import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

/// Assimilis Canvas & Notes on the phone:
/// - Infinite top-level Canvas board where Books live as draggable, connectable objects alongside
///   rich objects (note cards, coded graphs, media images, video, sound/audio, code blocks),
///   Bezier connection lines, and vector ink.
/// - Inside each Book: Sections > Pages, each supporting Page mode (markdown, $LaTeX$, prompt(...) blocks)
///   and Page Canvas mode (the same infinite object/connector/ink plane).
/// Persistent ID prefixes match the web Notes: lib-, book-, sec-, page-, blk-, node-, conn-.
/// Stored in <documents>/notes/vault.json.
class NotesStore {
  NotesStore._();
  static final NotesStore instance = NotesStore._();

  static const objectKinds = ['note', 'graph', 'media', 'video', 'sound', 'code'];

  Map<String, dynamic> vault = {};
  File? _file;

  static String newId(String prefix) {
    final r = Random.secure();
    return '$prefix-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 20).toRadixString(36)}';
  }

  /// Resets in-memory state (for unit tests with temporary directories).
  void resetForTest() {
    vault = {};
    _file = null;
  }

  Future<void> load() async {
    if (_file != null) return;
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/notes');
    await dir.create(recursive: true);
    _file = File('${dir.path}/vault.json');
    if (await _file!.exists()) {
      vault = Map<String, dynamic>.from(jsonDecode(await _file!.readAsString()));
      _ensureBoard();
    } else {
      vault = {
        'id': newId('lib'),
        'name': 'My Library',
        'books': <Map<String, dynamic>>[],
        'board': {
          'nodes': <Map<String, dynamic>>[],
          'connectors': <Map<String, dynamic>>[],
          'ink': <Map<String, dynamic>>[],
        },
      };
      await _seed();
    }
  }

  void _ensureBoard() {
    final b = vault['board'];
    if (b is! Map) {
      vault['board'] = {
        'nodes': <Map<String, dynamic>>[],
        'connectors': <Map<String, dynamic>>[],
        'ink': <Map<String, dynamic>>[],
      };
    } else {
      b['nodes'] ??= <Map<String, dynamic>>[];
      b['connectors'] ??= <Map<String, dynamic>>[];
      b['ink'] ??= <Map<String, dynamic>>[];
    }
    // Give any book created before the infinite board coordinates near the origin.
    final list = books;
    for (var i = 0; i < list.length; i++) {
      final bk = list[i];
      if (bk['x'] == null || bk['y'] == null) {
        bk['x'] = 48.0 + (i % 3) * 260.0;
        bk['y'] = 64.0 + (i ~/ 3) * 210.0;
        bk['w'] = 220.0;
      }
    }
  }

  Future<void> save() async {
    vault['updated'] = DateTime.now().toIso8601String();
    await _file!.writeAsString(jsonEncode(vault));
  }

  Future<void> _seed() async {
    final b = await addBook('School', color: 0xFFA855F7, x: 48, y: 72);
    final s = await addSection(b['id'], 'Maths');
    await addPage(b['id'], s['id'], 'Getting started',
        text: '# Welcome to Canvas\n\nWrite notes with **markdown** and maths like \$E = mc^2\$ or a block:\n\n'
            '\$\$\\int_0^1 x^2\\,dx = \\frac{1}{3}\$\$\n\n'
            'Ask A: *"make a note for COMP2201 on recursion"* or *"plot sin(x)"*.\n\n'
            'prompt(graph, "sin(x)")\n\nprompt(math, "2^10 + sqrt(144)")');
    final g = await addBoardObject(
      kind: 'graph',
      title: 'Functions',
      x: 48,
      y: 290,
      w: 290,
      extra: {
        'functions': ['sin(x)', 'x^2/4'],
        'code': 'y1 = sin(x)\ny2 = x^2/4',
      },
    );
    await addBoardConnector('${b['id']}', '${g['id']}', label: 'Maths');
  }

  List<Map<String, dynamic>> get books => List<Map<String, dynamic>>.from(vault['books'] ?? const []);

  Map<String, dynamic> get board {
    _ensureBoard();
    return vault['board'] as Map<String, dynamic>;
  }

  List get boardNodes => board['nodes'] as List;
  List get boardConnectors => board['connectors'] as List;
  List get boardInk => board['ink'] as List;

