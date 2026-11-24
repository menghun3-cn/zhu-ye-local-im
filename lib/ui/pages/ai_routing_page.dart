import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
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
/// actually targets its provider and stays for a short while after, so a
/// catalogue of dozens does not have to fit — the canvas only ever draws
/// the nodes a request is using.
class AiRoutingView extends StatefulWidget {
  /// Builds the surface over [runtime]'s router and configuration.
  const AiRoutingView({super.key, required this.runtime, this.configLoader});

  final AiRuntime runtime;

  /// Where the configuration comes from; defaults to [AiRuntime.load].
  /// Injectable so a widget test can answer from memory instead of real
  /// file IO, which the fake-async test clock cannot advance.
  final Future<AiConfig> Function()? configLoader;

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
  final Map<String, DateTime> _nodeVisibleUntil = {};
  static const _nodeVisibleFor = Duration(seconds: 20);

  /// 1s heartbeat: expires health marks, refreshes cooldown countdowns, and
  /// notices configuration saves and gateway rebinds without a handshake.
  Timer? _ticker;
  int _seenVersion = 0;
  String _gatewaySignature = '';

  @override
  void initState() {
    super.initState();
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
    final providerId = AiModelRef.parse(event.member)?.providerId;
    if (providerId == null) return;
    _nodeVisibleUntil[providerId] = DateTime.now().add(_nodeVisibleFor);
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
    // A retry to the same member reuses its leaf rather than stacking a
    // second one on the same pixels. The match needs the member too: one
    // callId covers a whole failover chain, and the next member's attempt
    // must still get its own leaf.
    if (_flights.any(
      (f) => f.callId == event.callId && f.member == event.member,
    )) {
      return;
    }
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
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
        controller.dispose();
      }
    });
    _flights.add(flight);
    unawaited(controller.forward());
  }

  /// Flies every leaf of [event]'s call home. Failover produces one leaf per
  /// member, so the match is on the member, not just the call.
  void _returnHome(AiRouteEvent event) {
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
    // leaf is still flying to it, however long a stream runs.
    final now = DateTime.now();
    final visibleProviders = <String>{
      for (final provider in config.providers)
        if ((_nodeVisibleUntil[provider.id]?.isAfter(now) ?? false) ||
            _flights.any((f) => f.providerId == provider.id))
          provider.id,
    };
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: _RoutingCanvas(
            config: config,
            flights: _flights,
            visibleProviders: visibleProviders,
            sourceLabel: l10n.aiRoutingSource,
            gatewayLabel: l10n.aiRoutingGateway,
            gatewayAddress: _gatewayAddress(l10n),
            gatewayOnline: widget.runtime.gateway != null,
            health: _healthByProvider(config),
          ),
        ),
        _StatusBar(event: _last),
        Expanded(flex: 2, child: _RequestLogSection(records: _records)),
      ],
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
    required this.config,
    required this.flights,
    required this.visibleProviders,
    required this.sourceLabel,
    required this.gatewayLabel,
    required this.gatewayAddress,
    required this.gatewayOnline,
    required this.health,
  });

  final AiConfig config;
  final List<_LeafFlight> flights;

  /// Provider ids whose nodes are drawn — the ones a request has used
  /// recently, not the whole catalogue.
  final Set<String> visibleProviders;
  final String sourceLabel;
  final String gatewayLabel;
  final String gatewayAddress;
  final bool gatewayOnline;
  final Map<String, _NodeHealth> health;

  static const double _agentWidth = 104;
  static const double _gatewayWidth = 150;
  static const double _nodeWidth = 168;
  static const double _nodeHeight = 48;
  static const double _cardHeight = 76;
  static const double _margin = 16;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final providers = [
          for (final provider in config.providers)
            if (visibleProviders.contains(provider.id)) provider,
        ];
        final slots = providers.length;
        final slot = slots == 0
            ? size.height
            : math.max(56.0, size.height / slots);
        final providerLeft = size.width - _margin - _nodeWidth;
        Offset anchorFor(int index) =>
            Offset(providerLeft, _margin + slot * index + slot / 2);

        // Three columns: the agent on the left, the gateway centered in the
        // gap before the provider column on the right.
        final midY = size.height / 2;
        final agentOut = Offset(_margin + _agentWidth, midY);
        final gatewayLeft =
            agentOut.dx + (providerLeft - agentOut.dx - _gatewayWidth) / 2;
        final gatewayIn = Offset(gatewayLeft, midY);
        final gatewayCenter = Offset(gatewayLeft + _gatewayWidth / 2, midY);
        final gatewayOut = Offset(gatewayLeft + _gatewayWidth, midY);

        bool wireActive(String providerId) =>
            flights.any((f) => f.providerId == providerId);

        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _WirePainter(
                  segments: [
                    _WireSegment(
                      from: agentOut,
                      to: gatewayIn,
                      dashed: flights.isNotEmpty,
                    ),
                    for (var i = 0; i < slots; i++)
                      if (providers[i].enabled)
                        _WireSegment(
                          from: gatewayOut,
                          to: anchorFor(i),
                          dashed: wireActive(providers[i].id),
                        ),
                  ],
                  color: WeChatColors.of(context).brandLine,
                ),
              ),
            ),
            // Leaves under the cards: a leaf crossing the gateway node
            // slips beneath it, which reads as "through" rather than
            // "over".
            for (final flight in flights)
              _Leaf(
                flight: flight,
                agent: agentOut,
                gateway: gatewayCenter,
                target: _targetAnchor(flight, providers, anchorFor),
              ),
            // Provider nodes first so the cards sit on top of any wire
            // that happens to pass under them.
            for (var i = 0; i < slots; i++)
              Positioned(
                left: providerLeft,
                top: _margin + slot * i + (slot - _nodeHeight) / 2,
                width: _nodeWidth,
                height: _nodeHeight,
                child: _ProviderNode(
                  provider: providers[i],
                  enabled: providers[i].enabled,
                  health: health[providers[i].id],
                ),
              ),
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
              left: _margin,
              top: midY - _cardHeight / 2,
              width: _agentWidth,
              height: _cardHeight,
              child: _SourceNode(label: sourceLabel),
            ),
          ],
        );
      },
    );
  }

  /// Where [flight]'s leaf is headed: its provider's anchor, or [Offset.zero]
  /// when the provider is not in the list (it was deleted mid-flight — the
  /// leaf still comes home, just to nowhere).
  Offset _targetAnchor(
    _LeafFlight flight,
    List<AiProvider> providers,
    Offset Function(int) anchorFor,
  ) {
    for (var i = 0; i < providers.length; i++) {
      if (providers[i].id == flight.providerId) return anchorFor(i);
    }
    return Offset.zero;
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
/// marker, so the route a request is taking reads at a glance.
final class _WireSegment {
  const _WireSegment({
    required this.from,
    required this.to,
    required this.dashed,
  });

  final Offset from;
  final Offset to;
  final bool dashed;
}

class _WirePainter extends CustomPainter {
  _WirePainter({required this.segments, required this.color});

  final List<_WireSegment> segments;
  final Color color;

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
        _drawDashed(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  /// 5px dash, 4px gap, extracted along the path's own metrics so the dashes
  /// follow the curve instead of a straight bounding box.
  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 5, metric.length)),
          paint,
        );
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_WirePainter old) =>
      old.color != color || !_sameSegments(old.segments, segments);

  bool _sameSegments(List<_WireSegment> a, List<_WireSegment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.from != y.from || x.to != y.to || x.dashed != y.dashed) {
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.brandSoft,
        borderRadius: BorderRadius.circular(WeChat.controlRadius),
        border: Border.all(color: colors.brandLine),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bolt_outlined, size: 22, color: colors.brandStrong),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(WeChat.controlRadius),
          border: Border.all(color: colors.brandLine),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.eco, size: 22, color: const Color(0xFF2E9E5B)),
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
              style: TextStyle(fontSize: 11, color: colors.secondaryText),
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
  });

  final AiProvider provider;
  final bool enabled;
  final _NodeHealth? health;

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
        ? const Color(0xFFB26A00)
        : colors.danger;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(WeChat.controlRadius),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              provider.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: WeChat.fontSizePreview,
                fontWeight: FontWeight.w600,
                color: colors.brandStrong,
              ),
            ),
            Text(
              status ?? l10n.aiProviderModelCount(enabledModels),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: status == null ? colors.secondaryText : statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The flying leaf: an [Icons.eco] glyph positioned each frame along its
/// route — agent → gateway → provider on the way out, back again on
/// return. Position comes from the controller's value; rotation sways
/// gently so the leaf reads as fluttering rather than sliding.
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
    return AnimatedBuilder(
      animation: flight.controller,
      builder: (context, _) {
        final t = flight.controller.value;
        // Two hops: the first half of the trip ends at the gateway's
        // center, the second half continues to the provider.
        final point = t <= 0.5
            ? _bezierPoint(agent, gateway, t * 2)
            : _bezierPoint(gateway, target, (t - 0.5) * 2);
        final sway = math.sin(t * math.pi * 2) * 0.35;
        return Positioned(
          left: point.dx - 11,
          top: point.dy - 11,
          child: Transform.rotate(
            angle: sway,
            child: const Icon(Icons.eco, size: 22, color: Color(0xFF2E9E5B)),
          ),
        );
      },
    );
  }

  Offset _bezierPoint(Offset from, Offset to, double t) {
    final points = _wirePoints(from, to);
    return _bezier(points[0], points[1], points[2], points[3], t);
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
                style: TextStyle(fontSize: 11, color: colors.secondaryText),
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
                  separatorBuilder: (_, index) => const SizedBox(height: 6),
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

  static String _duration(int ms) =>
      ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';

  static String _tokens(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    final caption = TextStyle(fontSize: 11, color: colors.secondaryText);
    final body = TextStyle(fontSize: WeChat.fontSizePreview);

    // Speed is completion tokens over generation time — the span after the
    // first token. Without a TTFT (non-streamed replies) the whole
    // duration is the generation span.
    final ttft = record.ttftMs;
    final genMs = ttft == null
        ? record.durationMs
        : math.max(1, record.durationMs - ttft);
    final completion = record.completionTokens;
    final speed = completion == null ? null : completion * 1000 / genMs;

    final metrics = [
      '${l10n.aiMetricDuration} ${_duration(record.durationMs)}',
      '${l10n.aiMetricFirstToken} '
          '${record.ttftMs == null ? '—' : _duration(record.ttftMs!)}',
      '${l10n.aiMetricTokens} '
          '${record.totalTokens == null ? '—' : _tokens(record.totalTokens!)}',
      '${l10n.aiMetricCached} '
          '${record.cachedTokens == null ? '—' : _tokens(record.cachedTokens!)}',
      '${l10n.aiMetricSpeed} '
          '${speed == null ? '—' : '${speed.toStringAsFixed(0)} tok/s'}',
    ].join(' · ');

    return Column(
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
          child: Text(
            metrics,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: caption,
          ),
        ),
      ],
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
        (event.cooling ? ('⏳', const Color(0xFFB26A00)) : ('✗', colors.danger)),
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
