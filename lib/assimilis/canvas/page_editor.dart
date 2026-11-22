import 'package:flutter/material.dart';

import '../../hub/brand.dart';
import 'note_renderer.dart';
import 'notes_store.dart';

/// One page: Page mode (write / preview with maths and prompt blocks) or Canvas mode
/// (infinite plane 0.2x–3x, note cards, connectors, vector ink).
class PageEditor extends StatefulWidget {
  final Map page;
  const PageEditor({super.key, required this.page});
  @override
  State<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> {
  final _store = NotesStore.instance;
  late final _title = TextEditingController(text: '${widget.page['title']}');
  late final _text = TextEditingController(text: '${widget.page['text'] ?? ''}');
  bool _editing = false;
  final _tc = TransformationController();
  String _tool = 'move'; // move | ink | connect
  String? _connectFrom;
  List<Offset>? _stroke;

  Map get p => widget.page;
  bool get canvas => p['mode'] == 'canvas';

  @override
  void dispose() {
    _commit();
    super.dispose();
  }

  void _commit() {
    p['title'] = _title.text.trim().isEmpty ? 'Untitled' : _title.text.trim();
    p['text'] = _text.text;
    _store.touch(p);
  }

  void _insert(String snippet) {
    final sel = _text.selection;
    final at = sel.isValid ? sel.start : _text.text.length;
    _text.text = _text.text.replaceRange(at, sel.isValid ? sel.end : at, snippet);
    _text.selection = TextSelection.collapsed(offset: at + snippet.length);
    setState(() => _editing = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AssimilisBrand.navy,
      appBar: AppBar(
        backgroundColor: AssimilisBrand.navy,
        foregroundColor: Colors.white,
        title: TextField(
          controller: _title,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(border: InputBorder.none),
          onEditingComplete: _commit,
        ),
        actions: [
          SegmentedButton<String>(
            style: SegmentedButton.styleFrom(
                foregroundColor: Colors.white70, selectedForegroundColor: Colors.white, selectedBackgroundColor: AssimilisBrand.violet),
            segments: const [
              ButtonSegment(value: 'page', icon: Icon(Icons.article_rounded, size: 18)),
              ButtonSegment(value: 'canvas', icon: Icon(Icons.gesture_rounded, size: 18)),
            ],
            selected: {canvas ? 'canvas' : 'page'},
            onSelectionChanged: (s) => setState(() {
              _commit();
              p['mode'] = s.first;
            }),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: canvas ? _canvas() : _pageMode(),
    );
  }

  // ---------------- Page mode
  Widget _pageMode() {
    return Column(children: [
      SizedBox(
        height: 46,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
          _chip(_editing ? 'Preview' : 'Edit', _editing ? Icons.visibility_rounded : Icons.edit_rounded,
              () => setState(() { _commit(); _editing = !_editing; })),
          _chip('H1', Icons.title_rounded, () => _insert('\n# ')),
          _chip('List', Icons.format_list_bulleted_rounded, () => _insert('\n- ')),
          _chip('Checklist', Icons.check_box_outlined, () => _insert('\n- [ ] ')),
          _chip('Maths', Icons.functions_rounded, () => _insert(r'$$ \frac{a}{b} $$')),
          _chip('Calc', Icons.calculate_rounded, () => _insert('\nprompt(math, "2^10 + sqrt(144)")\n')),
          _chip('Graph', Icons.show_chart_rounded, () => _insert('\nprompt(graph, "sin(x)", "x^2/4")\n')),
          _chip('d/dx', Icons.trending_up_rounded, () => _insert('\nprompt(derive, "x^3 + 2*x")\n')),
          _chip('∫', Icons.area_chart_rounded, () => _insert('\nprompt(integrate, "x^2", 0, 1)\n')),
          _chip('Table', Icons.table_chart_rounded, () => _insert('\n| A | B |\n|---|---|\n| 1 | 2 |\n')),
        ]),
      ),
      Expanded(
        child: _editing
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace', height: 1.4),
                  decoration: const InputDecoration(
                      border: InputBorder.none, hintText: 'Write… markdown, \$maths\$, prompt(graph, "x^2")',
                      hintStyle: TextStyle(color: Colors.white38)),
                ),
              )
            : GestureDetector(
                onDoubleTap: () => setState(() => _editing = true),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  if (_text.text.trim().isEmpty)
                    const Text('Empty page. Tap Edit (or double-tap) to write.', style: TextStyle(color: Colors.white38)),
                  NoteRenderer(_text.text),
                ]),
              ),
      ),
    ]);
  }

  Widget _chip(String label, IconData icon, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
        child: ActionChip(
          avatar: Icon(icon, size: 16, color: AssimilisBrand.violet),
          label: Text(label),
          labelStyle: const TextStyle(color: Colors.white),
          backgroundColor: AssimilisBrand.navyRaised,
          side: BorderSide.none,
          onPressed: onTap,
        ),
      );

  // ---------------- Canvas mode
  List get nodes => p['nodes'] as List;
  List get conns => p['connectors'] as List;
  List get ink => p['ink'] as List;

  Offset _worldCenter() {
    final size = MediaQuery.of(context).size;
    return _tc.toScene(Offset(size.width / 2, size.height / 2.6));
  }

  void _addCard() {
    final c = _worldCenter();
    setState(() => nodes.add({
          'id': NotesStore.newId('node'),
          'x': c.dx - 90,
          'y': c.dy - 50,
          'w': 180.0,
          'text': 'New note',
          'color': 0xFF23232B,
        }));
    _store.touch(p);
  }

  Future<void> _editCard(Map n) async {
    final c = TextEditingController(text: '${n['text']}');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AssimilisBrand.navyRaised,
        content: TextField(controller: c, maxLines: 6, autofocus: true, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, '\u0000delete'),
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (r == null) return;
    setState(() {
      if (r == '\u0000delete') {
        nodes.remove(n);
        conns.removeWhere((k) => k['from'] == n['id'] || k['to'] == n['id']);
      } else {
        n['text'] = r;
      }
    });
    _store.touch(p);
  }

  void _tapCard(Map n) {
    if (_tool != 'connect') return;
    if (_connectFrom == null) {
      setState(() => _connectFrom = n['id']);
    } else if (_connectFrom != n['id']) {
      setState(() {
        conns.add({'id': NotesStore.newId('conn'), 'from': _connectFrom, 'to': n['id']});
        _connectFrom = null;
      });
      _store.touch(p);
    }
  }

  Widget _canvas() {
    return Stack(children: [
      Positioned.fill(
        child: InteractiveViewer(
          transformationController: _tc,
          minScale: 0.2,
          maxScale: 3.0,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          constrained: false,
          panEnabled: _tool != 'ink',
          scaleEnabled: _tool != 'ink',
          child: SizedBox(
            width: 6000,
            height: 6000,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Child coordinates are already world coordinates (pan/zoom handled by the viewer).
              onPanStart: _tool == 'ink' ? (d) => setState(() => _stroke = [d.localPosition]) : null,
              onPanUpdate: _tool == 'ink' ? (d) => setState(() => _stroke!.add(d.localPosition)) : null,
              onPanEnd: _tool == 'ink'
                  ? (_) {
                      setState(() {
                        ink.add({'points': [for (final o in _stroke!) [o.dx, o.dy]], 'color': 0xFFA855F7, 'w': 3.0});
                        _stroke = null;
                      });
                      _store.touch(p);
                    }
                  : null,
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(painter: _CanvasPainter(nodes, conns, ink, _stroke))),
                for (final n in nodes)
                  Positioned(
                    left: (n['x'] as num).toDouble(),
                    top: (n['y'] as num).toDouble(),
                    width: (n['w'] as num).toDouble(),
                    child: GestureDetector(
                      onTap: () => _tapCard(n),
                      onDoubleTap: () => _editCard(n),
                      onPanUpdate: _tool == 'move'
                          ? (d) => setState(() {
                                n['x'] = (n['x'] as num) + d.delta.dx;
                                n['y'] = (n['y'] as num) + d.delta.dy;
                              })
                          : null,
                      onPanEnd: _tool == 'move' ? (_) => _store.touch(p) : null,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Color((n['color'] ?? 0xFF23232B) as int),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _connectFrom == n['id'] ? AssimilisBrand.magenta : AssimilisBrand.violet, width: 1.5),
                        ),
                        child: NoteRenderer('${n['text']}'),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
      Positioned(
        left: 12,
        right: 12,
        bottom: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(color: AssimilisBrand.navyRaised, borderRadius: BorderRadius.circular(18)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _tb(Icons.pan_tool_rounded, 'move', 'Move'),
            _tb(Icons.edit_rounded, 'ink', 'Ink'),
            _tb(Icons.share_rounded, 'connect', 'Connect'),
            IconButton(onPressed: _addCard, icon: const Icon(Icons.add_box_rounded, color: Colors.white), tooltip: 'Card'),
            IconButton(
              onPressed: () {
                setState(() => ink.isNotEmpty ? ink.removeLast() : null);
                _store.touch(p);
              },
              icon: const Icon(Icons.undo_rounded, color: Colors.white),
              tooltip: 'Undo ink',
            ),
            IconButton(
                onPressed: () => _tc.value = Matrix4.identity(),
                icon: const Icon(Icons.center_focus_strong_rounded, color: Colors.white),
                tooltip: 'Reset view'),
          ]),
        ),
      ),
    ]);
  }

  Widget _tb(IconData i, String tool, String tip) => IconButton(
        tooltip: tip,
        onPressed: () => setState(() {
          _tool = tool;
          _connectFrom = null;
        }),
        icon: Icon(i, color: _tool == tool ? AssimilisBrand.violet : Colors.white70),
      );
}

