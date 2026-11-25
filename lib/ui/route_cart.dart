import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The flying cart: a horse silhouette pulling a two-wheel dray, drawn
/// in one colour (the per-callId shade) so concurrent requests stay
/// tellable apart. [loaded] stacks sacks in the bed — the reply coming
/// home — and [spin] turns the wheel spokes with the trip's progress.
class RouteCart extends StatelessWidget {
  const RouteCart({
    super.key,
    required this.color,
    required this.loaded,
    required this.spin,
  });

  final Color color;
  final bool loaded;
  final double spin;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(44, 28),
    painter: RouteCartPainter(color: color, loaded: loaded, spin: spin),
  );
}

/// Side-view mule-and-dray in a 44×28 design space, facing right — the
/// widget flips horizontally on the return leg. Everything is stroked
/// or filled in [color]; sacks use a darkened shade so the cargo reads
/// against the pale bed.
class RouteCartPainter extends CustomPainter {
  RouteCartPainter({
    required this.color,
    required this.loaded,
    required this.spin,
  });

  final Color color;
  final bool loaded;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final hsl = HSLColor.fromColor(color);
    final sackColor = hsl
        .withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0))
        .toColor();
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final solid = Paint()..color = color;
    final sack = Paint()..color = sackColor;

    // Cargo first: the bed's front rail overlaps the sacks' bottoms so
    // they sit *in* the bed rather than on top of it.
    if (loaded) {
      for (final c in [
        const Offset(6.5, 12.4),
        const Offset(10.5, 11.8),
        const Offset(14.5, 12.4),
      ]) {
        canvas.drawCircle(c, 2.3, sack);
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
    // The shaft tying horse to cart.
    canvas.drawLine(const Offset(16, 17), const Offset(23.5, 16), line);

    // The mule: filled silhouette — body, neck, head — over stroked
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
    for (final leg in [
      const Offset(26.3, 17.6),
      const Offset(29.0, 17.9),
      const Offset(31.8, 17.9),
      const Offset(34.6, 17.6),
    ]) {
      canvas.drawLine(leg, Offset(leg.dx + (leg.dx - 29.5) * 0.12, 26.4), line);
    }
    // Tail.
    canvas.drawLine(const Offset(23.6, 13.6), const Offset(22.2, 17.4), line);
  }

  @override
  bool shouldRepaint(RouteCartPainter old) =>
      old.color != color || old.loaded != loaded || old.spin != spin;
}
