import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';

import '../../hub/brand.dart';

/// Calculator and grapher for Canvas pages (prompt(math, …), prompt(graph, …)) and Jarvis.
class Maths {
  static final _parser = GrammarParser();

  static String _prep(String e) => e
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll('π', 'pi')
      .replaceAll('√', 'sqrt')
      .replaceAll(RegExp(r'\bpi\b'), '${math.pi}')
      .replaceAll(RegExp(r'(?<![a-z])e(?![a-z(])'), '${math.e}')
      .replaceAll('**', '^');

  static Expression parse(String e) => _parser.parse(_prep(e));

  static num eval(String expr, {double? x}) {
    final cm = ContextModel();
    if (x != null) cm.bindVariableName('x', Number(x));
    return RealEvaluator(cm).evaluate(parse(expr));
  }

  /// "2^10 + sqrt(144)" -> "1036". Errors come back as text.
  static String calc(String expr) {
    try {
      final v = eval(expr);
      if (v.isNaN) return 'undefined';
      if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
      return double.parse(v.toStringAsPrecision(12)).toString();
    } catch (e) {
      return 'Could not evaluate "$expr"';
    }
  }

  /// Simplified symbolic derivative with respect to x, e.g. "x^3" -> "3*x^2".
  static String derive(String expr) {
    try {
      return parse(expr).derive('x').simplify().toString();
    } catch (_) {
      return 'Could not differentiate "$expr"';
    }
  }

  /// Numeric definite integral (Simpson's rule).
  static String integrate(String expr, double a, double b) {
    try {
      const n = 1000;
      final h = (b - a) / n;
      var s = eval(expr, x: a) + eval(expr, x: b);
      for (var i = 1; i < n; i++) {
        s += eval(expr, x: a + i * h) * (i.isOdd ? 4 : 2);
      }
      return double.parse((s * h / 3).toStringAsPrecision(10)).toString();
    } catch (_) {
      return 'Could not integrate "$expr"';
    }
  }
}

/// y = f(x) plot, pinch to zoom.
class FunctionGraph extends StatefulWidget {
  final List<String> functions;
  final double height;
  const FunctionGraph({super.key, required this.functions, this.height = 220});
  @override
  State<FunctionGraph> createState() => _FunctionGraphState();
}

class _FunctionGraphState extends State<FunctionGraph> {
  double _span = 10, _cx = 0, _cy = 0, _start = 10;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (_) => _start = _span,
      onScaleUpdate: (d) => setState(() {
        _span = (_start / d.scale).clamp(0.5, 200);
        _cx -= d.focalPointDelta.dx * _span / 300;
        _cy += d.focalPointDelta.dy * _span / 300;
      }),
      onDoubleTap: () => setState(() { _span = 10; _cx = 0; _cy = 0; }),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(color: const Color(0xFF0E131B), borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CustomPaint(painter: _GraphPainter(widget.functions, _span, _cx, _cy), size: Size.infinite),
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<String> fns;
  final double span, cx, cy;
  _GraphPainter(this.fns, this.span, this.cx, this.cy);
  static const colors = [AssimilisBrand.green, AssimilisBrand.magenta, Color(0xFF42A5F5), Color(0xFFFFB300)];

  @override
  void paint(Canvas c, Size size) {
    final xMin = cx - span / 2, xMax = cx + span / 2;
    final ySpan = span * size.height / size.width;
    final yMin = cy - ySpan / 2, yMax = cy + ySpan / 2;
    Offset p(double x, double y) =>
        Offset((x - xMin) / (xMax - xMin) * size.width, size.height - (y - yMin) / (yMax - yMin) * size.height);
    final grid = Paint()..color = Colors.white10;
    final step = math.pow(10, (math.log(span) / math.ln10).floor()).toDouble();
    for (var x = (xMin / step).floor() * step; x <= xMax; x += step) {
      c.drawLine(p(x, yMin), p(x, yMax), grid);
    }
    for (var y = (yMin / step).floor() * step; y <= yMax; y += step) {
      c.drawLine(p(xMin, y), p(xMax, y), grid);
    }
    final axis = Paint()..color = Colors.white54..strokeWidth = 1.2;
    c.drawLine(p(xMin, 0), p(xMax, 0), axis);
    c.drawLine(p(0, yMin), p(0, yMax), axis);
    for (var i = 0; i < fns.length; i++) {
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      final path = Path();
      var pen = false;
      for (var px = 0.0; px <= size.width; px += 1.5) {
        final x = xMin + px / size.width * (xMax - xMin);
        double y;
        try {
          y = Maths.eval(fns[i], x: x).toDouble();
        } catch (_) {
          pen = false;
          continue;
        }
        if (!y.isFinite || y.abs() > 1e6) {
          pen = false;
          continue;
        }
        final o = p(x, y);
        pen ? path.lineTo(o.dx, o.dy) : path.moveTo(o.dx, o.dy);
        pen = true;
      }
      c.drawPath(path, paint);
      final tp = TextPainter(
          text: TextSpan(text: 'y = ${fns[i]}', style: TextStyle(color: colors[i % colors.length], fontSize: 12)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(c, Offset(8, 6 + i * 16.0));
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter o) => o.span != span || o.cx != cx || o.cy != cy || o.fns != fns;
}
