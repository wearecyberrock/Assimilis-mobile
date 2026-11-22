import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

/// Assimilis Notes on the phone: Library (vault) > Book (notebook) > Section > Page, with the same
/// persistent ID prefixes as the web Notes (lib-, book-, sec-, page-, blk-, node-, conn-).
/// Pages have a Page mode (markdown text with $…$ / $$…$$ maths and prompt(...) blocks) and an
/// infinite Canvas mode (note cards, connectors, ink). Stored in <documents>/notes/vault.json.
class NotesStore {
  NotesStore._();
  static final NotesStore instance = NotesStore._();

  Map<String, dynamic> vault = {};
  File? _file;

  static String newId(String prefix) {
    final r = Random.secure();
    return '$prefix-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 20).toRadixString(36)}';
  }

  Future<void> load() async {
    if (_file != null) return;
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/notes');
    await dir.create(recursive: true);
    _file = File('${dir.path}/vault.json');
    if (await _file!.exists()) {
      vault = Map<String, dynamic>.from(jsonDecode(await _file!.readAsString()));
    } else {
      vault = {'id': newId('lib'), 'name': 'My Library', 'books': []};
      await _seed();
    }
  }

  Future<void> save() async {
    vault['updated'] = DateTime.now().toIso8601String();
    await _file!.writeAsString(jsonEncode(vault));
  }

  Future<void> _seed() async {
    final b = await addBook('School', color: 0xFFA855F7);
    final s = await addSection(b['id'], 'Maths');
    await addPage(b['id'], s['id'], 'Getting started',
        text: '# Welcome to Canvas\n\nWrite notes with **markdown** and maths like \$E = mc^2\$ or a block:\n\n'
            '\$\$\\int_0^1 x^2\\,dx = \\frac{1}{3}\$\$\n\n'
            'Ask Jarvis: *"make a note for COMP2201 on recursion"* or *"plot sin(x)"*.\n\n'
            'prompt(graph, "sin(x)")\n\nprompt(math, "2^10 + sqrt(144)")');
  }

  List<Map<String, dynamic>> get books => List<Map<String, dynamic>>.from(vault['books'] ?? const []);

  Future<Map<String, dynamic>> addBook(String name, {int color = 0xFFA855F7}) async {
    final b = {'id': newId('book'), 'name': name, 'color': color, 'sections': <Map<String, dynamic>>[]};
    (vault['books'] as List).add(b);
    await save();
    return b;
  }

  Map<String, dynamic>? book(String id) => books.cast<Map<String, dynamic>?>().firstWhere((b) => b!['id'] == id, orElse: () => null);

  Map<String, dynamic>? bookNamed(String name) => books.cast<Map<String, dynamic>?>().firstWhere(
      (b) => '${b!['name']}'.toLowerCase() == name.toLowerCase(),
      orElse: () => null);

  Future<Map<String, dynamic>> addSection(String bookId, String name) async {
    final s = {'id': newId('sec'), 'name': name, 'pages': <Map<String, dynamic>>[]};
    (book(bookId)!['sections'] as List).add(s);
    await save();
    return s;
  }

  Future<Map<String, dynamic>> addPage(String bookId, String sectionId, String title, {String text = ''}) async {
    final sec = (book(bookId)!['sections'] as List).firstWhere((s) => s['id'] == sectionId);
    final p = {
      'id': newId('page'),
      'title': title,
      'mode': 'page',
      'text': text,
      'nodes': <Map<String, dynamic>>[],
      'connectors': <Map<String, dynamic>>[],
      'ink': <Map<String, dynamic>>[],
      'pageSetup': {'size': 'letter', 'orientation': 'portrait', 'surface': 'plain'},
      'created': DateTime.now().toIso8601String(),
      'updated': DateTime.now().toIso8601String(),
    };
    (sec['pages'] as List).add(p);
    await save();
    return p;
  }

  /// Every page with where it lives.
  Iterable<({Map book, Map section, Map page})> allPages() sync* {
    for (final b in books) {
      for (final s in (b['sections'] as List)) {
        for (final p in (s['pages'] as List)) {
          yield (book: b, section: s, page: p);
        }
      }
    }
  }

  ({Map book, Map section, Map page})? find(String pageId) {
    for (final e in allPages()) {
      if (e.page['id'] == pageId) return e;
    }
    return null;
  }

  List<({Map book, Map section, Map page})> search(String q) {
    final terms = q.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    return allPages().where((e) {
      final hay = '${e.book['name']} ${e.section['name']} ${e.page['title']} ${e.page['text']} '
              '${(e.page['nodes'] as List).map((n) => n['text']).join(' ')}'
          .toLowerCase();
      return terms.every(hay.contains);
    }).toList();
  }

  /// Create a note somewhere sensible: book/section by name (created if missing).
  Future<Map<String, dynamic>> quickNote(String title, String text, {String book = 'Inbox', String section = 'Notes'}) async {
    final b = bookNamed(book) ?? await addBook(book);
    final secs = (b['sections'] as List);
    final s = secs.cast<Map>().firstWhere((x) => '${x['name']}'.toLowerCase() == section.toLowerCase(),
        orElse: () => <String, dynamic>{});
    final sec = s.isNotEmpty ? Map<String, dynamic>.from(s) : await addSection(b['id'], section);
    return addPage(b['id'], sec['id'], title, text: text);
  }

  Future<void> touch(Map page) async {
    page['updated'] = DateTime.now().toIso8601String();
    await save();
  }
}