class _CanvasPainter extends CustomPainter {
  final List nodes, conns, ink;
  final List<Offset>? live;
  _CanvasPainter(this.nodes, this.conns, this.ink, this.live);

  @override
  void paint(Canvas c, Size size) {
    final dot = Paint()..color = Colors.white10;
    for (var x = 0.0; x < size.width; x += 40) {
      for (var y = 0.0; y < size.height; y += 40) {
        c.drawCircle(Offset(x, y), 1, dot);
      }
    }
    final byId = {for (final n in nodes) n['id']: n};
    final line = Paint()
      ..color = const Color(0xAAA855F7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final k in conns) {
      final a = byId[k['from']], b = byId[k['to']];
      if (a == null || b == null) continue;
      final p1 = Offset((a['x'] as num) + (a['w'] as num) / 2, (a['y'] as num) + 30.0);
      final p2 = Offset((b['x'] as num) + (b['w'] as num) / 2, (b['y'] as num) + 30.0);
      final dx = (p2.dx - p1.dx).abs() / 2 + 40;
      // Cubic Bezier: M x1 y1 C cx1 cy1, cx2 cy2, x2 y2
      c.drawPath(Path()..moveTo(p1.dx, p1.dy)..cubicTo(p1.dx + dx, p1.dy, p2.dx - dx, p2.dy, p2.dx, p2.dy), line);
      c.drawCircle(p2, 4, Paint()..color = const Color(0xFFA855F7));
    }
    void stroke(List<Offset> pts, Color color, double w) {
      if (pts.length < 2) return;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final o in pts.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      c.drawPath(path, Paint()
        ..color = color
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke);
    }

    for (final s in ink) {
      stroke([for (final q in (s['points'] as List)) Offset((q[0] as num).toDouble(), (q[1] as num).toDouble())],
          Color((s['color'] ?? 0xFFA855F7) as int), ((s['w'] ?? 3) as num).toDouble());
    }
    if (live != null) stroke(live!, AssimilisBrand.violet, 3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
