import 'package:flutter/material.dart';

import '../../hub/brand.dart';
import '../../hub/hud.dart';
import 'notes_store.dart';
import 'page_editor.dart';

/// Canvas: notebooks (books) > sections > pages, search, and quick add.
class CanvasView extends StatefulWidget {
  const CanvasView({super.key});
  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  final _s = NotesStore.instance;
  bool _loaded = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _s.load().then((_) => setState(() => _loaded = true));
  }

  Future<String?> _ask(String title, [String initial = '']) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AssimilisBrand.navyRaised,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: c,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _open(Map page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Theme(
          data: AssimilisBrand.theme(),
          child: PageEditor(page: page),
        ),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return HudScaffold(
      title: 'Canvas',
      actions: [
        IconButton(
          tooltip: 'New notebook',
          icon: const Icon(Icons.create_new_folder_rounded),
          onPressed: () async {
            final n = await _ask('New notebook');
            if (n != null && n.isNotEmpty) {
              final b = await _s.addBook(n);
              await _s.addSection(b['id'], 'Notes');
              setState(() {});
            }
          },
        ),
      ],
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
              children: [
                TextField(
                  onChanged: (v) => setState(() => _q = v),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Colors.white54,
                    ),
                    hintText: 'Search notes',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: AssimilisBrand.navyRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_q.trim().isNotEmpty)
                  for (final r in _s.search(_q))
                    ListTile(
                      leading: const Icon(
                        Icons.description_rounded,
                        color: AssimilisBrand.violet,
                      ),
                      title: Text(
                        '${r.page['title']}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${r.book['name']} › ${r.section['name']}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      onTap: () => _open(r.page),
                    )
                else
                  for (final b in _s.books) _book(b),
              ],
            ),
    );
  }

  Widget _book(Map b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HudPanel(
        padding: EdgeInsets.zero,
        accent: Color((b['color'] ?? 0xFFA855F7) as int),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: Colors.white,
          collapsedIconColor: Colors.white54,
          leading: Icon(
            Icons.menu_book_rounded,
            color: Color((b['color'] ?? 0xFFA855F7) as int),
          ),
          title: Text(
            '${b['name']}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          children: [
            for (final s in (b['sections'] as List))
              ExpansionTile(
                iconColor: Colors.white,
                collapsedIconColor: Colors.white38,
                title: Text(
                  '${s['name']}',
                  style: const TextStyle(color: Colors.white70),
                ),
                childrenPadding: const EdgeInsets.only(left: 12),
                children: [
                  for (final p in (s['pages'] as List))
                    ListTile(
                      dense: true,
                      leading: Icon(
                        p['mode'] == 'canvas'
                            ? Icons.gesture_rounded
                            : Icons.article_rounded,
                        color: Colors.white54,
                        size: 18,
                      ),
                      title: Text(
                        '${p['title']}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      onTap: () => _open(p),
                    ),
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.add_rounded,
                      color: AssimilisBrand.violet,
                    ),
                    title: const Text(
                      'New page',
                      style: TextStyle(color: AssimilisBrand.violet),
                    ),
                    onTap: () async {
                      final t = await _ask('Page title');
                      if (t == null || t.isEmpty) return;
                      final p = await _s.addPage(b['id'], s['id'], t);
                      _open(p);
                    },
                  ),
                ],
              ),
            ListTile(
              leading: const Icon(Icons.add_rounded, color: Colors.white54),
              title: const Text(
                'New section',
                style: TextStyle(color: Colors.white54),
              ),
              onTap: () async {
                final n = await _ask('Section name');
                if (n != null && n.isNotEmpty) {
                  await _s.addSection(b['id'], n);
                  setState(() {});
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
