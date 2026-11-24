import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../l10n/generated/app_localizations.dart';
import '../wechat/theme.dart';
import '../widgets.dart';

/// The routing surface: which providers a request can reach, drawn as wires,
/// with a bamboo leaf flying the wire while a request is in flight.
///
/// The picture is a view over [AiRouter.events] — the same stream any future
/// in-app chat will feed — so a request the gateway serves and one the app
/// makes itself look identical here. The leaf is the whole point: a list of
/// providers says what *can* be routed, the flight says what *is* being
/// routed, right now.
///
/// This is an embeddable view, not a route: the AI settings page shows it
/// inline at the top, where "what is being asked" belongs above the
/// configuration that decides it. It needs a bounded height from its parent.
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
        with
        TickerProviderStateMixin {
  AiConfig? _config;
  Object? _failure;
  StreamSubscription<AiRouteEvent>? _events;
  final List<_LeafFlight> _flights = [];
  AiRouteEvent? _last;

  @override
  void initState() {
    super.initState();
    _events = widget.runtime.router.events.listen(_onEvent);
    unawaited(_reload());
  }

  @override
  void dispose() {
    unawaited(_events?.cancel() ?? Future.value());
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
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  void _onEvent(AiRouteEvent event) {
    if (!mounted) return;
    setState(() => _last = event);
    if (MediaQuery.disableAnimationsOf(context)) return;
    switch (event.phase) {
      case AiRoutePhase.attempt:
        _depart(event);
      case AiRoutePhase.served:
      case AiRoutePhase.failed:
        _returnHome(event);
    }
  }

  /// Sends a leaf along the wire to [event]'s provider, if the provider is
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
    for (final flight in _flights) {
      if (flight.callId == event.callId && flight.member == event.member) {
        unawaited(flight.controller.reverse());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
    return Column(
      children: [
        Expanded(
          child: _RoutingCanvas(
            config: config,
            flights: _flights,
            sourceLabel: l10n.aiRoutingSource,
          ),
        ),
        _StatusBar(event: _last),
      ],
    );
  }
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

/// The wires and the nodes they join. Positions are computed from the
/// [LayoutBuilder] constraints on every build, so a window resize simply
/// re-anchors everything — the animations ride along because they only own
/// a 0→1 progress value, never a pixel position.
class _RoutingCanvas extends StatelessWidget {
  const _RoutingCanvas({
    required this.config,
    required this.flights,
    required this.sourceLabel,
  });

  final AiConfig config;
  final List<_LeafFlight> flights;
  final String sourceLabel;

  static const double _sourceWidth = 132;
  static const double _nodeWidth = 168;
  static const double _nodeHeight = 48;
  static const double _margin = 16;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final providers = config.providers;
        final slots = providers.length;
        final slot = slots == 0
            ? size.height
            : math.max(56.0, size.height / slots);
        Offset anchorFor(int index) => Offset(
          size.width - _margin - _nodeWidth,
          _margin + slot * index + slot / 2,
        );
        final source = Offset(_margin + _sourceWidth, size.height / 2);
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _WirePainter(
                  source: source,
                  targets: [
                    for (var i = 0; i < slots; i++)
                      if (providers[i].enabled) anchorFor(i),
                  ],
                  color: WeChatColors.of(context).brandLine,
                ),
              ),
            ),
            // Provider nodes first so the source card sits on top of any
            // wire that happens to pass under it.
            for (var i = 0; i < slots; i++)
              Positioned(
                left: size.width - _margin - _nodeWidth,
                top: _margin + slot * i + (slot - _nodeHeight) / 2,
                width: _nodeWidth,
                height: _nodeHeight,
                child: _ProviderNode(
                  provider: providers[i],
                  enabled: providers[i].enabled,
                ),
              ),
            Positioned(
              left: _margin,
              top: size.height / 2 - _nodeHeight / 2 - 12,
              width: _sourceWidth,
              height: _nodeHeight + 24,
              child: _SourceNode(label: sourceLabel),
            ),
            for (final flight in flights)
              _Leaf(
                flight: flight,
                source: source,
                target: _targetAnchor(flight, providers, anchorFor),
              ),
          ],
        );
      },
    );
  }

  /// Where [flight]'s leaf is headed: its provider's anchor, or the canvas
  /// bottom edge when the provider is not in the list (it was deleted
  /// mid-flight — the leaf still comes home, just to nowhere).
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

/// The four control points of the wire's cubic: start, two handles at the
/// horizontal thirds, end. Shared by the painter and the leaf so the leaf
/// rides exactly on the line it is flying.
List<Offset> _wirePoints(Offset from, Offset to) {
  final dx = (to.dx - from.dx) / 3;
  return [from, Offset(from.dx + dx, from.dy), Offset(to.dx - dx, to.dy), to];
}

class _WirePainter extends CustomPainter {
  _WirePainter({
    required this.source,
    required this.targets,
    required this.color,
  });

  final Offset source;
  final List<Offset> targets;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final target in targets) {
      final points = _wirePoints(source, target);
      canvas.drawPath(
        Path()
          ..moveTo(points[0].dx, points[0].dy)
          ..cubicTo(
            points[1].dx,
            points[1].dy,
            points[2].dx,
            points[2].dy,
            points[3].dx,
            points[3].dy,
          ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WirePainter old) =>
      old.source != source ||
      old.color != color ||
      old.targets.length != targets.length ||
      !_samePoints(old.targets, targets);

  bool _samePoints(List<Offset> a, List<Offset> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return a.length == b.length;
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
          Icon(Icons.hub_outlined, size: 22, color: colors.brandStrong),
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

class _ProviderNode extends StatelessWidget {
  const _ProviderNode({required this.provider, required this.enabled});

  final AiProvider provider;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    final enabledModels = provider.models.where((m) => m.enabled).length;
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
              l10n.aiProviderModelCount(enabledModels),
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

/// The flying leaf: an [Icons.eco] glyph positioned each frame along its
/// flight's bezier. Position comes from the controller's value; rotation
/// sways gently so the leaf reads as fluttering rather than sliding.
class _Leaf extends StatelessWidget {
  const _Leaf({
    required this.flight,
    required this.source,
    required this.target,
  });

  final _LeafFlight flight;
  final Offset source;
  final Offset target;

  @override
  Widget build(BuildContext context) {
    if (target == Offset.zero) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: flight.controller,
      builder: (context, _) {
        final t = flight.controller.value;
        final points = _wirePoints(source, target);
        final point = _bezier(points[0], points[1], points[2], points[3], t);
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
      AiRoutePhase.failed => ('✗', colors.danger),
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
