import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The flying cart: a horse silhouette pulling a two-wheel dray, drawn
/// in one colour (the per-callId shade) so concurrent requests stay
/// tellable apart. [loaded] stacks sacks in the bed — the reply coming
/// home — [spin] turns the wheel spokes with the trip's progress, and
/// [gallop] is the stride clock: radians of leg swing, advancing with
/// wall-clock animation time rather than trip progress so the gait never
/// plays backwards on the return leg.
class RouteCart extends StatelessWidget {
  const RouteCart({
    super.key,
    required this.color,
    required this.loaded,
    required this.spin,
    required this.gallop,
  });

  final Color color;
  final bool loaded;
  final double spin;
  final double gallop;

  @override
  Widget build(BuildContext context) => CustomPaint(
    // Double the on-canvas presence: the design space stays 44×28 and
    // the painter scales it up, so every coordinate below is unchanged.
    size: const Size(88, 56),
    painter: RouteCartPainter(
      color: color,
      loaded: loaded,
      spin: spin,
      gallop: gallop,
    ),
  );
}

/// Side-view horse-and-dray in a 44×28 design space, facing right — the
/// widget flips horizontally on the return leg. Everything is stroked
/// or filled in [color]; sacks use a darkened shade so the cargo reads
/// against the pale bed.
class RouteCartPainter extends CustomPainter {
  RouteCartPainter({
    required this.color,
    required this.loaded,
    required this.spin,
    required this.gallop,
  });

  final Color color;
  final bool loaded;
  final double spin;
  final double gallop;

  /// One leg: a quadratic stroke from [hip] to a hoof that swings fore
  /// and aft with [phase] and lifts as it passes under the body — the
  /// lift peaks at mid-stance so planted feet stay planted.
  void _leg(Canvas canvas, Offset hip, double phase, Paint paint) {
    final swing = math.sin(phase) * 4.4;
    final lift = math.max(0.0, math.cos(phase)) * 1.5;
    final hoof = Offset(hip.dx + swing, 26.9 - lift);
    final mid = Offset(
      (hip.dx + hoof.dx) / 2 + 1.1,
      (hip.dy + hoof.dy) / 2 - 0.6,
    );
    canvas.drawPath(
      Path()
        ..moveTo(hip.dx, hip.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, hoof.dx, hoof.dy),
      paint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 44, size.height / 28);

    final hsl = HSLColor.fromColor(color);
    final sackColor = hsl
        .withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0))
        .toColor();
    final sackEdge = Paint()
      ..color = sackColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Far-side legs sit a touch dimmer and thinner — depth without a
    // second colour.
    final farLeg = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    // Near legs run a touch heavier than the cart's outline — at flying
    // size they are the "it is running" cue and must not read as wire.
    final nearLeg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final solid = Paint()..color = color;
    final sack = Paint()..color = sackColor;

    // Cargo first: the bed's front rail overlaps the sacks' bottoms so
    // they sit *in* the bed rather than on top of it. Five outlined
    // sacks in a two-tier heap — bottom row three, top row two — so the
    // load reads as parcels, not dots.
    if (loaded) {
      for (final c in [
        const Offset(6.3, 12.7),
        const Offset(10.3, 12.4),
        const Offset(14.3, 12.7),
        const Offset(8.3, 9.5),
        const Offset(12.3, 9.5),
      ]) {
        canvas.drawCircle(c, 2.6, sack);
        canvas.drawCircle(c, 2.6, sackEdge);
      }
    }

    // The dray: an open-topped bed on two spoked wheels.
    canvas.drawRect(const Rect.fromLTWH(3, 15, 13, 6), line);
    for (final cx in [7.0, 13.0]) {
      final hub = Offset(cx, 24.3);
      canvas.drawCircle(hub, 3.3, line);
      canvas.save();
      canvas.translate(hub.dx, hub.dy);
      canvas.rotate(spin);
      for (var i = 0; i < 3; i++) {
        canvas.drawLine(Offset.zero, const Offset(0, -2.4), line);
        canvas.rotate(math.pi * 2 / 3);
      }
      canvas.restore();
      canvas.drawCircle(hub, 0.9, solid);
    }
    // The shaft tying horse to cart — behind the body, like the real
    // thing.
    canvas.drawLine(const Offset(16, 17), const Offset(23.5, 16), line);

    // Trot gait: diagonal pairs share a phase — the near-front leg with
    // the far-rear, the near-rear with the far-front — so the near side
    // shows the classic alternating run. Far legs draw first, under the
    // body; near legs after it.
    _leg(canvas, const Offset(25.7, 17.15), gallop, farLeg);
    _leg(canvas, const Offset(34.3, 17.15), gallop + math.pi, farLeg);

    // The horse: filled silhouette — body, neck, head — over stroked
    // legs, so it reads as an animal and not a diagram.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(29.5, 14.2), width: 13, height: 7.4),
      solid,
    );
    canvas.drawLine(
      const Offset(34, 11.8),
      const Offset(39, 8.6),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round,
    );
    // Head as a forward wedge — poll, nose, jaw — so the silhouette
    // reads "animal facing the direction of travel", not a blob.
    canvas.drawPath(
      Path()
        ..moveTo(37.5, 10.6)
        ..lineTo(40.8, 6.6)
        ..lineTo(43.6, 7.4)
        ..lineTo(44.2, 9.0)
        ..lineTo(40.2, 11.6)
        ..close(),
      solid,
    );

    _leg(canvas, const Offset(27.5, 17.45), gallop + math.pi + 0.3, nearLeg);
    _leg(canvas, const Offset(32.5, 17.45), gallop, nearLeg);

    // Tail: a curve whose sway counter-phases the stride — the tail
    // trails, it does not march.
    final tailSway = math.sin(gallop + 2.2) * 1.3;
    canvas.drawPath(
      Path()
        ..moveTo(23.6, 13.6)
        ..quadraticBezierTo(21.4 + tailSway, 15.4, 22.0 + tailSway * 0.6, 17.6),
      line,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(RouteCartPainter old) =>
      old.color != color ||
      old.loaded != loaded ||
      old.spin != spin ||
      old.gallop != gallop;
}
