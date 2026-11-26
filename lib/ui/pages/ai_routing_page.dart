import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../ai_provider_mark.dart';
import '../l10n/generated/app_localizations.dart';
import '../wechat/theme.dart';
import '../widgets.dart';

/// The routing surface: which providers a request can reach, drawn as wires
/// through the local gateway, with a bamboo leaf flying the route while a
/// request is in flight.
///
/// The picture is a view over [AiRouter.events] — the same stream any future
/// in-app chat will feed — so a request the gateway serves and one the app
/// makes itself look identical here. The leaf is the whole point: a list of
/// providers says what *can* be routed, the flight says what *is* being
/// routed, right now.
///
/// This is an embeddable view, not a route: the AI page shows it as its
/// first tab, at full height. It needs a bounded height from its parent.
///
/// Provider nodes are earned, not listed: a node appears when a request
/// actually targets its provider and stays for five minutes after the
/// last one, so a catalogue of dozens does not have to fit — the canvas
/// only ever draws the nodes a request is using.
class AiRoutingView extends StatefulWidget {
  /// Builds the surface over [runtime]'s router and configuration.
  const AiRoutingView({
    super.key,
    required this.runtime,
    this.configLoader,
    this.onProviderTap,
  });

  final AiRuntime runtime;

  /// Where the configuration comes from; defaults to [AiRuntime.load].
  /// Injectable so a widget test can answer from memory instead of real
  /// file IO, which the fake-async test clock cannot advance.
  final Future<AiConfig> Function()? configLoader;

  /// Called with a provider id when its canvas node is tapped — the host
  /// page uses it to jump to that provider's editor.
  final void Function(String providerId)? onProviderTap;

  @override
  State<AiRoutingView> createState() => _AiRoutingViewState();
}

