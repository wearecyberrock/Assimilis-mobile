import 'package:flutter/material.dart';

import '../../hub/brand.dart';
import 'canvas_objects.dart';
import 'note_renderer.dart';
import 'notes_store.dart';

/// One page: Page mode (write / preview with maths and prompt blocks) or Canvas mode
/// (infinite plane 0.2x–3x with notes, coded graphs, media, video, sound, code, connectors, and vector ink).
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
    _tc.dispose();
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

  Future<void> _addObject() async {
    final res = await showCanvasObjectDialog(context);
    if (res == null || res['_delete'] == true) return;
    final c = _worldCenter();
    await _store.addBoardObject(
      kind: '${res['kind']}',
      title: '${res['title']}',
      text: '${res['text']}',
      x: (c.dx - 110).clamp(16, 5600),
      y: (c.dy - 60).clamp(16, 5600),
      extra: Map<String, dynamic>.from(res['extra'] as Map? ?? const {}),
      page: p,
    );
    if (mounted) setState(() {});
  }

  Future<void> _editCard(Map<String, dynamic> n) async {
    final res = await showCanvasObjectDialog(context, existing: n);
    if (res == null) return;
    if (res['_delete'] == true) {
      await _store.removeBoardObject('${n['id']}', page: p);
    } else {
      n['title'] = res['title'];
      n['text'] = res['text'];
      n.addAll(Map<String, dynamic>.from(res['extra'] as Map? ?? const {}));
      await _store.touch(p);
    }
    if (mounted) setState(() {});
  }

  void _tapCard(Map n) {
    if (_tool != 'connect') return;
    if (_connectFrom == null) {
      setState(() => _connectFrom = '${n['id']}');
    } else if (_connectFrom != '${n['id']}') {
      setState(() {
        conns.add({'id': NotesStore.newId('conn'), 'from': _connectFrom, 'to': n['id']});
        _connectFrom = null;
      });
      _store.touch(p);
    }
  }

  Widget _canvas() {
    final itemList = [for (final n in nodes) Map<String, dynamic>.from(n as Map)];
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
                Positioned.fill(
                  child: CustomPaint(
                    painter: CanvasBoardPainter(items: itemList, conns: conns, ink: ink, liveStroke: _stroke),
                  ),
                ),
                for (final n in nodes)
                  Positioned(
                    left: ((n as Map)['x'] as num? ?? 40).toDouble(),
                    top: (n['y'] as num? ?? 40).toDouble(),
                    width: (n['w'] as num? ?? 210).toDouble(),
                    child: CanvasObjectCard(
                      node: Map<String, dynamic>.from(n),
                      selected: _connectFrom == n['id'],
                      onTap: () => _tapCard(n),
                      onDoubleTap: () => _editCard(n as Map<String, dynamic>),
                      onPanUpdate: _tool == 'move'
                          ? (d) => setState(() {
                                n['x'] = (n['x'] as num? ?? 0) + d.delta.dx;
                                n['y'] = (n['y'] as num? ?? 0) + d.delta.dy;
                              })
                          : null,
                      onPanEnd: _tool == 'move' ? (_) => _store.touch(p) : null,
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
            IconButton(onPressed: _addObject, icon: const Icon(Icons.add_box_rounded, color: Colors.white), tooltip: 'Add object'),
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
