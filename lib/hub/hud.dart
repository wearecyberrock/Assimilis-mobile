import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brand.dart';

/// HES-style building blocks shared by the Assimilis screens.

/// A graphite panel with glowing corner brackets (the HES "system window").
class HudPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color accent;
  final String? title;
  final Widget? trailing;
  final VoidCallback? onTap;
  const HudPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.accent = AssimilisBrand.violet,
    this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: padding,
      child: title == null
          ? child
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(title!.toUpperCase(), style: AssimilisBrand.label(12, color: AssimilisBrand.text))),
                if (trailing != null) trailing!,
              ]),
              const SizedBox(height: 10),
              child,
            ]),
    );
    return CustomPaint(
      foregroundPainter: _Brackets(accent),
      child: Container(
        decoration: BoxDecoration(
          color: AssimilisBrand.panel,
          border: Border.all(color: AssimilisBrand.line),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.08), blurRadius: 18)],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: onTap == null ? body : InkWell(onTap: onTap, splashColor: accent.withValues(alpha: 0.12), child: body),
        ),
      ),
    );
  }
}

class _Brackets extends CustomPainter {
  final Color color;
  _Brackets(this.color);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const l = 14.0;
    c.drawPath(Path()..moveTo(0, l)..lineTo(0, 0)..lineTo(l, 0), p);
    c.drawPath(Path()..moveTo(s.width - l, s.height)..lineTo(s.width, s.height)..lineTo(s.width, s.height - l), p);
  }

  @override
  bool shouldRepaint(covariant _Brackets o) => o.color != color;
}

/// Glowing section header: "STATUS", "DAILY QUESTS".
class HudHeader extends StatelessWidget {
  final String text;
  final Color color;
  final Widget? trailing;
  const HudHeader(this.text, {super.key, this.color = AssimilisBrand.violet, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
        child: Row(children: [
          Container(width: 3, height: 14, color: color, margin: const EdgeInsets.only(right: 8)),
          Expanded(
            child: Text(text.toUpperCase(),
                style: AssimilisBrand.label(13, color: color, w: FontWeight.w700)
                    .copyWith(shadows: [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 10)])),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Screen scaffold in the Assimilis style: graphite, centred glowing title.
class HudScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? floatingActionButton;
  const HudScaffold({super.key, required this.title, this.subtitle, required this.body, this.actions, this.bottom, this.floatingActionButton});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AssimilisBrand.theme(),
      child: Scaffold(
        backgroundColor: AssimilisBrand.graphite,
        floatingActionButton: floatingActionButton,
        appBar: AppBar(
          centerTitle: true,
          title: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title.toUpperCase(),
                style: AssimilisBrand.display(17, color: AssimilisBrand.violetSoft)
                    .copyWith(shadows: [const Shadow(color: AssimilisBrand.violet, blurRadius: 14)])),
            if (subtitle != null) Text(subtitle!, style: AssimilisBrand.label(10)),
          ]),
          actions: actions,
          bottom: bottom,
        ),
        body: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: GridBackdrop())),
          Positioned.fill(child: body),
        ]),
      ),
    );
  }
}

/// Faint grid behind every screen, like the HES web page.
class GridBackdrop extends CustomPainter {
  const GridBackdrop();
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = AssimilisBrand.violet.withValues(alpha: 0.045);
    for (var x = 0.0; x < s.width; x += 28) {
      c.drawLine(Offset(x, 0), Offset(x, s.height), p);
    }
    for (var y = 0.0; y < s.height; y += 28) {
      c.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Small label/value block: "TOTAL POWER 113.1".
class HudStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const HudStat(this.label, this.value, {super.key, this.color = AssimilisBrand.text});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: AssimilisBrand.label(10)),
        const SizedBox(height: 2),
        Text(value, style: AssimilisBrand.display(16, color: color)),
      ]);
}