class _AiRoutingViewState extends State<AiRoutingView>
        // Plural: each in-flight request owns its leaf's controller, and a
        // single-ticker mixin would refuse the second concurrent flight.
        // Keep-alive: the view is a tab child, and a request in flight must
        // not lose its leaf — or its node marks — because the user looked
        // at the Providers tab for a moment.
        with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin {
  AiConfig? _config;
  Object? _failure;
  StreamSubscription<AiRouteEvent>? _events;
  final List<_LeafFlight> _flights = [];

  /// Attempts that arrived while a leaf was still flying home. A serial
  /// caller fires its next request the moment the reply lands — during
  /// the homeward leg — and launching then would put two leaves on screen
  /// travelling opposite ways for what reads as one sequential exchange.
  /// They wait for the last homeward leaf to dock; outbound leaves may
  /// still overlap freely, so genuine concurrency is unaffected.
  final List<AiRouteEvent> _pendingDepartures = [];
  AiRouteEvent? _last;

  /// Finished requests, newest first — the log under the canvas.
  List<AiRequestRecord> _records = const [];
  int _seenLogVersion = 0;

  /// member ref → when its cooldown ends. Seeded from the router on load so
  /// a cooldown that began before the page opened still shows.
  final Map<String, DateTime> _coolingUntil = {};

  /// member ref → when it last failed fatally. Shown briefly, then cleared —
  /// a stale "failed" badge is worse than none.
  final Map<String, DateTime> _erroredAt = {};
  static const _errorVisibleFor = Duration(seconds: 30);

  /// provider id → when its node stops being drawn. See the class doc: the
  /// canvas shows only providers a request has actually used recently.
  /// Five minutes, not seconds: a node that vanishes the moment a reply
  /// lands reads as "the request never happened" — the linger is what lets
  /// the log row and the picture agree about the same request.
  final Map<String, DateTime> _nodeVisibleUntil = {};
  static const _nodeVisibleFor = Duration(minutes: 5);

  /// provider ids in first-requested order — each keeps a fixed slot on the
  /// canvas so a node appearing or expiring never slides its neighbours.
  /// Capped: past this many distinct providers the spacing would squeeze
  /// nodes into each other, and the canvas is a "what is being asked" view,
  /// not a catalogue.
  final List<String> _slotOrder = [];
  static const _maxSlots = 10;

  /// 1s heartbeat: expires health marks, refreshes cooldown countdowns, and
  /// notices configuration saves and gateway rebinds without a handshake.
  Timer? _ticker;
  int _seenVersion = 0;
  String _gatewaySignature = '';

  /// Drives the marching-dash flow on in-flight wires. Repeats only while
  /// a leaf is flying — an idle canvas does not burn frames.
  late final AnimationController _dashController;

  /// provider id → the model id its latest route event named, so a node
  /// can say *which* model is being asked, not just which provider.
  final Map<String, String> _modelByProvider = {};

  @override
  void initState() {
    super.initState();
    _dashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _seenVersion = widget.runtime.configVersion;
    _seenLogVersion = widget.runtime.requestLog.version;
    _events = widget.runtime.router.events.listen(_onEvent);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(_reload());
    unawaited(_loadRecords());
  }

  @override
  void dispose() {
    unawaited(_events?.cancel() ?? Future.value());
    _ticker?.cancel();
    _dashController.dispose();
    for (final flight in _flights) {
      flight.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final config = await (widget.configLoader ?? widget.runtime.load)();
      if (mounted) {
        setState(() {
          _config = config;
          _failure = null;
          _seenVersion = widget.runtime.configVersion;
          // Deleted providers leave stale slots behind; pruning keeps the
          // spacing honest without moving live nodes.
          _slotOrder.removeWhere((id) => config.providerNamed(id) == null);
          _modelByProvider.removeWhere((providerId, modelId) {
            final provider = config.providerNamed(providerId);
            return provider == null || provider.modelNamed(modelId) == null;
          });
          _seedHealth(config);
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  /// Reads the request log newest-first. [AiRequestLog.version] is the
  /// cheap change signal — the file itself is only touched when it moves.
  Future<void> _loadRecords() async {
    final log = widget.runtime.requestLog;
    final records = await log.load();
    records.sort((a, b) => b.at.compareTo(a.at));
    if (mounted) {
      setState(() {
        _records = records;
        _seenLogVersion = log.version;
      });
    }
  }

  /// Every concrete `provider/model` the config can currently route to.
  static Iterable<String> _memberRefs(AiConfig config) sync* {
    for (final provider in config.providers) {
      if (!provider.enabled) continue;
      for (final model in provider.models) {
        if (model.enabled) yield '${provider.id}/${model.id}';
      }
    }
  }

  /// Pulls live cooldown state out of the router for every routable member.
  void _seedHealth(AiConfig config) {
    final now = DateTime.now();
    _coolingUntil.removeWhere((_, until) => until.isBefore(now));
    for (final ref in _memberRefs(config)) {
      final until = widget.runtime.router.coolingDownUntil(ref);
      if (until == null) {
        _coolingUntil.remove(ref);
      } else {
        _coolingUntil[ref] = until;
      }
    }
  }

  /// Every route event — attempt, served or failed — is proof the provider
  /// was asked for, so it earns (or renews) its node's place on the canvas.
  void _noteNodeActivity(AiRouteEvent event) {
    final ref = AiModelRef.parse(event.member);
    final providerId = ref?.providerId;
    if (providerId == null) return;
    final modelId = ref?.modelId;
    if (modelId != null) _modelByProvider[providerId] = modelId;
    _nodeVisibleUntil[providerId] = DateTime.now().add(_nodeVisibleFor);
    if (!_slotOrder.contains(providerId) && _slotOrder.length < _maxSlots) {
      _slotOrder.add(providerId);
    }
  }

  void _recordHealth(AiRouteEvent event) {
    switch (event.phase) {
      case AiRoutePhase.attempt:
      case AiRoutePhase.served:
        // Being tried — or having answered — clears both marks.
        _coolingUntil.remove(event.member);
        _erroredAt.remove(event.member);
      case AiRoutePhase.failed:
        if (event.cooling) {
          _coolingUntil[event.member] = DateTime.now().add(
            widget.runtime.router.cooldown,
          );
          _erroredAt.remove(event.member);
        } else {
          _erroredAt[event.member] = DateTime.now();
        }
    }
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    var dirty = false;
    if (widget.runtime.configVersion != _seenVersion) {
      _seenVersion = widget.runtime.configVersion;
      unawaited(_reload());
      dirty = true;
    }
    final signature = _gatewaySig();
    if (signature != _gatewaySignature) {
      _gatewaySignature = signature;
      dirty = true;
    }
    if (widget.runtime.requestLog.version != _seenLogVersion) {
      unawaited(_loadRecords());
    }
    final hadMarks =
        _coolingUntil.isNotEmpty ||
        _erroredAt.isNotEmpty ||
        _nodeVisibleUntil.isNotEmpty;
    _coolingUntil.removeWhere((_, until) => until.isBefore(now));
    _erroredAt.removeWhere((_, at) => now.difference(at) > _errorVisibleFor);
    _nodeVisibleUntil.removeWhere((_, until) => until.isBefore(now));
    if (_flights.isEmpty) _dashController.stop();
    // Rebuild while marks live (the countdown needs a fresh second), and
    // once more when the last mark expires so the badge actually clears.
    if (dirty ||
        hadMarks ||
        _coolingUntil.isNotEmpty ||
        _erroredAt.isNotEmpty ||
        _nodeVisibleUntil.isNotEmpty) {
      setState(() {});
    }
  }

  String _gatewaySig() {
    final gateway = widget.runtime.gateway;
    if (gateway == null) return 'off';
    return '${gateway.actualPort}|${gateway.scope.name}|'
        '${widget.runtime.lanAddresses.join(',')}';
  }

  void _onEvent(AiRouteEvent event) {
    if (!mounted) return;
    setState(() {
      _last = event;
      _noteNodeActivity(event);
      _recordHealth(event);
    });
    if (MediaQuery.disableAnimationsOf(context)) return;
    switch (event.phase) {
      case AiRoutePhase.attempt:
        _depart(event);
      case AiRoutePhase.served:
      case AiRoutePhase.failed:
        _returnHome(event);
    }
  }

  /// Sends a leaf along the route to [event]'s provider, if the provider is
  /// one this page can draw. A member whose provider vanished mid-request
  /// (deleted while in flight) gets no leaf — there is no wire to fly.
  void _depart(AiRouteEvent event) {
    final providerId = AiModelRef.parse(event.member)?.providerId;
    final config = _config;
    if (providerId == null || config == null) return;
    if (config.providerNamed(providerId) == null) return;
    // A provider past the slot cap earns its visibility mark but no canvas
    // position — a leaf with no node to land on would fly invisible while
    // still tripping the "request in flight" dashed wire.
    if (!_slotOrder.contains(providerId)) return;
    // A retry to the same member reuses its leaf rather than stacking a
    // second one on the same pixels. The match needs the member too: one
    // callId covers a whole failover chain, and the next member's attempt
    // must still get its own leaf.
    if (_flights.any(
      (f) => f.callId == event.callId && f.member == event.member,
    )) {
      return;
    }
    // Queue behind any homeward leaf — see _pendingDepartures.
    if (_flights.any((f) => f.controller.status == AnimationStatus.reverse)) {
      _pendingDepartures.add(event);
      return;
    }
    _launch(event, providerId);
  }

  void _launch(AiRouteEvent event, String providerId) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    late final _LeafFlight flight;
    flight = _LeafFlight(
      callId: event.callId,
      member: event.member,
      providerId: providerId,
      controller: controller,
    );
    controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        setState(() => _flights.remove(flight));
        if (_flights.isEmpty) _dashController.stop();
        controller.dispose();
        _flushDepartures();
      }
    });
    _flights.add(flight);
    _dashController.repeat();
    unawaited(controller.forward());
  }

  /// Runs queued departures once no leaf is flying home. Each queued event
  /// goes back through [_depart] so provider/slot/dedup checks re-run —
  /// the config may have changed while the leaf was airborne.
  void _flushDepartures() {
    if (_pendingDepartures.isEmpty ||
        _flights.any((f) => f.controller.status == AnimationStatus.reverse)) {
      return;
    }
    final pending = List<AiRouteEvent>.of(_pendingDepartures);
    _pendingDepartures.clear();
    for (final event in pending) {
      _depart(event);
    }
  }

  /// Flies every leaf of [event]'s call home. Failover produces one leaf per
  /// member, so the match is on the member, not just the call.
  void _returnHome(AiRouteEvent event) {
    // A request that ended while its attempt still sat in the departure
    // queue never earned a leaf — launching it now would fly out and
    // park at the provider forever, no second end event is coming.
    _pendingDepartures.removeWhere(
      (e) => e.callId == event.callId && e.member == event.member,
    );
    // A copy: reverse() on a leaf that never left completes synchronously,
    // and its dismissal listener removes it from _flights mid-iteration.
    for (final flight in [..._flights]) {
      if (flight.callId == event.callId && flight.member == event.member) {
        unawaited(flight.controller.reverse());
      }
    }
  }

  /// Worst-first health per provider: any cooling member marks the node
  /// cooling, else any recently-failed member marks it failed.
  Map<String, _NodeHealth> _healthByProvider(AiConfig config) {
    final health = <String, _NodeHealth>{};
    final now = DateTime.now();
    for (final provider in config.providers) {
      var cooling = false;
      var seconds = 0;
      var error = false;
      for (final model in provider.models) {
        if (!model.enabled) continue;
        final ref = '${provider.id}/${model.id}';
        final until = _coolingUntil[ref];
        if (until != null) {
          cooling = true;
          seconds = math.max(seconds, until.difference(now).inSeconds);
        } else if (_erroredAt.containsKey(ref)) {
          error = true;
        }
      }
      health[provider.id] = _NodeHealth(
        cooling: cooling,
        coolingSeconds: seconds,
        error: error,
      );
    }
    return health;
  }

  /// `ip:port` the gateway answers on — the LAN address under LAN scope,
  /// loopback otherwise — or the not-listening hint while it is down.
  String _gatewayAddress(AppLocalizations l10n) {
    final gateway = widget.runtime.gateway;
    final port = gateway?.actualPort;
    if (gateway == null || port == null) return l10n.aiGatewayNotListening;
    final host =
        gateway.scope == AiGatewayScope.lan &&
            widget.runtime.lanAddresses.isNotEmpty
        ? widget.runtime.lanAddresses.first
        : '127.0.0.1';
    return '$host:$port';
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final config = _config;
    if (config == null) {
      return Center(
        child: _failure == null
            ? const CircularProgressIndicator()
            : HintText('${l10n.aiLoadFailed}: $_failure'),
      );
    }
    if (config.providers.isEmpty) {
      return Center(child: HintText(l10n.aiRoutingEmpty));
    }
    // A provider keeps its node while it was asked recently — or while a
    // leaf is still flying to it, however long a stream runs. Visible nodes
    // render in slot order, not request order, so nothing slides when a
    // neighbour expires.
    final now = DateTime.now();
    final visibleIds = <String>{
      for (final provider in config.providers)
        if ((_nodeVisibleUntil[provider.id]?.isAfter(now) ?? false) ||
            _flights.any((f) => f.providerId == provider.id))
          provider.id,
    };
    final orderedProviders = [
      for (final id in _slotOrder)
        if (visibleIds.contains(id)) config.providerNamed(id),
    ].whereType<AiProvider>().toList();
    // Active providers past the slot cap get no node and no leaf — the
    // canvas says so rather than letting their requests look ignored.
    final overflow = visibleIds.where((id) => !_slotOrder.contains(id)).length;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The log keeps a usable floor: on a short window the canvas gives
        // way first (it is the flex child), but the request list never
        // shrinks to a sliver — below ~120px its two-line rows are unreadable.
        final logHeight = math.min(
          math.max(constraints.maxHeight * 0.4, 120.0),
          math.max(120.0, constraints.maxHeight * 0.6),
        );
        return Column(
          children: [
            Expanded(
              flex: 3,
              child: _RoutingCanvas(
                slotOrder: _slotOrder,
                providers: orderedProviders,
                flights: _flights,
                dash: _dashController,
                modelByProvider: _modelByProvider,
                sourceLabel: l10n.aiRoutingSource,
                gatewayLabel: l10n.aiRoutingGateway,
                gatewayAddress: _gatewayAddress(l10n),
                gatewayOnline: widget.runtime.gateway != null,
                health: _healthByProvider(config),
                overflowLabel: overflow == 0
                    ? null
                    : l10n.aiRoutingMoreProviders(overflow),
                onProviderTap: widget.onProviderTap,
              ),
            ),
            _StatusBar(event: _last),
            // The log sits in its own bordered panel so the record list
            // reads as a bounded region under the canvas, not a bare
            // strip bleeding into the page background.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                height: logHeight,
                decoration: BoxDecoration(
                  color: WeChatColors.of(context).surface,
                  border: Border.all(
                    color: WeChatColors.of(context).borderStrong,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: _RequestLogSection(records: _records),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Per-provider rollup of its members' route health.
final class _NodeHealth {
  const _NodeHealth({
    required this.cooling,
    required this.coolingSeconds,
    required this.error,
  });

  final bool cooling;
  final int coolingSeconds;
  final bool error;
}

/// One leaf's flight state: which call it belongs to, which member it is
/// flying to, and the controller whose value is the trip's progress.
final class _LeafFlight {
  _LeafFlight({
    required this.callId,
    required this.member,
    required this.providerId,
    required this.controller,
  });

  final int callId;
  final String member;
  final String providerId;
  final AnimationController controller;
}

/// The wires and the nodes they join: Agent → gateway → each provider. The
/// gateway node splits what used to be one long hop into two short ones, so
/// every wire is roughly half its old length. Positions are computed from
/// the [LayoutBuilder] constraints on every build, so a window resize simply
/// re-anchors everything — the animations ride along because they only own
/// a 0→1 progress value, never a pixel position.
class _RoutingCanvas extends StatelessWidget {
  const _RoutingCanvas({
    required this.slotOrder,
    required this.providers,
    required this.flights,
    required this.sourceLabel,
    required this.gatewayLabel,
    required this.gatewayAddress,
    required this.gatewayOnline,
    required this.health,
    this.dash,
    this.modelByProvider = const {},
    this.overflowLabel,
    this.onProviderTap,
  });

  /// provider ids in fixed slot order — a node's vertical position is its
  /// index here, so appearing and expiring nodes never move their neighbours.
  final List<String> slotOrder;

  /// The providers currently drawn, already in [slotOrder] order.
  final List<AiProvider> providers;
  final List<_LeafFlight> flights;
  final String sourceLabel;
  final String gatewayLabel;
  final String gatewayAddress;
  final bool gatewayOnline;
  final Map<String, _NodeHealth> health;

  /// Repeating 0→1 phase that slides the dash pattern on in-flight wires.
  /// Null keeps the dashes static (tests, or a host that never flies leaves).
  final Animation<double>? dash;

  /// provider id → model id from its latest route event; the node shows
  /// that model's name while the provider is on the canvas.
  final Map<String, String> modelByProvider;

  /// Tap on a provider node — forwarded from [AiRoutingView.onProviderTap].
  final void Function(String providerId)? onProviderTap;

  /// Caption for providers that were asked recently but hold no canvas
  /// slot (past [_maxSlots]) — null when every active provider is drawn.
  final String? overflowLabel;

  static const double _agentWidth = 185;
  static const double _gatewayWidth = 267;
  static const double _nodeWidth = 299;
  static const double _nodeHeight = 85;
  static const double _cardHeight = 143;
  static const double _margin = 16;

  /// The narrowest canvas that still fits all three columns with the
  /// fallback (tight) segment spacing — below it the view scrolls
  /// horizontally instead of squeezing nodes into each other.
  static const double _minContentWidth =
      2 * _margin + _agentWidth + 2 * 8 + _gatewayWidth + _nodeWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // Three columns need a floor: below it the fallback spacing would
        // squeeze the provider column into the gateway node. Rather than
        // overlap, the canvas keeps its minimum width and scrolls.
        final width = math.max(size.width, _minContentWidth);
        final slots = slotOrder.length;
        // Slots divide the height *between* the margins, so the first and
        // last nodes keep their breathing room at any count.
        final slot = slots == 0
            ? size.height
            : math.max(_nodeHeight + 8.0, (size.height - 2 * _margin) / slots);

        // Three columns with each hop half the length it used to be: the
        // whole agent→gateway→provider group is centered, so shrinking the
        // wires leaves equal air on both sides instead of piling up against
        // the right edge.
        final midY = size.height / 2;
        final span =
            width - 2 * _margin - _agentWidth - _gatewayWidth - _nodeWidth;
        var segment = math.max(24.0, span / 4);
        var groupWidth = _agentWidth + 2 * segment + _gatewayWidth + _nodeWidth;
        var startX = (width - groupWidth) / 2;
        if (startX < _margin || groupWidth > width - 2 * _margin) {
          // Too narrow for the airy layout — fall back to edge-to-edge.
          segment = math.max(8.0, (span - _gatewayWidth) / 2);
          groupWidth = _agentWidth + 2 * segment + _gatewayWidth + _nodeWidth;
          startX = _margin;
        }
        // Never let a squeezed layout push the provider column off-canvas.
        final providerLeft = math.min(
          startX + groupWidth - _nodeWidth,
          width - _margin - _nodeWidth,
        );
        Offset anchorFor(String providerId) {
          final index = slotOrder.indexOf(providerId);
          if (index < 0) return Offset.zero;
          return Offset(providerLeft, _margin + slot * index + slot / 2);
        }

        final agentOut = Offset(startX + _agentWidth, midY);
        final gatewayLeft = agentOut.dx + segment;
        final gatewayIn = Offset(gatewayLeft, midY);
        final gatewayCenter = Offset(gatewayLeft + _gatewayWidth / 2, midY);
        final gatewayOut = Offset(gatewayLeft + _gatewayWidth, midY);

        bool wireActive(String providerId) =>
            flights.any((f) => f.providerId == providerId);

        // "Answering" means the request is still being served: any
        // flight that has not started its way home — outbound leg and
        // the parked stretch at the provider both count. Once the leaf
        // turns around the reply already arrived, so the mark lifts.
        bool answering(String providerId) => flights.any(
          (f) =>
              f.providerId == providerId &&
              f.controller.status != AnimationStatus.reverse,
        );

        // The leaf's mid-route waypoint arcs over the gateway card
        // instead of crossing its face: the waypoint sits one card
        // half-height plus margin above or below the gateway centre —
        // the side the provider node is on — so both hops keep their
        // horizontal end tangents and the path crests clear of the card.
        Offset gatewayWaypoint(Offset target) {
          if (target == Offset.zero) return gatewayCenter;
          final side = target.dy >= midY ? 1.0 : -1.0;
          return Offset(gatewayCenter.dx, midY + side * (_cardHeight / 2 + 48));
        }

        final wireColor = WeChatColors.of(context).brandLine;
        final dashAnimation = dash;
        // The wire layer rebuilds on every animation tick: the dash
        // phase for the flow, and each leaf's live 0→1 progress for
        // which leg it is actually on — a dashed wire must mean "a leaf
        // is on this segment right now", not merely "some request
        // targets this provider".
        final wireTicks = <Listenable>[
          ?dashAnimation,
          for (final flight in flights) flight.controller,
        ];

        CustomPaint wires(double phase) {
          // Leg occupancy from live controller values: t ≤ 0.5 rides
          // agent→gateway, t > 0.5 rides gateway→provider, on both the
          // outbound and the return trip. A segment flows forward only
          // while every leaf on it travels forward.
          var agentGwFwd = false;
          var agentGwBack = false;
          final providerFwd = <String>{};
          final providerBack = <String>{};
          for (final flight in flights) {
            final returning =
                flight.controller.status == AnimationStatus.reverse;
            if (flight.controller.value <= 0.5) {
              if (returning) {
                agentGwBack = true;
              } else {
                agentGwFwd = true;
              }
            } else if (returning) {
              providerBack.add(flight.providerId);
            } else {
              providerFwd.add(flight.providerId);
            }
          }
          return CustomPaint(
            painter: _WirePainter(
              segments: [
                _WireSegment(
                  from: agentOut,
                  to: gatewayIn,
                  dashed: agentGwFwd || agentGwBack,
                  reverse: agentGwBack && !agentGwFwd,
                ),
                for (final provider in providers)
                  if (provider.enabled)
                    _WireSegment(
                      from: gatewayOut,
                      to: anchorFor(provider.id),
                      dashed:
                          providerFwd.contains(provider.id) ||
                          providerBack.contains(provider.id),
                      reverse:
                          providerBack.contains(provider.id) &&
                          !providerFwd.contains(provider.id),
                    ),
              ],
              color: wireColor,
              dashPhase: phase,
            ),
          );
        }

        final stack = Stack(
          children: [
            Positioned.fill(
              child: wireTicks.isEmpty
                  ? wires(0)
                  : AnimatedBuilder(
                      animation: Listenable.merge(wireTicks),
                      builder: (context, _) => wires(dashAnimation?.value ?? 0),
                    ),
            ),
            // Provider nodes first so the cards sit on top of any wire
            // that happens to pass under them.
            for (final provider in providers) ...[
              Positioned(
                left: providerLeft,
                top:
                    _margin +
                    slot * slotOrder.indexOf(provider.id) +
                    (slot - _nodeHeight) / 2,
                width: _nodeWidth,
                height: _nodeHeight,
                child: _ProviderNode(
                  provider: provider,
                  enabled: provider.enabled,
                  health: health[provider.id],
                  activeModelId: modelByProvider[provider.id],
                  breathing: dash != null && wireActive(provider.id),
                  breath: dash,
                  onTap: onProviderTap == null
                      ? null
                      : () => onProviderTap!(provider.id),
                ),
              ),
              // A live "answering" mark beside the card — a long stream
              // must not read as an unresponsive node. Sits just right
              // of the card, vertically centered on it.
              if (answering(provider.id))
                Positioned(
                  left: providerLeft + _nodeWidth + 8,
                  top:
                      _margin +
                      slot * slotOrder.indexOf(provider.id) +
                      (slot - _nodeHeight) / 2,
                  height: _nodeHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      AppLocalizations.of(context).aiRoutingAnswering,
                      style: TextStyle(
                        fontSize: WeChat.fontSizeMeta,
                        fontWeight: FontWeight.w600,
                        color: WeChatColors.of(context).brandStrong,
                      ),
                    ),
                  ),
                ),
            ],
            Positioned(
              left: gatewayLeft,
              top: midY - _cardHeight / 2,
              width: _gatewayWidth,
              height: _cardHeight,
              child: _GatewayNode(
                label: gatewayLabel,
                address: gatewayAddress,
                online: gatewayOnline,
              ),
            ),
            Positioned(
              left: startX,
              top: midY - _cardHeight / 2,
              width: _agentWidth,
              height: _cardHeight,
              child: _SourceNode(label: sourceLabel),
            ),
            // Leaves ride on top of every node: the waypoint is the
            // gateway's center, so a leaf crosses the card's face —
            // under the cards it would vanish mid-trip.
            for (final flight in flights)
              _Leaf(
                flight: flight,
                agent: agentOut,
                gateway: gatewayWaypoint(anchorFor(flight.providerId)),
                target: anchorFor(flight.providerId),
              ),
            if (overflowLabel != null)
              Positioned(
                right: _margin,
                bottom: 4,
                child: Text(
                  overflowLabel!,
                  style: TextStyle(
                    fontSize: WeChat.fontSizeMeta,
                    color: WeChatColors.of(context).secondaryText,
                  ),
                ),
              ),
          ],
        );
        // Below the minimum content width the canvas scrolls sideways —
        // overlapping nodes would be a worse answer than a scrollbar.
        if (width > size.width) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: width, height: size.height, child: stack),
          );
        }
        return stack;
      },
    );
  }
}

