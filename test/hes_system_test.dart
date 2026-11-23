import 'dart:convert';
import 'dart:io';

import 'package:assimilis_mobile/assimilis/hes/hes_store.dart';
import 'package:assimilis_mobile/assimilis/hes/hes_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final docs = Directory.systemTemp.createTempSync('hes_sys');
  final sys = HesSystem.instance;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => docs.path);
    m.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
    await HesStore.instance.state(); // onboard with defaults
  });

  test('a quest pays its reward when completed', () async {
    final before = await HesStore.instance.state();
    final q = await sys.issue(title: 'Walk 5,000 steps', type: 'side', silent: true);
    expect(q['xp'], 30);
    final r = await sys.complete(q['id']);
    expect(r, contains('+30 XP'));
    final after = await HesStore.instance.state();
    expect(after.xpTotal - before.xpTotal, 30);
    expect(after.coins - before.coins, 15);
    expect((await sys.quests()).firstWhere((x) => x['id'] == q['id'])['status'], 'done');
  });

  test('a missed quest is failed with a penalty when penalties are on', () async {
    final before = await HesStore.instance.state();
    await sys.issue(title: 'Up before 6', type: 'urgent', due: DateTime.now().subtract(const Duration(minutes: 1)), silent: true);
    final out = await sys.sweep();
    expect(out.single, contains('Penalty'));
    final after = await HesStore.instance.state();
    expect(after.xpTotal - before.xpTotal, -25);
    expect((await sys.feed()).first['kind'], 'penalty');
  });

  test('wake-up and study are quests; exams stay reminders that still pay', () async {
    final at = DateTime.now().add(const Duration(hours: 10));
    expect(await sys.remind('Wake up', at), startsWith('Quest set'));
    expect(await sys.remind('Study chemistry', at), startsWith('Quest set'));
    expect(await sys.remind('Chemistry exam in room 4', at), startsWith('Reminder set'));
    final open = await sys.quests(openOnly: true);
    final exam = open.firstWhere((q) => q['title'] == 'Chemistry exam in room 4');
    expect(exam['type'], 'reminder');
    expect(exam['due'], isNull); // never fails
    expect(open.firstWhere((q) => q['title'] == 'Wake up')['type'], 'daily');
    expect(await sys.complete('Chemistry exam'), contains('+5 XP'));
  });

  test('a module quest completes itself when the logs reach the target', () async {
    final q = await sys.issue(title: 'Pushups: 20', module: 'pushups', target: 20, unit: 'reps', silent: true);
    await HesStore.instance.quickLog('12 pushups');
    expect(await sys.sweep(), isEmpty);
    await HesStore.instance.quickLog('10 pushups');
    final out = await sys.sweep();
    expect(out.single, contains('Quest complete'));
    expect((await sys.quests()).firstWhere((x) => x['id'] == q['id'])['status'], 'done');
  });

  test('a repeating quest comes back after it is done', () async {
    final q = await sys.issue(
        title: 'Read 10 pages', repeat: 'daily', due: DateTime.now().add(const Duration(hours: 2)), silent: true);
    await sys.complete(q['id']);
    final again = (await sys.quests(openOnly: true)).where((x) => x['title'] == 'Read 10 pages').toList();
    expect(again, hasLength(1));
    expect((again.single['due'] as int) > (q['due'] as int), isTrue);
  });

  test('achievements, memory, questions and the chronicle', () async {
    final a = await sys.achievements();
    expect(a.map((x) => x['id']), contains('first_quest'));
    await sys.remember('Has a knee injury: no jumping.');
    expect(await sys.remember('has a knee injury: no jumping.'), 'Already known.');
    await sys.askUser('What is your exam date?');
    final q = (await sys.feed()).firstWhere((m) => m['kind'] == 'question');
    await sys.answer(q['id'], 'December 10');
    final facts = ((await sys.profile())['facts'] as List).map((f) => f['text']).toList();
    expect(facts.last, contains('December 10'));
    await sys.addChapter('Chapter 1: The Awakening', 'The player rose before dawn.');
    expect((await sys.chronicle()).first['title'], 'Chapter 1: The Awakening');
  });

  test('a check-in lets the brain act through HES tools', () async {
    // A fake OpenAI-compatible brain: first asks to issue a quest, then answers.
    var round = 0;
    Map? firstRequest;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
      round++;
      firstRequest ??= body;
      final msg = round == 1
          ? {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'c1',
                  'type': 'function',
                  'function': {
                    'name': 'hes_issue_quest',
                    'arguments': jsonEncode({'title': 'Sleep by 23:00', 'type': 'daily', 'detail': 'Your sleep log is short.'})
                  }
                }
              ]
            }
          : {'role': 'assistant', 'content': '[SYSTEM] One quest issued.'};
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'choices': [
          {'index': 0, 'message': msg, 'finish_reason': round == 1 ? 'tool_calls' : 'stop'}
        ]
      }));
      await req.response.close();
    });
    final text = await sys.think(endpoint: (base: 'http://127.0.0.1:${server.port}/v1', model: 'fake', key: ''), reason: 'test');
    await server.close(force: true);
    expect(text, '[SYSTEM] One quest issued.');
    expect((await sys.quests(openOnly: true)).any((q) => q['title'] == 'Sleep by 23:00'), isTrue);
    final tools = (firstRequest!['tools'] as List).map((t) => t['function']['name']).toList();
    expect(tools, containsAll(['hes_issue_quest', 'hes_ask_player', 'hes_set_reminder', 'hes_chronicle']));
    expect('${(firstRequest!['messages'] as List)[1]['content']}', contains('"open_quests"'));
  });
}
