import 'dart:io';

import 'package:assimilis_mobile/assimilis/canvas/notes_store.dart';
import 'package:assimilis_mobile/assimilis/tools.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;

  setUp(() async {
    docs = Directory.systemTemp.createTempSync('asm_canvas_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => docs.path);
    NotesStore.instance.resetForTest();
  });

  tearDown(() {
    try {
      docs.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('infinite canvas seeds a book, coded graph, and connector', () async {
    final s = NotesStore.instance;
    await s.load();
    expect(s.books.length, 1);
    expect(s.books.first['x'], isNotNull);
    expect(s.boardNodes.length, 1);
    expect(s.boardNodes.first['kind'], 'graph');
    expect(s.boardConnectors.length, 1);

    final dump = s.readCanvas();
    expect(dump, contains('School'));
    expect(dump, contains('[graph]'));
    expect(dump, contains('sin(x)'));
    expect(dump, contains('--- Connections ---'));
  });

  test('rich objects (media, video, sound, code) and connectors persist and are readable by canvas_read', () async {
    final s = NotesStore.instance;
    await s.load();
    final bookId = '${s.books.first['id']}';

    final resImg = await AssimilisTools.run('canvas_add_object', {
      'kind': 'media',
      'title': 'Circuit diagram',
      'uri': 'https://example.com/circuit.png',
      'content': 'Week 4 lab',
      'connect_to': 'School',
      'connect_label': 'Lab 4',
    });
    expect(resImg, contains('Placed media object'));
    expect(resImg, contains('connected to School'));

    await AssimilisTools.run('canvas_add_object', {
      'kind': 'video',
      'title': 'Lecture 3',
      'uri': 'https://youtu.be/dQw4w9WgXcQ',
      'content': 'Recursion walkthrough',
    });
    await AssimilisTools.run('canvas_add_object', {
      'kind': 'sound',
      'title': 'Voice memo',
      'uri': '/storage/emulated/0/memo.mp3',
      'content': 'Exam tips',
    });
    await AssimilisTools.run('canvas_add_object', {
      'kind': 'code',
      'title': 'Area formula',
      'language': 'math',
      'content': 'pi * 5^2',
    });

    // Reload from disk to verify persistence.
    s.resetForTest();
    await s.load();

    final summary = await AssimilisTools.run('canvas_read', {});
    expect(summary, contains('[media] "Circuit diagram"'));
    expect(summary, contains('[video] "Lecture 3"'));
    expect(summary, contains('[sound] "Voice memo"'));
    expect(summary, contains('[code] "Area formula"'));
    expect(summary, contains('[Lab 4]'));

    final bookDump = await AssimilisTools.run('canvas_read', {'book': bookId});
    expect(bookDump, contains('Book: School'));
    expect(bookDump, contains('Getting started'));
    expect(bookDump, contains('Connected on canvas'));

    final qDump = await AssimilisTools.run('canvas_read', {'query': 'Circuit'});
    expect(qDump, contains('Circuit diagram'));
  });

  test('removing a book cleans up its canvas connectors', () async {
    final s = NotesStore.instance;
    await s.load();
    final id = '${s.books.first['id']}';
    expect(s.boardConnectors, isNotEmpty);
    await s.removeBook(id);
    expect(s.books, isEmpty);
    expect(s.boardConnectors, isEmpty);
  });
}