/// Cubic bezier point at [t], shared by the wire painter and the leaf so
/// the leaf rides exactly on the line it is flying.
Offset _bezier(Offset p0, Offset c1, Offset c2, Offset p3, double t) {
  final u = 1 - t;
  final a = u * u * u;
  final b = 3 * u * u * t;
  final c = 3 * u * t * t;
  final d = t * t * t;
  return Offset(
    a * p0.dx + b * c1.dx + c * c2.dx + d * p3.dx,
    a * p0.dy + b * c1.dy + c * c2.dy + d * p3.dy,
  );
}

/// The four control points of a wire's cubic: start, two handles at the
/// horizontal thirds, end. Shared by the painter and the leaf so the leaf
/// rides exactly on the line it is flying.
List<Offset> _wirePoints(Offset from, Offset to) {
  final dx = (to.dx - from.dx) / 3;
  return [from, Offset(from.dx + dx, from.dy), Offset(to.dx - dx, to.dy), to];
}

/// One wire: [from] → [to], drawn dashed while [dashed] — the in-flight
/// marker, so the route a request is taking reads at a glance. [reverse]
/// flips the dash flow: a leaf on the way home travels the segment
/// backwards, and the dashes should march the way it does.
final class _WireSegment {
  const _WireSegment({
    required this.from,
    required this.to,
    required this.dashed,
    this.reverse = false,
  });

