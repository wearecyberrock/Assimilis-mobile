import 'package:flutter/material.dart';

import '../../hub/brand.dart';
import '../../hub/hud.dart';
import 'canvas_objects.dart';
import 'notes_store.dart';
import 'page_editor.dart';

/// Canvas: opens directly as the infinite plane (0.2x–3x pan/zoom) with Books as draggable,
/// connectable objects alongside rich objects (notes, coded graphs, media, video, sound, code),
/// Bezier connectors, and vector ink.
class CanvasView extends StatefulWidget {
  const CanvasView({super.key});
  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  final _s = NotesStore.instance;
  final _tc = TransformationController();
  bool _loaded = false;
  String _tool = 'move'; // move | ink | connect
  String? _connectFrom;
  List<Offset>? _stroke;
  String _q = '';
  bool _indexOpen = false;

  @override
  void initState() {
    super.initState();
    _s.load().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Offset _worldCenter() {
    final size = MediaQuery.of(context).size;
    return _tc.toScene(Offset(size.width / 2, size.height / 2.5));
  }

  Future<String?> _ask(String title, [String initial = '', String? hint]) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AssimilisBrand.panel,
        title: Text(title, style: AssimilisBrand.body(16, w: FontWeight.w600)),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _openPage(Map page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Theme(data: AssimilisBrand.theme(), child: PageEditor(page: page)),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openBook(Map<String, dynamic> book) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AssimilisBrand.panel,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final accent = Color((book['color'] ?? 0xFFA855F7) as int);
          final sections = (book['sections'] as List);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(children: [
                    Icon(Icons.menu_book_rounded, color: accent),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${book['name']}', style: AssimilisBrand.display(16, w: FontWeight.w700))),
                    IconButton(
                      tooltip: 'New section',
                      icon: const Icon(Icons.create_new_folder_outlined, color: AssimilisBrand.violetSoft),
                      onPressed: () async {
                        final n = await _ask('Section name');
                        if (n != null && n.isNotEmpty) {
                          await _s.addSection('${book['id']}', n);
                          setSheet(() {});
                          if (mounted) setState(() {});
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Delete book',
                      icon: const Icon(Icons.delete_outline_rounded, color: AssimilisBrand.faint),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _s.removeBook('${book['id']}');
                        if (mounted) setState(() {});
                      },
                    ),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    for (final s in sections)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: HudPanel(
                          padding: EdgeInsets.zero,
                          accent: accent,
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            shape: const Border(),
                            collapsedShape: const Border(),
                            title: Text('${s['name']}', style: AssimilisBrand.body(14, w: FontWeight.w600)),
                            children: [
                              for (final p in (s['pages'] as List))
                                ListTile(
                                  dense: true,
                                  leading: Icon(
                                    p['mode'] == 'canvas' ? Icons.gesture_rounded : Icons.article_rounded,
                                    color: AssimilisBrand.violetSoft,
                                    size: 18,
                                  ),
                                  title: Text('${p['title']}', style: AssimilisBrand.body(14)),
                                  onTap: () async {
                                    Navigator.pop(ctx);
                                    await _openPage(p);
                                  },
                                ),
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.add_rounded, color: AssimilisBrand.violet),
                                title: Text('New page', style: AssimilisBrand.body(13, color: AssimilisBrand.violetSoft)),
                                onTap: () async {
                                  final t = await _ask('Page title');
                                  if (t == null || t.isEmpty) return;
                                  final p = await _s.addPage('${book['id']}', '${s['id']}', t);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  await _openPage(p);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (sections.isEmpty) const HudNote('No sections yet. Tap the folder icon above to add one.'),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _addMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AssimilisBrand.panel,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
          Text('ADD TO INFINITE CANVAS', style: AssimilisBrand.label(11, color: AssimilisBrand.violetSoft)),
          const SizedBox(height: 8),
          for (final item in const [
            ('book', 'Book (notebook)', 'Holds sections and pages', Icons.menu_book_rounded),
            ('note', 'Note card', 'Markdown, \$LaTeX\$ and prompt(...) blocks', Icons.sticky_note_2_outlined),
            ('graph', 'Coded graph', 'Interactive y = f(x) plots & formulas', Icons.show_chart_rounded),
            ('media', 'Image / media', 'Photo from gallery or web URL', Icons.image_rounded),
            ('video', 'Video', 'Local video file or YouTube / web link', Icons.smart_display_rounded),
            ('sound', 'Sound / audio', 'Playable audio clip or stream URL', Icons.graphic_eq_rounded),
            ('code', 'Code / maths block', 'Monospace code or live math evaluation', Icons.code_rounded),
          ])
            ListTile(
              leading: Icon(item.$4, color: AssimilisBrand.violetSoft),
              title: Text(item.$2, style: AssimilisBrand.body(14, w: FontWeight.w600)),
              subtitle: Text(item.$3, style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
              onTap: () => Navigator.pop(ctx, item.$1),
            ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    final c = _worldCenter();
    if (choice == 'book') {
      final n = await _ask('New book name');
      if (n != null && n.isNotEmpty) {
        final b = await _s.addBook(n, x: (c.dx - 110).clamp(16, 5600), y: (c.dy - 70).clamp(16, 5600));
        await _s.addSection('${b['id']}', 'Notes');
        if (mounted) setState(() {});
      }
      return;
    }
    final res = await showCanvasObjectDialog(context, initialKind: choice);
    if (res == null || res['_delete'] == true) return;
    await _s.addBoardObject(
      kind: '${res['kind']}',
      title: '${res['title']}',
      text: '${res['text']}',
      x: (c.dx - 120).clamp(16, 5600),
      y: (c.dy - 80).clamp(16, 5600),
      extra: Map<String, dynamic>.from(res['extra'] as Map? ?? const {}),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editObject(Map<String, dynamic> node) async {
    final res = await showCanvasObjectDialog(context, existing: node);
    if (res == null) return;
    if (res['_delete'] == true) {
      await _s.removeBoardObject('${node['id']}');
    } else {
      node['title'] = res['title'];
      node['text'] = res['text'];
      final extra = Map<String, dynamic>.from(res['extra'] as Map? ?? const {});
      node.addAll(extra);
      await _s.save();
    }
    if (mounted) setState(() {});
  }

  Future<void> _tapItemForConnect(String id) async {
    if (_tool != 'connect') return;
    if (_connectFrom == null) {
      setState(() => _connectFrom = id);
      return;
    }
    if (_connectFrom == id) {
      setState(() => _connectFrom = null);
      return;
    }
    final from = _connectFrom!;
    setState(() => _connectFrom = null);
    final lbl = await _ask('Connection label (optional)', '', 'e.g. depends on, references, formula');
    await _s.addBoardConnector(from, id, label: lbl);
    if (mounted) setState(() {});
  }

  void _focusOn(double x, double y) {
    final size = MediaQuery.of(context).size;
    final tx = -(x - size.width / 2 + 110);
    final ty = -(y - size.height / 2.6 + 60);
    _tc.value = Matrix4.translationValues(tx, ty, 0);
    setState(() => _indexOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final books = _loaded ? _s.books : const <Map<String, dynamic>>[];
    final nodes = _loaded ? _s.boardNodes : const [];
    final conns = _loaded ? _s.boardConnectors : const [];
    final ink = _loaded ? _s.boardInk : const [];
    final allItems = <Map<String, dynamic>>[
      ...books,
      for (final n in nodes) Map<String, dynamic>.from(n as Map),
    ];

    return HudScaffold(
      title: 'Canvas',
      subtitle: _loaded ? '${books.length} BOOKS · ${nodes.length} OBJECTS · ${conns.length} LINKS' : null,
      actions: [
        IconButton(
          tooltip: _indexOpen ? 'Infinite canvas' : 'Search & index',
          icon: Icon(_indexOpen ? Icons.grid_view_rounded : Icons.search_rounded),
          onPressed: () => setState(() => _indexOpen = !_indexOpen),
        ),
        IconButton(
          tooltip: 'Add object or book',
          icon: const Icon(Icons.add_box_outlined),
          onPressed: _loaded ? _addMenu : null,
        ),
      ],
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _indexOpen
              ? _indexView(books)
              : Stack(children: [
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
                                    ink.add({
                                      'points': [for (final o in _stroke!) [o.dx, o.dy]],
                                      'color': 0xFFA855F7,
                                      'w': 3.0,
                                    });
                                    _stroke = null;
                                  });
                                  _s.save();
                                }
                              : null,
                          child: Stack(children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: CanvasBoardPainter(items: allItems, conns: conns, ink: ink, liveStroke: _stroke),
                              ),
                            ),
                            for (final b in books)
                              Positioned(
                                left: (b['x'] as num? ?? 48).toDouble(),
                                top: (b['y'] as num? ?? 72).toDouble(),
                                width: (b['w'] as num? ?? 220).toDouble(),
                                child: _bookObject(b),
                              ),
                            for (final raw in nodes)
                              Positioned(
                                left: ((raw as Map)['x'] as num? ?? 80).toDouble(),
                                top: (raw['y'] as num? ?? 260).toDouble(),
                                width: (raw['w'] as num? ?? 220).toDouble(),
                                child: CanvasObjectCard(
                                  node: Map<String, dynamic>.from(raw),
                                  selected: _connectFrom == raw['id'],
                                  onTap: () => _tapItemForConnect('${raw['id']}'),
                                  onDoubleTap: () => _editObject(raw as Map<String, dynamic>),
                                  onPanUpdate: _tool == 'move'
                                      ? (d) => setState(() {
                                            raw['x'] = (raw['x'] as num? ?? 0) + d.delta.dx;
                                            raw['y'] = (raw['y'] as num? ?? 0) + d.delta.dy;
                                          })
                                      : null,
                                  onPanEnd: _tool == 'move' ? (_) => _s.save() : null,
                                ),
                              ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  if (_tool == 'connect')
                    Positioned(
                      top: 10,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AssimilisBrand.panel.withValues(alpha: 0.94),
                            border: Border.all(color: AssimilisBrand.magenta),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _connectFrom == null ? 'Tap the first book or object to connect' : 'Tap the target book or object',
                            style: AssimilisBrand.label(11, color: AssimilisBrand.text),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: AssimilisBrand.panel.withValues(alpha: 0.95),
                        border: Border.all(color: AssimilisBrand.line),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                        _tb(Icons.pan_tool_rounded, 'move', 'Move / Pan'),
                        _tb(Icons.edit_rounded, 'ink', 'Ink'),
                        _tb(Icons.hub_outlined, 'connect', 'Connect'),
                        IconButton(
                          tooltip: 'Add book or object',
                          onPressed: _addMenu,
                          icon: const Icon(Icons.add_circle_outline_rounded, color: AssimilisBrand.violetSoft),
                        ),
                        IconButton(
                          tooltip: 'Undo ink',
                          onPressed: () {
                            if (ink.isEmpty) return;
                            setState(() => ink.removeLast());
                            _s.save();
                          },
                          icon: const Icon(Icons.undo_rounded, color: Colors.white70),
                        ),
                        IconButton(
                          tooltip: 'Reset view',
                          onPressed: () => setState(() => _tc.value = Matrix4.identity()),
                          icon: const Icon(Icons.center_focus_strong_rounded, color: Colors.white70),
                        ),
                      ]),
                    ),
                  ),
                ]),
    );
  }

  Widget _bookObject(Map<String, dynamic> b) {
    final accent = Color((b['color'] ?? 0xFFA855F7) as int);
    final selected = _connectFrom == b['id'];
    final sections = (b['sections'] as List);
    final pageCount = sections.fold<int>(0, (sum, s) => sum + ((s['pages'] as List).length));
    final firstPages = [
      for (final s in sections)
        for (final p in (s['pages'] as List)) p,
    ].take(2).toList();

    return GestureDetector(
      onTap: () => _tool == 'connect' ? _tapItemForConnect('${b['id']}') : _openBook(b),
      onPanUpdate: _tool == 'move'
          ? (d) => setState(() {
                b['x'] = (b['x'] as num? ?? 48) + d.delta.dx;
                b['y'] = (b['y'] as num? ?? 72) + d.delta.dy;
              })
          : null,
      onPanEnd: _tool == 'move' ? (_) => _s.save() : null,
      child: HudPanel(
        accent: selected ? AssimilisBrand.magenta : accent,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(Icons.menu_book_rounded, color: accent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${b['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AssimilisBrand.display(13, w: FontWeight.w700),
              ),
            ),
            Text('BOOK', style: AssimilisBrand.label(9, color: accent)),
          ]),
          const SizedBox(height: 6),
          Text('${sections.length} sec · $pageCount pages', style: AssimilisBrand.label(10)),
          if (firstPages.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final p in firstPages)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(children: [
                  const Icon(Icons.article_outlined, size: 12, color: AssimilisBrand.muted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${p['title']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AssimilisBrand.body(11, color: AssimilisBrand.muted),
                    ),
                  ),
                ]),
              ),
          ],
          const SizedBox(height: 6),
          Text('Tap to open · Drag to move', style: AssimilisBrand.label(9, color: AssimilisBrand.faint)),
        ]),
      ),
    );
  }

