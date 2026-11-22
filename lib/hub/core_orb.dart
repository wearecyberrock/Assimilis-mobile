import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brand.dart';

enum CoreMood { idle, listening, thinking, speaking }

/// The Core: Assimilis's mascot. A magenta heart inside a white eye ring, energy cracks, tilted violet
/// orbits carrying light, and a ticked outer ring. Animated; still when reduced motion is on.
class CoreOrb extends StatefulWidget {
  final double size;
  final CoreMood mood;
  final double level; // 0..1 voice level (listening / speaking)
  final bool animate;
  const CoreOrb({super.key, this.size = 220, this.mood = CoreMood.idle, this.level = 0, this.animate = true});

  @override
  State<CoreOrb> createState() => _CoreOrbState();
}

class _CoreOrbState extends State<CoreOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 30));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = !widget.animate || MediaQuery.maybeOf(context)?.disableAnimations == true;
    if (still) {
      _c.stop();
      _c.value = 0.137;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: CorePainter(_c.value * 30, widget.mood, widget.level)),
        ),
      ),
    );
  }
}

/// Paints the Core at time [t] seconds. Public so icons and screenshots can render a still frame.
class CorePainter extends CustomPainter {
  final double t;
  final CoreMood mood;
  final double level;
  CorePainter(this.t, [this.mood = CoreMood.idle, this.level = 0]);

  static const _violet = AssimilisBrand.violet;
  static const _magenta = AssimilisBrand.magenta;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final speed = switch (mood) {
      CoreMood.thinking => 2.6,
      CoreMood.listening => 1.3,
      CoreMood.speaking => 1.6,
      CoreMood.idle => 1.0,
    };
    final tt = t * speed;
    final beat = switch (mood) {
      CoreMood.listening => level,
      CoreMood.speaking => 0.5 + 0.5 * math.sin(t * 14).abs() * (0.4 + level),
      CoreMood.thinking => 0.35 + 0.15 * math.sin(t * 6),
      CoreMood.idle => 0.25 + 0.1 * math.sin(t * 1.6),
    };

    // 1. Halo
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          _magenta.withValues(alpha: 0.55 + 0.25 * beat),
          _violet.withValues(alpha: 0.28),
          _violet.withValues(alpha: 0.06),
          Colors.transparent,
        ], stops: const [0.0, 0.32, 0.62, 1.0])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // 2. Outer ticked ring (slowly turning) and a broken arc ring
    final tick = Paint()
      ..color = _violet.withValues(alpha: 0.75)
      ..strokeWidth = math.max(1, r * 0.012)
      ..strokeCap = StrokeCap.round;
    const ticks = 120;
    for (var i = 0; i < ticks; i++) {
      final a = i / ticks * 2 * math.pi + tt * 0.05;
      final long = i % 10 == 0;
      final r1 = r * 0.93, r2 = r * (long ? 0.86 : 0.9);
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r1, c + Offset(math.cos(a), math.sin(a)) * r2,
          tick..color = (long ? _magenta : _violet).withValues(alpha: long ? 0.9 : 0.55));
    }
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.02
      ..strokeCap = StrokeCap.round
      ..color = _violet.withValues(alpha: 0.85)
      ..maskFilter = MaskFilter.blur(BlurStyle.solid, r * 0.02);
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.8), -tt * 0.18 + i * 2 * math.pi / 3, 0.9, false, arc);
    }

    // 3. Tilted orbits with travelling light
    const orbits = 7; // seven, like the seven arms of the old icon
    for (var i = 0; i < orbits; i++) {
      final tilt = i * math.pi / orbits + tt * 0.04 * (i.isEven ? 1 : -1);
      final rx = r * (0.62 + 0.04 * (i % 3));
      final ry = rx * (0.22 + 0.1 * (i % 4));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(tilt);
      final orbit = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, r * 0.006)
        ..color = (i.isEven ? _violet : AssimilisBrand.violetSoft).withValues(alpha: 0.55)
        ..blendMode = BlendMode.plus;
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), orbit);
      // two particles per orbit
      for (var k = 0; k < 2; k++) {
        final a = tt * (0.5 + i * 0.07) + k * math.pi + i;
        final p = Offset(math.cos(a) * rx, math.sin(a) * ry);
        canvas.drawCircle(p, r * 0.035, Paint()
          ..color = _magenta.withValues(alpha: 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.03));
        canvas.drawCircle(p, r * 0.012, Paint()..color = Colors.white);
      }
      canvas.restore();
    }

    // 4. Energy cracks from the heart
    final crack = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, r * 0.01)
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.75 + 0.25 * beat)
      ..maskFilter = MaskFilter.blur(BlurStyle.solid, r * 0.012);
    final rnd = math.Random(7);
    const cracks = 14;
    for (var i = 0; i < cracks; i++) {
      final a0 = i / cracks * 2 * math.pi + rnd.nextDouble() * 0.3;
      var p = c + Offset(math.cos(a0), math.sin(a0)) * r * 0.2;
      final path = Path()..moveTo(p.dx, p.dy);
      final reach = r * (0.36 + 0.1 * rnd.nextDouble()) * (0.85 + 0.3 * beat);
      const steps = 4;
      for (var s = 1; s <= steps; s++) {
        final jitter = (rnd.nextDouble() - 0.5) * 0.5 + 0.12 * math.sin(t * 9 + i * 3 + s);
        final a = a0 + jitter;
        p = c + Offset(math.cos(a), math.sin(a)) * (r * 0.2 + reach * s / steps * 0.6);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, crack);
    }

    // 5. Inner dotted ring
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.85);
    const dots = 36;
    for (var i = 0; i < dots; i++) {
      final a = i / dots * 2 * math.pi - tt * 0.3;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * 0.27, r * 0.008, dot);
    }

    // 6. The eye: white disc, magenta heart with highlight
    final eye = r * (0.2 + 0.025 * beat);
    canvas.drawCircle(c, eye * 1.25, Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06));
    canvas.drawCircle(c, eye, Paint()
      ..shader = const RadialGradient(colors: [Color(0xFFFFFFFF), Color(0xFFF3E8FF)])
          .createShader(Rect.fromCircle(center: c, radius: eye)));
    canvas.drawCircle(c, eye, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.012
      ..color = _violet.withValues(alpha: 0.6));
    final heart = eye * (0.32 + 0.12 * beat);
    canvas.drawCircle(c, heart * 1.6, Paint()
      ..color = _magenta.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, heart));
    canvas.drawCircle(c, heart, Paint()..color = _magenta);
    canvas.drawCircle(c + Offset(-heart * 0.35, -heart * 0.35), heart * 0.32, Paint()..color = const Color(0xFFFF8AC2));
  }

  @override
  bool shouldRepaint(covariant CorePainter o) => o.t != t || o.mood != mood || o.level != level;
}