  Future<Map<String, dynamic>> addBook(String name, {int color = 0xFFA855F7, double? x, double? y}) async {
    _ensureBoard();
    final idx = books.length;
    final b = <String, dynamic>{
      'id': newId('book'),
      'name': name,
      'color': color,
      'x': x ?? (48.0 + (idx % 3) * 260.0),
      'y': y ?? (72.0 + (idx ~/ 3) * 210.0),
      'w': 220.0,
      'sections': <Map<String, dynamic>>[],
    };
    (vault['books'] as List).add(b);
    await save();
    return b;
  }

  Future<void> removeBook(String id) async {
    (vault['books'] as List).removeWhere((b) => b['id'] == id);
    boardConnectors.removeWhere((k) => k['from'] == id || k['to'] == id);
    await save();
  }

  Map<String, dynamic>? book(String id) =>
      books.cast<Map<String, dynamic>?>().firstWhere((b) => b!['id'] == id, orElse: () => null);

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

  /// Adds an object (note, graph, media, video, sound, code) to the top-level infinite canvas
  /// or to a specific page's canvas when [page] is supplied.
  Future<Map<String, dynamic>> addBoardObject({
    required String kind,
    String? title,
    String text = '',
    double? x,
    double? y,
    double? w,
    int color = 0xFF1A1A22,
    Map<String, dynamic>? extra,
    Map? page,
  }) async {
    _ensureBoard();
    final list = page != null ? (page['nodes'] as List) : boardNodes;
    final idx = list.length;
    final defaultW = switch (kind) {
      'graph' => 280.0,
      'media' || 'video' => 250.0,
      'sound' => 240.0,
      'code' => 260.0,
      _ => 210.0,
    };
    final obj = <String, dynamic>{
      'id': newId('node'),
      'kind': objectKinds.contains(kind) ? kind : 'note',
      'title': title ?? '',
      'text': text,
      'x': x ?? (60.0 + (idx % 3) * 280.0),
      'y': y ?? (260.0 + (idx ~/ 3) * 230.0),
      'w': w ?? defaultW,
      'color': color,
      'created': DateTime.now().toIso8601String(),
      ...?extra,
    };
    list.add(obj);
    if (page != null) {
      await touch(page);
    } else {
      await save();
    }
    return obj;
  }

  Future<Map<String, dynamic>> addBoardConnector(String fromId, String toId, {String? label, Map? page}) async {
    _ensureBoard();
    final list = page != null ? (page['connectors'] as List) : boardConnectors;
    final conn = <String, dynamic>{
      'id': newId('conn'),
      'from': fromId,
      'to': toId,
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
    };
    list.add(conn);
    if (page != null) {
      await touch(page);
    } else {
      await save();
    }
    return conn;
  }