  Widget _indexView(List<Map<String, dynamic>> books) {
    final q = _q.trim();
    final pageHits = q.isEmpty ? const [] : _s.search(q);
    final objHits = q.isEmpty ? _s.boardNodes.map((e) => Map<String, dynamic>.from(e as Map)).toList() : _s.searchObjects(q);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 32), children: [
      TextField(
        onChanged: (v) => setState(() => _q = v),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search books, pages & canvas objects'),
      ),
      if (q.isNotEmpty) ...[
        const HudHeader('Matching pages'),
        for (final r in pageHits)
          ListTile(
            leading: const Icon(Icons.description_rounded, color: AssimilisBrand.violet),
            title: Text('${r.page['title']}'),
            subtitle: Text('${r.book['name']} › ${r.section['name']}', style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
            onTap: () => _openPage(r.page),
          ),
        if (pageHits.isEmpty) const HudNote('No matching pages.'),
      ],
      const HudHeader('Books on Canvas'),
      for (final b in books)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: HudPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            accent: Color((b['color'] ?? 0xFFA855F7) as int),
            onTap: () => _openBook(b),
            child: Row(children: [
              Icon(Icons.menu_book_rounded, color: Color((b['color'] ?? 0xFFA855F7) as int)),
              const SizedBox(width: 10),
              Expanded(child: Text('${b['name']}', style: AssimilisBrand.body(14, w: FontWeight.w600))),
              IconButton(
                tooltip: 'Locate on canvas',
                icon: const Icon(Icons.my_location_rounded, size: 18, color: AssimilisBrand.violetSoft),
                onPressed: () => _focusOn((b['x'] as num? ?? 48).toDouble(), (b['y'] as num? ?? 72).toDouble()),
              ),
            ]),
          ),
        ),
      const HudHeader('Canvas objects'),
      for (final o in objHits)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: HudPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            accent: CanvasObjectCard.accentFor('${o['kind'] ?? 'note'}'),
            onTap: () => _focusOn((o['x'] as num? ?? 80).toDouble(), (o['y'] as num? ?? 260).toDouble()),
            child: Row(children: [
              Icon(CanvasObjectCard.iconFor('${o['kind'] ?? 'note'}'), color: CanvasObjectCard.accentFor('${o['kind'] ?? 'note'}'), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${o['title'] ?? ''}'.isEmpty ? '${o['kind'] ?? 'note'}'.toUpperCase() : '${o['title']}',
                      style: AssimilisBrand.body(14, w: FontWeight.w600)),
                  Text('${o['kind'] ?? 'note'} · ${o['uri'] ?? o['text'] ?? (o['functions'] as List?)?.join(', ') ?? ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
                ]),
              ),
              const Icon(Icons.my_location_rounded, size: 16, color: AssimilisBrand.faint),
            ]),
          ),
        ),
      if (objHits.isEmpty) const HudNote('No canvas objects yet.'),
    ]);
  }

  Widget _tb(IconData i, String tool, String tip) => IconButton(
        tooltip: tip,
        onPressed: () => setState(() {
          _tool = tool;
          _connectFrom = null;
        }),
        icon: Icon(i, color: _tool == tool ? AssimilisBrand.violetSoft : Colors.white70),
      );
}