  final Offset from;
  final Offset to;
  final bool dashed;
  final bool reverse;
}

class _WirePainter extends CustomPainter {
  _WirePainter({
    required this.segments,
    required this.color,
    this.dashPhase = 0,
  });

  final List<_WireSegment> segments;
  final Color color;

  /// 0→1 loop position of the dash pattern. Each cycle slides the dashes
  /// one period (9px) toward the provider, so a wire carrying a request
  /// reads as flowing rather than merely dashed.
  final double dashPhase;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final segment in segments) {
      final points = _wirePoints(segment.from, segment.to);
      final path = Path()
        ..moveTo(points[0].dx, points[0].dy)
        ..cubicTo(
          points[1].dx,
          points[1].dy,
          points[2].dx,
          points[2].dy,
          points[3].dx,
          points[3].dy,
        );
      if (segment.dashed) {
        _drawDashed(canvas, path, paint, reversed: segment.reverse);
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  /// 5px dash, 4px gap, extracted along the path's own metrics so the dashes
  /// follow the curve instead of a straight bounding box. [dashPhase] shifts
  /// the whole pattern along the path — increasing it moves the dashes
  /// toward `to`; [reversed] runs the flow the other way, for leaves on the
  /// way home.
  void _drawDashed(
    Canvas canvas,
    Path path,
    Paint paint, {
    bool reversed = false,
  }) {
    final shift = reversed ? ((-dashPhase * 9) % 9) : ((dashPhase * 9) % 9);
    for (final metric in path.computeMetrics()) {
      var distance = shift - 9;
      while (distance < metric.length) {
        final start = math.max(0.0, distance);
        final end = math.min(distance + 5, metric.length);
        if (end > start) {
          canvas.drawPath(metric.extractPath(start, end), paint);
        }
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_WirePainter old) =>
      old.color != color ||
      old.dashPhase != dashPhase ||
      !_sameSegments(old.segments, segments);

  bool _sameSegments(List<_WireSegment> a, List<_WireSegment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.from != y.from ||
          x.to != y.to ||
          x.dashed != y.dashed ||
          x.reverse != y.reverse) {
        return false;
      }
    }
    return true;
  }
}

class _SourceNode extends StatelessWidget {
  const _SourceNode({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 15),
      decoration: BoxDecoration(
        color: colors.brandSoft,
        borderRadius: BorderRadius.circular(WeChat.controlRadius),
        border: Border.all(color: colors.brandLine),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bolt_outlined, size: 39, color: colors.brandStrong),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: WeChat.fontSizePreview,
              color: colors.brandStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// The local gateway hop every routed request passes through. Shows the
/// address callers actually dial — `ip:port` — and dims while nothing is
/// listening, so "configured but down" is visible on the picture itself.
class _GatewayNode extends StatelessWidget {
  const _GatewayNode({
    required this.label,
    required this.address,
    required this.online,
  });

  final String label;
  final String address;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return Opacity(
      opacity: online ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 15),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(WeChat.controlRadius),
          border: Border.all(color: colors.brandLine),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.eco, size: 39, color: colors.brandStrong),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: WeChat.fontSizePreview,
                fontWeight: FontWeight.w600,
                color: colors.brandStrong,
              ),
            ),
            Text(
              address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: WeChat.fontSizeMeta,
                color: colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderNode extends StatelessWidget {
  const _ProviderNode({
    required this.provider,
    required this.enabled,
    this.health,
    this.activeModelId,
    this.breathing = false,
    this.breath,
    this.onTap,
  });

  final AiProvider provider;
  final bool enabled;
  final _NodeHealth? health;

  /// A request is in flight to this provider right now — the card breathes
  /// (a soft pulsing glow) until the leaf comes home.
  final bool breathing;

  /// The shared 0→1 phase driving the breathing pulse; the same controller
  /// that marches the dashes, so glow and flow share one "requests live"
  /// clock and both stop when the last leaf docks.
  final Animation<double>? breath;

  /// The model id from this provider's latest route event. When set and
  /// the node is healthy, the second line names that concrete model —
  /// "which model answered" — under the provider's own name.
  final String? activeModelId;

  /// Opens the provider's editor on the host page; null makes the node
  /// inert (used by callers that embed the canvas without a page).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    final enabledModels = provider.models.where((m) => m.enabled).length;
    final nodeHealth = health;
    final status = nodeHealth == null
        ? null
        : nodeHealth.cooling
        ? l10n.aiRoutingCooling(nodeHealth.coolingSeconds)
        : nodeHealth.error
        ? l10n.aiRoutingFailed
        : null;
    final statusColor = nodeHealth != null && nodeHealth.cooling
        ? colors.warning
        : colors.danger;
    final modelId = activeModelId;
    final model = modelId == null ? null : provider.modelNamed(modelId);
    final modelLabel = model == null ? modelId : (model.label ?? model.id);
    // Breathing: while a leaf is flying to this provider, a soft glow
    // swells and fades on an ~800ms sine — "being asked right now" reads
    // at a glance without a badge. The phase comes from the shared dash
    // controller, so the pulse and the marching dashes stay in step.
    Widget card = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(WeChat.controlRadius),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AiProviderMark(
                  provider: provider,
                  color: colors.brandStrong,
                  size: 25,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    provider.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: WeChat.fontSizePreview,
                      fontWeight: FontWeight.w600,
                      color: colors.brandStrong,
                    ),
                  ),
                ),
              ],
            ),
            // Health outranks the model name: a cooling or failed node
            // says so even while a model is on it. Healthy nodes show
            // the concrete model that was last asked, falling back to
            // the enabled-model count.
            Text(
              status ?? modelLabel ?? l10n.aiProviderModelCount(enabledModels),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: WeChat.fontSizeMeta,
                color: status == null ? colors.secondaryText : statusColor,
              ),
            ),
          ],
        ),
      ),
    );
    final breathAnimation = breath;
    if (breathing && breathAnimation != null) {
      final still = card;
      card = AnimatedBuilder(
        animation: breathAnimation,
        builder: (context, _) {
          // Sine over one dash cycle: 0→1→0, eased so the swell reads as
          // a breath rather than a blink.
          final pulse =
              0.5 - 0.5 * math.cos(breathAnimation.value * 2 * math.pi);
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WeChat.controlRadius + 3),
              boxShadow: [
                BoxShadow(
                  color: colors.brandStrong.withValues(
                    alpha: 0.12 + 0.30 * pulse,
                  ),
                  blurRadius: 4 + 8 * pulse,
                  spreadRadius: 0.5 + pulse,
                ),
              ],
            ),
            child: still,
          );
        },
      );
    }
    final onTap = this.onTap;
    if (onTap == null) return card;
    return Tooltip(
      message: modelLabel == null
          ? provider.name
          : '${provider.name} · $modelLabel',
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}