/// Rank badge: a glowing letter in a square frame.
class RankBadge extends StatelessWidget {
  final String rank;
  final double size;
  const RankBadge(this.rank, {super.key, this.size = 64});
  @override
  Widget build(BuildContext context) {
    final col = AssimilisBrand.rankColor(rank);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AssimilisBrand.raised,
        border: Border.all(color: col, width: 1.5),
        boxShadow: [BoxShadow(color: col.withValues(alpha: 0.35), blurRadius: 16)],
      ),
      child: Text(rank,
          style: AssimilisBrand.display(rank.length > 2 ? size * 0.22 : size * 0.42, color: col)
              .copyWith(shadows: [Shadow(color: col, blurRadius: 12)])),
    );
  }
}

/// Thin glowing progress bar.
class HudBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  const HudBar(this.value, {super.key, this.color = AssimilisBrand.violet, this.height = 6});
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(color: AssimilisBrand.raised, border: Border.all(color: AssimilisBrand.line, width: 0.5)),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0, 1).toDouble(),
          child: Container(decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withValues(alpha: 0.7), color]),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
          )),
        ),
      );
}

/// Radar chart (the HES branch spider web).
class RadarChart extends StatelessWidget {
  final List<String> labels;
  final List<double> values; // 0..max
  final double max;
  final Color color;
  final double size;
  const RadarChart({super.key, required this.labels, required this.values, this.max = 100, this.color = AssimilisBrand.violet, this.size = 200});
  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _Radar(labels, values, max, color)));
}

class _Radar extends CustomPainter {
  final List<String> labels;
  final List<double> values;
  final double max;
  final Color color;
  _Radar(this.labels, this.values, this.max, this.color);

  @override
  void paint(Canvas c, Size s) {
    final n = labels.length;
    if (n < 3) return;
    final ctr = s.center(Offset.zero);
    final r = s.shortestSide / 2 - 26;
    Offset at(int i, double f) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      return ctr + Offset(math.cos(a), math.sin(a)) * r * f;
    }

    final web = Paint()
      ..color = AssimilisBrand.line
      ..style = PaintingStyle.stroke;
    for (var ring = 1; ring <= 4; ring++) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = at(i, ring / 4);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      c.drawPath(path..close(), web);
    }
    for (var i = 0; i < n; i++) {
      c.drawLine(ctr, at(i, 1), web);
    }
    final shape = Path();
    for (var i = 0; i < n; i++) {
      final p = at(i, (values[i] / max).clamp(0.02, 1));
      i == 0 ? shape.moveTo(p.dx, p.dy) : shape.lineTo(p.dx, p.dy);
    }
    shape.close();
    c.drawPath(shape, Paint()..color = color.withValues(alpha: 0.22));
    c.drawPath(shape, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2));
    for (var i = 0; i < n; i++) {
      c.drawCircle(at(i, (values[i] / max).clamp(0.02, 1)), 2.6, Paint()..color = Colors.white);
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: const TextStyle(fontFamily: 'Inter', color: AssimilisBrand.muted, fontSize: 10)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 80);
      final p = at(i, 1.16);
      tp.paint(c, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _Radar o) => o.values != values || o.color != color;
}

/// Pill chip used for tabs and filters.
class HudChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const HudChip(this.label, {super.key, required this.selected, required this.onTap, this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AssimilisBrand.violet.withValues(alpha: 0.18) : Colors.transparent,
              border: Border.all(color: selected ? AssimilisBrand.violet : AssimilisBrand.line),
              boxShadow: selected ? [BoxShadow(color: AssimilisBrand.violet.withValues(alpha: 0.3), blurRadius: 10)] : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 14, color: selected ? AssimilisBrand.violetSoft : AssimilisBrand.muted), const SizedBox(width: 6)],
              Text(label.toUpperCase(), style: AssimilisBrand.label(11, color: selected ? AssimilisBrand.text : AssimilisBrand.muted)),
            ]),
          ),
        ),
      );
}

/// Empty / info line in mono.
class HudNote extends StatelessWidget {
  final String text;
  final Color color;
  const HudNote(this.text, {super.key, this.color = AssimilisBrand.faint});
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(16), child: Text(text, textAlign: TextAlign.center, style: AssimilisBrand.label(11, color: color)));
}
