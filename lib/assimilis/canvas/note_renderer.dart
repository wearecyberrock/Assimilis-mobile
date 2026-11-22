import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../../hub/brand.dart';
import 'maths.dart';

/// Renders a page: markdown, $inline$ and $$display$$ LaTeX, and prompt(...) blocks
/// (the Assimilis Notes command language):
///   prompt(math, "2^10 + sqrt(144)")   calculator
///   prompt(graph, "sin(x)", "x^2/4")    function graph
///   prompt(derive, "x^3 + 2x")          derivative
///   prompt(integrate, "x^2", 0, 1)      definite integral
class NoteRenderer extends StatelessWidget {
  final String text;
  const NoteRenderer(this.text, {super.key});

  static final _block = RegExp(r'(\$\$[\s\S]+?\$\$|^\s*prompt\([^\n]*\)\s*$)', multiLine: true);

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    var last = 0;
    for (final m in _block.allMatches(text)) {
      if (m.start > last) parts.add(_md(text.substring(last, m.start)));
      final chunk = m.group(0)!.trim();
      parts.add(chunk.startsWith(r'$$') ? _display(chunk.substring(2, chunk.length - 2)) : _prompt(chunk));
      last = m.end;
    }
    if (last < text.length) parts.add(_md(text.substring(last)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: parts);
  }

  Widget _md(String s) => s.trim().isEmpty
      ? const SizedBox.shrink()
      : MarkdownBody(
          data: s,
          selectable: true,
          extensionSet: md.ExtensionSet(
            md.ExtensionSet.gitHubFlavored.blockSyntaxes,
            [_InlineMath(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
          ),
          builders: {'imath': _MathBuilder()},
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(color: Colors.white, fontSize: 15, height: 1.45),
            h1: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
            h2: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
            h3: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
            listBullet: const TextStyle(color: Colors.white70),
            code: const TextStyle(color: AssimilisBrand.mint, backgroundColor: AssimilisBrand.graphite),
            blockquoteDecoration: BoxDecoration(color: AssimilisBrand.raised, borderRadius: BorderRadius.circular(8)),
            tableBody: const TextStyle(color: Colors.white),
            tableHead: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        );

  Widget _display(String tex) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(tex.trim(),
              mathStyle: MathStyle.display,
              textStyle: const TextStyle(color: Colors.white, fontSize: 18),
              onErrorFallback: (e) => Text(tex, style: const TextStyle(color: Colors.redAccent))),
        ),
      );

  static List<String> _args(String call) {
    final inner = call.substring(call.indexOf('(') + 1, call.lastIndexOf(')'));
    return RegExp(r'"([^"]*)"|([^,\s][^,]*)').allMatches(inner).map((m) => (m.group(1) ?? m.group(2)!).trim()).toList();
  }

  Widget _prompt(String call) {
    final a = _args(call);
    if (a.isEmpty) return Text(call);
    final action = a.first.toLowerCase();
    final rest = a.skip(1).toList();
    Widget box(Widget child) => Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: AssimilisBrand.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x55A855F7))),
          child: child,
        );
    switch (action) {
      case 'math':
      case 'eval':
      case 'calc':
        final e = rest.join(',');
        return box(Text('$e = ${Maths.calc(e)}',
            style: const TextStyle(color: AssimilisBrand.mint, fontSize: 16, fontFamily: 'monospace')));
      case 'graph':
      case 'plot':
        return box(FunctionGraph(functions: rest.isEmpty ? ['x'] : rest));
      case 'derive':
        final e = rest.join(',');
        return box(Text("d/dx [$e] = ${Maths.derive(e)}",
            style: const TextStyle(color: AssimilisBrand.mint, fontFamily: 'monospace')));
      case 'integrate':
        if (rest.length < 3) return box(const Text('prompt(integrate, "f(x)", a, b)', style: TextStyle(color: Colors.white54)));
        final lo = double.tryParse(rest[1]) ?? 0, hi = double.tryParse(rest[2]) ?? 1;
        return box(Text('∫ ${rest[0]} dx from ${rest[1]} to ${rest[2]} = ${Maths.integrate(rest[0], lo, hi)}',
            style: const TextStyle(color: AssimilisBrand.mint, fontFamily: 'monospace')));
      default:
        return box(Text(call, style: const TextStyle(color: Colors.white54, fontFamily: 'monospace')));
    }
  }
}

class _InlineMath extends md.InlineSyntax {
  _InlineMath() : super(r'\$([^\$\n]+?)\$');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('imath', match[1]!));
    return true;
  }
}

class _MathBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    return Math.tex(element.textContent,
        mathStyle: MathStyle.text,
        textStyle: (parentStyle ?? const TextStyle()).copyWith(color: Colors.white, fontSize: 15),
        onErrorFallback: (e) => Text('\$${element.textContent}\$', style: const TextStyle(color: Colors.redAccent)));
  }
}