/// The flying leaf: an [Icons.eco] glyph riding the route — agent →
/// gateway → provider on the way out, back again on return. The leaf
/// carries a solid bead outbound (the request) and a hollow one home
/// (the reply), sways as it flies, and dissolves into each end node:
/// opacity follows the eased trip progress so it fades out as it lands
/// on the provider and fades back in as the return leg pulls away —
/// a leaf parked at its node would read as a stuck request.
class _Leaf extends StatelessWidget {
  const _Leaf({
    required this.flight,
    required this.agent,
    required this.gateway,
    required this.target,
  });

  final _LeafFlight flight;
  final Offset agent;
  final Offset gateway;
  final Offset target;

  @override
  Widget build(BuildContext context) {
    if (target == Offset.zero) return const SizedBox.shrink();
    final colors = WeChatColors.of(context);
    // Concurrent requests each get their own leaf, and identical green
    // leaves made two in-flight calls look like one. The shade is a pure
    // function of callId, so a failover's members — same call, different
    // providers — stay the same colour while unrelated calls differ.
    final leafColor = _leafColor(colors.brandStrong, flight.callId);
    return AnimatedBuilder(
      animation: flight.controller,
      builder: (context, _) {
        final t = flight.controller.value;
        // Cosine ease-in-out: the leaf launches and docks gently rather
        // than sliding at constant speed. The leg split still reads the
        // raw controller value, which crosses 0.5 at the same instant.
        final te = (1 - math.cos(math.pi * t)) / 2;
        // Two hops: the first half of the trip ends at the gateway's
        // center, the second half continues to the provider.
        final point = te <= 0.5
            ? _bezierPoint(agent, gateway, te * 2)
            : _bezierPoint(gateway, target, (te - 0.5) * 2);
        final sway = math.sin(t * math.pi * 2) * 0.35;
        final returning = flight.controller.status == AnimationStatus.reverse;
        // Dissolve at both ends of the trip: fully transparent at the
        // nodes (te 0 and 1), fully opaque through the middle. While the
        // request sits at the provider the leaf is invisible; the return
        // leg fades it back in as it pulls away.
        final opacity = (math.min(te, 1 - te) / 0.15).clamp(0.0, 1.0);
        return Positioned(
          left: point.dx - 11,
          top: point.dy - 11,
          child: Opacity(
            opacity: opacity,
            child: Transform.rotate(
              angle: sway,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // The key doubles as the test hook: 'leaf-out' outbound,
                  // 'leaf-back' (hollow bead) on the way home.
                  Icon(
                    Icons.eco,
                    key: ValueKey(returning ? 'leaf-back' : 'leaf-out'),
                    size: 22,
                    color: leafColor,
                  ),
                  Positioned(
                    left: 15,
                    top: -4,
                    child: _CargoBead(color: leafColor, hollow: returning),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Distinct-but-related shades of the brand green, indexed by callId:
  /// four lightness steps crossed with two saturation steps gives eight
  /// combinations before a repeat. Hue stays brand so a crowd of leaves
  /// still reads as "the app's leaf", just tellable apart.
  static const _lightnessSteps = [-0.09, 0.09, -0.18, 0.18];
  static const _saturationSteps = [-0.12, 0.12];

  static Color _leafColor(Color base, int callId) {
    final hsl = HSLColor.fromColor(base);
    final slot = callId % (_lightnessSteps.length * _saturationSteps.length);
    final lightness =
        (hsl.lightness + _lightnessSteps[slot % _lightnessSteps.length]).clamp(
          0.0,
          1.0,
        );
    final saturation =
        (hsl.saturation + _saturationSteps[slot ~/ _lightnessSteps.length])
            .clamp(0.0, 1.0);
    return hsl.withLightness(lightness).withSaturation(saturation).toColor();
  }

  Offset _bezierPoint(Offset from, Offset to, double t) {
    final points = _wirePoints(from, to);
    return _bezier(points[0], points[1], points[2], points[3], t);
  }
}

/// The bead a leaf carries: filled on the way out (the request), a ring
/// on the way back (the reply). Same colour as its leaf so the pairing
/// survives the per-callId shading. Both variants get a keyline in the
/// page background — a same-colour bead against a same-colour leaf and
/// wires was nearly invisible at 7px.
class _CargoBead extends StatelessWidget {
  const _CargoBead({required this.color, required this.hollow});

  final Color color;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    final keyline = WeChatColors.of(context).pageBackground;
    return Container(
      key: ValueKey(hollow ? 'bead-hollow' : 'bead-solid'),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hollow ? null : color,
        border: Border.all(
          color: hollow ? color : keyline,
          width: hollow ? 2.4 : 1.4,
        ),
      ),
    );
  }
}

/// The request history under the canvas: the last 7 days of finished
/// requests, newest first. Each record is two lines — when and which model
/// on the first, the timing and token metrics on the second — so a glance
/// down the column reads like a table.
class _RequestLogSection extends StatelessWidget {
  const _RequestLogSection({required this.records});

  final List<AiRequestRecord> records;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Text(
                l10n.aiRequestsTitle,
                style: TextStyle(
                  fontSize: WeChat.fontSizePreview,
                  fontWeight: FontWeight.w600,
                  color: colors.brandStrong,
                ),
              ),
              const Spacer(),
              Text(
                l10n.aiRequestsWindow,
                style: TextStyle(
                  fontSize: WeChat.fontSizeMeta,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: records.isEmpty
              ? Center(child: HintText(l10n.aiRequestsEmpty))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  itemCount: records.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _RequestTile(record: records[index]),
                ),
        ),
      ],
    );
  }
}

/// One log row: `MM-dd HH:mm:ss  model` over the metric line. The timestamp
/// gets its own fixed-width column so the models line up vertically.
class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.record});

  final AiRequestRecord record;

  static String _pad(int v) => v.toString().padLeft(2, '0');

  static String _dateTime(DateTime t) =>
      '${_pad(t.month)}-${_pad(t.day)} '
      '${_pad(t.hour)}:${_pad(t.minute)}:${_pad(t.second)}';

  static String _tokens(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  /// Output tokens per second over the *decode* span — completion
  /// tokens divided by the time after the first token arrived, so a
  /// slow-thinking upstream does not read as a slow generator. Rows
  /// without a completion split (or without any post-TTFT time) show
  /// `—`: totalTokens would count the prompt and wildly overstate it.
  String _speed() {
    final tokens = record.completionTokens;
    if (tokens == null) return '—';
    final ttft = record.ttftMs;
    final decodeMs = ttft != null
        ? record.durationMs - ttft
        : record.durationMs;
    if (decodeMs <= 0) return '—';
    return (tokens / (decodeMs / 1000)).toStringAsFixed(1);
  }

  /// `1,433` — the tooltip's exact counts read better grouped than compact.
  static String _grouped(int n) {
    final digits = n.abs().toString();
    final buf = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    final caption = TextStyle(
      fontSize: WeChat.fontSizeMeta,
      color: colors.secondaryText,
    );
    final body = TextStyle(fontSize: WeChat.fontSizePreview);

    String seconds(int ms) => l10n.aiLogSeconds((ms / 1000).toStringAsFixed(1));

    final ttft = record.ttftMs;
    // Older rows (and upstreams that report only total/completion) lack a
    // prompt count; derive it so cache-hit math still renders. Inconsistent
    // totals derive to null rather than a negative count.
    int? prompt;
    if (record.promptTokens != null) {
      prompt = record.promptTokens;
    } else if (record.totalTokens != null && record.completionTokens != null) {
      final derived = record.totalTokens! - record.completionTokens!;
      prompt = derived > 0 ? derived : null;
    }
    final cached = record.cachedTokens;
    final percent = prompt != null && prompt > 0 && cached != null
        ? '${(cached * 100 / prompt).round()}%'
        : '—';
    final metrics = l10n.aiLogMetrics(
      seconds(record.durationMs),
      ttft == null ? '—' : seconds(ttft),
      record.totalTokens == null ? '—' : _tokens(record.totalTokens!),
      percent,
      _speed(),
    );

    // Hover detail: the exact token split behind the compact line — what
    // was read from cache, what was written to it, and what was billed fresh.
    final uncachedInput = prompt == null
        ? '—'
        : _grouped(math.max(0, prompt - (cached ?? 0)));
    final tooltip = [
      '${l10n.aiLogInputUncached}: $uncachedInput',
      '${l10n.aiLogOutput}: '
          '${record.completionTokens == null ? '—' : _grouped(record.completionTokens!)}',
      '${l10n.aiLogCacheRead}: ${cached == null ? '—' : _grouped(cached)}',
      '${l10n.aiLogCacheWrite}: '
          '${_grouped(record.cacheWriteTokens ?? 0)}',
    ].join('\n');

    // Each record is its own card inside the log panel: sunken fill and a
    // hairline border keep rows readable as separate entries at a glance.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        border: Border.all(color: colors.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(_dateTime(record.at), style: caption),
              ),
              Expanded(
                child: Text(
                  record.servedBy ?? record.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 96),
            child: Tooltip(
              message: tooltip,
              child: Text(
                metrics,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: caption,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one-line status under the canvas: the most recent route event,
/// phrased as "member ✓ / ✗ / →".
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.event});

  final AiRouteEvent? event;

  @override
  Widget build(BuildContext context) {
    final event = this.event;
    if (event == null) return const SizedBox.shrink();
    final colors = WeChatColors.of(context);
    final (mark, color) = switch (event.phase) {
      AiRoutePhase.attempt => ('→', colors.secondaryText),
      AiRoutePhase.served => ('✓', colors.brandStrong),
      AiRoutePhase.failed =>
        (event.cooling ? ('⏳', colors.warning) : ('✗', colors.danger)),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        '$mark ${event.member}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: WeChat.fontSizePreview, color: color),
      ),
    );
  }
}