  Future<void> removeBoardObject(String id, {Map? page}) async {
    final nodes = page != null ? (page['nodes'] as List) : boardNodes;
    final conns = page != null ? (page['connectors'] as List) : boardConnectors;
    nodes.removeWhere((n) => n['id'] == id);
    conns.removeWhere((k) => k['from'] == id || k['to'] == id);
    if (page != null) {
      await touch(page);
    } else {
      await save();
    }
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

  /// Finds any top-level canvas item (book or board object) by id or exact/partial title.
  Map<String, dynamic>? findBoardItem(String idOrName) {
    final q = idOrName.trim().toLowerCase();
    for (final b in books) {
      if ('${b['id']}'.toLowerCase() == q || '${b['name']}'.toLowerCase() == q) return b;
    }
    for (final n in boardNodes) {
      final m = Map<String, dynamic>.from(n as Map);
      if ('${m['id']}'.toLowerCase() == q || '${m['title'] ?? ''}'.toLowerCase() == q) return m;
    }
    for (final b in books) {
      if ('${b['name']}'.toLowerCase().contains(q)) return b;
    }
    for (final n in boardNodes) {
      final m = Map<String, dynamic>.from(n as Map);
      if ('${m['title'] ?? ''} ${m['text'] ?? ''}'.toLowerCase().contains(q)) return m;
    }
    return null;
  }

  List<({Map book, Map section, Map page})> search(String q) {
    final terms = q.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    return allPages().where((e) {
      final hay = '${e.book['name']} ${e.section['name']} ${e.page['title']} ${e.page['text']} '
              '${(e.page['nodes'] as List).map((n) => '${n['title'] ?? ''} ${n['text'] ?? ''} ${n['code'] ?? ''} ${(n['functions'] as List? ?? const []).join(' ')}').join(' ')}'
          .toLowerCase();
      return terms.every(hay.contains);
    }).toList();
  }

  /// Search top-level canvas objects (notes, graphs, media, video, sound, code).
  List<Map<String, dynamic>> searchObjects(String q) {
    final terms = q.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    return boardNodes.map((n) => Map<String, dynamic>.from(n as Map)).where((n) {
      final hay = '${n['kind'] ?? 'note'} ${n['title'] ?? ''} ${n['text'] ?? ''} ${n['code'] ?? ''} '
              '${n['uri'] ?? ''} ${n['path'] ?? ''} ${(n['functions'] as List? ?? const []).join(' ')}'
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

  /// Human- and AI-readable dump of the Canvas (infinite board, books, objects, connectors, or a specific book/page).
  String readCanvas({String? bookQuery, String? pageId, String? query}) {
    _ensureBoard();
    if (pageId != null && pageId.trim().isNotEmpty) {
      final f = find(pageId.trim());
      if (f == null) return 'No Canvas page with id "$pageId".';
      final p = f.page;
      final buf = StringBuffer()
        ..writeln('Page: ${p['title']} (${p['id']}) · Book: ${f.book['name']} › ${f.section['name']} · mode=${p['mode']}')
        ..writeln('--- Text ---')
        ..writeln('${p['text'] ?? ''}'.trim());
      final pNodes = (p['nodes'] as List? ?? const []);
      final pConns = (p['connectors'] as List? ?? const []);
      if (pNodes.isNotEmpty) {
        buf.writeln('--- Page Canvas Objects (${pNodes.length}) ---');
        for (final n in pNodes) {
          buf.writeln(_describeNode(Map<String, dynamic>.from(n as Map)));
        }
      }
      if (pConns.isNotEmpty) {
        buf.writeln('--- Connections (${pConns.length}) ---');
        final names = {for (final n in pNodes) '${n['id']}': _labelOf(Map<String, dynamic>.from(n as Map))};
        for (final k in pConns) {
          final lbl = '${k['label'] ?? ''}'.trim();
          buf.writeln('- ${names[k['from']] ?? k['from']} -> ${names[k['to']] ?? k['to']}${lbl.isEmpty ? '' : ' ($lbl)'}');
        }
      }
      final inkCount = (p['ink'] as List? ?? const []).length;
      if (inkCount > 0) buf.writeln('Ink strokes: $inkCount');
      return buf.toString().trim();
    }

    if (bookQuery != null && bookQuery.trim().isNotEmpty) {
      final b = book(bookQuery.trim()) ?? bookNamed(bookQuery.trim());
      if (b == null) return 'No book matching "$bookQuery".';
      final buf = StringBuffer()
        ..writeln('Book: ${b['name']} (${b['id']}) at (${_num(b['x'])}, ${_num(b['y'])})');
      for (final s in (b['sections'] as List)) {
        buf.writeln('  Section: ${s['name']} (${s['id']})');
        for (final p in (s['pages'] as List)) {
          final txt = '${p['text'] ?? ''}'.replaceAll('\n', ' ').trim();
          final preview = txt.length > 160 ? '${txt.substring(0, 160)}…' : txt;
          final objs = (p['nodes'] as List? ?? const []).length;
          buf.writeln('    - Page ${p['id']}: ${p['title']} ($objs canvas objects)${preview.isEmpty ? '' : ' — $preview'}');
        }
      }
      final relConns = boardConnectors.where((k) => k['from'] == b['id'] || k['to'] == b['id']).toList();
      if (relConns.isNotEmpty) {
        buf.writeln('  Connected on canvas:');
        final names = _boardLabels();
        for (final k in relConns) {
          final lbl = '${k['label'] ?? ''}'.trim();
          buf.writeln('    - ${names[k['from']] ?? k['from']} -> ${names[k['to']] ?? k['to']}${lbl.isEmpty ? '' : ' ($lbl)'}');
        }
      }
      return buf.toString().trim();
    }

    final q = query?.trim();
    if (q != null && q.isNotEmpty) {
      final hits = search(q);
      final objs = searchObjects(q);
      if (hits.isEmpty && objs.isEmpty) return 'Nothing on the Canvas matches "$q".';
      final buf = StringBuffer()..writeln('Canvas matches for "$q":');
      for (final o in objs) {
        buf.writeln('  [object] ${_describeNode(o)}');
      }
      for (final h in hits.take(10)) {
        final t = '${h.page['text'] ?? ''}'.replaceAll('\n', ' ').trim();
        buf.writeln('  [page] ${h.page['id']} · ${h.book['name']} › ${h.section['name']} › ${h.page['title']}: '
            '${t.length > 140 ? '${t.substring(0, 140)}…' : t}');
      }
      return buf.toString().trim();
    }

    final buf = StringBuffer()
      ..writeln('Infinite Canvas (${books.length} books, ${boardNodes.length} objects, ${boardConnectors.length} connections, ${boardInk.length} ink strokes):');
    if (books.isNotEmpty) {
      buf.writeln('--- Books ---');
      for (final b in books) {
        final secs = (b['sections'] as List);
        final pageCount = secs.fold<int>(0, (sum, s) => sum + ((s['pages'] as List).length));
        final pageNames = [
          for (final s in secs)
            for (final p in (s['pages'] as List)) '${p['title']} (${p['id']})',
        ].take(6).join(', ');
        buf.writeln('- [book] ${b['name']} (${b['id']}) at (${_num(b['x'])}, ${_num(b['y'])}) · '
            '${secs.length} sections, $pageCount pages${pageNames.isEmpty ? '' : ': $pageNames'}');
      }
    }
    if (boardNodes.isNotEmpty) {
      buf.writeln('--- Objects ---');
      for (final n in boardNodes) {
        buf.writeln(_describeNode(Map<String, dynamic>.from(n as Map)));
      }
    }
    if (boardConnectors.isNotEmpty) {
      buf.writeln('--- Connections ---');
      final names = _boardLabels();
      for (final k in boardConnectors) {
        final lbl = '${k['label'] ?? ''}'.trim();
        buf.writeln('- ${names[k['from']] ?? k['from']} (${k['from']}) -> ${names[k['to']] ?? k['to']} (${k['to']})${lbl.isEmpty ? '' : ' [$lbl]'}');
      }
    }
    return buf.toString().trim();
  }

  Map<String, String> _boardLabels() {
    final out = <String, String>{};
    for (final b in books) {
      out['${b['id']}'] = 'Book:${b['name']}';
    }
    for (final n in boardNodes) {
      final m = Map<String, dynamic>.from(n as Map);
      out['${m['id']}'] = _labelOf(m);
    }
    return out;
  }

  static String _labelOf(Map<String, dynamic> n) {
    final kind = '${n['kind'] ?? 'note'}';
    final title = '${n['title'] ?? ''}'.trim();
    if (title.isNotEmpty) return '$kind:$title';
    final text = '${n['text'] ?? ''}'.trim().split('\n').first;
    if (text.isNotEmpty) return '$kind:${text.length > 32 ? '${text.substring(0, 32)}…' : text}';
    return '$kind:${n['id']}';
  }

  static String _describeNode(Map<String, dynamic> n) {
    final kind = '${n['kind'] ?? 'note'}';
    final id = '${n['id']}';
    final title = '${n['title'] ?? ''}'.trim();
    final pos = '(${_num(n['x'])}, ${_num(n['y'])})';
    final details = <String>[];
    if (kind == 'graph') {
      final fns = (n['functions'] as List? ?? const []).map((e) => '$e').toList();
      if (fns.isNotEmpty) details.add('functions=${fns.join(', ')}');
      if ('${n['code'] ?? ''}'.trim().isNotEmpty) details.add('code=${'${n['code']}'.replaceAll('\n', '; ')}');
    } else if (kind == 'code') {
      final lang = '${n['language'] ?? 'text'}';
      final code = '${n['code'] ?? n['text'] ?? ''}'.replaceAll('\n', ' \\n ').trim();
      details.add('lang=$lang');
      if (code.isNotEmpty) details.add('code=${code.length > 180 ? '${code.substring(0, 180)}…' : code}');
    } else if (kind == 'media' || kind == 'video' || kind == 'sound') {
      final src = '${n['uri'] ?? n['path'] ?? ''}'.trim();
      if (src.isNotEmpty) details.add('src=$src');
      final cap = '${n['text'] ?? ''}'.trim();
      if (cap.isNotEmpty) details.add('caption=$cap');
    } else {
      final txt = '${n['text'] ?? ''}'.replaceAll('\n', ' ').trim();
      if (txt.isNotEmpty) details.add(txt.length > 180 ? '${txt.substring(0, 180)}…' : txt);
    }
    final head = title.isEmpty ? '[$kind] $id' : '[$kind] "$title" ($id)';
    return '- $head at $pos${details.isEmpty ? '' : ': ${details.join(' · ')}'}';
  }

  static String _num(dynamic v) => v is num ? v.round().toString() : '0';
}
