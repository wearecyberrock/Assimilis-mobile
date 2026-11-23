import 'dart:convert';
import 'dart:io';

import 'package:assimilis_mobile/assimilis/hes/hes_store.dart';
import 'package:assimilis_mobile/assimilis/sync/hes_sync.dart';
import 'package:assimilis_mobile/assimilis/tools.dart';
import 'package:assimilis_mobile/assimilis/uwi/vle_client.dart';
import 'package:assimilis_mobile/assimilis/uwi/vle_store.dart';
import 'package:assimilis_mobile/assimilis/whatsapp/whatsapp_link.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  final secure = <String, String>{};

  setUpAll(() {
    HttpOverrides.global = null;
    docs = Directory.systemTemp.createTempSync('asm_m6_test');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => docs.path);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
      final a = Map<String, dynamic>.from(c.arguments as Map? ?? {});
      switch (c.method) {
        case 'read':
          return secure['${a['key']}'];
        case 'write':
          secure['${a['key']}'] = '${a['value']}';
          return null;
        case 'delete':
          secure.remove('${a['key']}');
          return null;
        case 'readAll':
          return Map<String, String>.from(secure);
        default:
          return null;
      }
    });
  });

  setUp(() {
    secure.clear();
    SharedPreferences.setMockInitialValues({'asm_user_name': 'Shakir'});
    VleClient.instance.setClientForTest(null);
    HesSync.instance.setClientForTest(null);
    WhatsAppLink.instance.setClientForTest(null);
  });

  tearDownAll(() {
    try {
      docs.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('M6 · Multi-user encrypted UWI Mona VLE', () {
    test('stores multiple accounts encrypted in keystore and never exposes passwords', () async {
      final store = VleStore.instance;
      final a1 = await store.saveAccount(label: 'Shakir', username: '620001111', password: 'secret-pw-1');
      final a2 = await store.saveAccount(label: 'Alex', username: '620002222', password: 'secret-pw-2');

      final list = await store.listAccounts();
      expect(list.length, 2);
      expect(await store.activeAccountId(), a2.id);

      // Edit Alex without passing a password -> keeps original encrypted password.
      await store.saveAccount(id: a2.id, label: 'Alex M', username: '620002222', password: '');
      final updated = (await store.listAccounts()).firstWhere((a) => a.id == a2.id);
      expect(updated.label, 'Alex M');
      expect(updated.password, 'secret-pw-2');

      // Passwords are ONLY in secure storage, never in SharedPreferences or vle_accounts tool output.
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        final v = '${prefs.get(k)}';
        expect(v, isNot(contains('secret-pw-1')));
        expect(v, isNot(contains('secret-pw-2')));
      }
      final toolOut = await AssimilisTools.run('vle_accounts', {});
      expect(toolOut, contains('Shakir'));
      expect(toolOut, contains('Alex M'));
      expect(toolOut, isNot(contains('secret-pw')));

      await store.removeAccount(a1.id);
      expect((await store.listAccounts()).length, 1);
    });

    test('vle_scan logs into mock Moodle, scans courses, deadlines, resources, and news', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        final p = req.uri.path;
        if (p == '/login/index.php' && req.method == 'GET') {
          req.response
            ..headers.set('set-cookie', 'MoodleSession=abc123; Path=/')
            ..write('<input name="logintoken" value="tok999">');
        } else if (p == '/login/index.php' && req.method == 'POST') {
          final body = await utf8.decoder.bind(req).join();
          if (!body.contains('username=620001111') || !body.contains('logintoken=tok999')) {
            req.response.write('<div class="alert alert-danger">Bad login</div>');
          } else {
            req.response
              ..statusCode = 302
              ..headers.set('location', '$base/my/');
          }
        } else if (p == '/my/') {
          req.response.write('<script>M.cfg = {"sesskey":"sk_live_42"};</script>');
        } else if (p == '/lib/ajax/service.php') {
          final info = req.uri.queryParameters['info'];
          req.response.headers.contentType = ContentType.json;
          if (info == 'core_course_get_enrolled_courses_by_timeline_classification') {
            req.response.write(jsonEncode([
              {
                'error': false,
                'data': {
                  'courses': [
                    {
                      'id': 101,
                      'shortname': 'COMP2201',
                      'fullname': 'Discrete Mathematics',
                      'viewurl': '$base/course/view.php?id=101',
                      'progress': 60,
                    },
                  ],
                },
              }
            ]));
          } else {
            final due = (DateTime.now().add(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000);
            req.response.write(jsonEncode([
              {
                'error': false,
                'data': {
                  'events': [
                    {
                      'id': 501,
                      'name': 'Lab 4 Submission',
                      'modulename': 'assign',
                      'course': {'shortname': 'COMP2201', 'fullname': 'Discrete Mathematics'},
                      'timesort': due,
                      'url': '$base/mod/assign/view.php?id=501',
                    }
                  ],
                },
              }
            ]));
          }
        } else if (p == '/course/view.php') {
          req.response.write(
            '<a href="$base/mod/forum/view.php?id=10">Announcements</a>'
            '<a href="$base/mod/resource/view.php?id=11">Lecture 4 Slides (PDF)</a>'
            '<a href="$base/mod/quiz/view.php?id=12">Midterm Practice Quiz</a>',
          );
        } else if (p == '/mod/forum/view.php') {
          req.response.write(
            '<tr class="discussion"><th class="topic"><a href="$base/mod/forum/discuss.php?d=1">Lab 4 Extended</a></th>'
            '<td class="author"><a>Dr. Brown</a></td></tr>',
          );
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });

      try {
        await VleStore.instance.saveAccount(
          label: 'Shakir',
          username: '620001111',
          password: 'pw',
          baseUrl: base,
        );
        final out = await AssimilisTools.run('vle_scan', {'account': 'Shakir', 'refresh': true});
        expect(out, contains('COMP2201'));
        expect(out, contains('Lab 4 Submission'));
        expect(out, contains('Lab 4 Extended'));
        expect(out, contains('Lecture 4 Slides (PDF)'));
        expect(out, contains('Midterm Practice Quiz'));
      } finally {
        await server.close(force: true);
      }
    });
  });

  group('M6 · QR Connect & HES Sync', () {
    test('QR payload & pairing key encode/decode for own device vs friend', () async {
      final sync = HesSync.instance;
      final ownQr = await sync.buildQrPayload(mode: 'sync', host: '100.64.0.9');
      final ownMap = HesSync.parsePayload(ownQr);
      expect(ownMap['mode'], 'sync');
      expect(ownMap['url'], 'http://100.64.0.9:47800');
      expect('${ownMap['key']}', startsWith('hsk_'));

      final friendKey = await sync.buildPairingKey(mode: 'friend', host: '192.168.1.50');
      expect(friendKey, startsWith('ASM1:'));
      final friendMap = HesSync.parsePayload(friendKey);
      expect(friendMap['mode'], 'friend');
      expect(friendMap.containsKey('key'), isFalse);

      final uriMap = HesSync.parsePayload('assimilis://sync?mode=desktop&url=http://100.64.0.7:8787&key=abc123');
      expect(uriMap['mode'], 'desktop');
      expect(uriMap['url'], 'http://100.64.0.7:8787');
      expect(uriMap['key'], 'abc123');
    });

    test('two-way HES sync authenticates key and merges events without duplicates', () async {
      await HesStore.instance.state();
      await HesStore.instance.log('pushups', 20);
      final localCount = HesStore.instance.events.length;

      final remoteDoc = {
        'modules': ['pushups', 'reading'],
        'events': [
          {
            'id': 'ev-remote-1',
            'at': DateTime.now().millisecondsSinceEpoch / 1000,
            'status': 'applied',
            'source': 'tablet',
            'kind': 'log',
            'module': 'reading',
            'quantity': 15,
            'summary': 'Reading',
          },
        ],
        'system_facts': ['Prefers morning training'],
      };

      const peerSecret = 'hsk_peer_secret_999';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        if (req.uri.path == '/hes/card') {
          req.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'player': 'Rival', 'rank': 'A', 'level': 14, 'className': 'Shadow Mage', 'power': 240}));
        } else if (req.uri.path == '/hes/sync') {
          if (req.headers.value('x-assimilis-sync-key') != peerSecret) {
            req.response
              ..statusCode = 401
              ..write(jsonEncode({'error': 'Invalid sync key'}));
          } else {
            req.response
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'ok': true, 'doc': remoteDoc, 'card': {'player': 'Shakir', 'rank': 'C', 'level': 5}}));
          }
        } else if (req.uri.path == '/api/hes/sync') {
          req.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'ok': true, 'doc': {'events': []}}));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });

      try {
        final base = 'http://127.0.0.1:${server.port}';
        // Wrong key is rejected.
        final badPayload = jsonEncode({'v': 1, 'mode': 'sync', 'id': 'tab-1', 'name': 'Tablet', 'url': base, 'key': 'wrong'});
        await expectLater(HesSync.instance.connectFromPayload(badPayload), throwsException);

        // Correct key performs two-way merge.
        final goodPayload = jsonEncode({'v': 1, 'mode': 'sync', 'id': 'tab-1', 'name': 'Tablet', 'url': base, 'key': peerSecret});
        final msg = await HesSync.instance.connectFromPayload(goodPayload);
        expect(msg, contains('Synced with Tablet'));
        expect(msg, contains('+1 events'));
        expect(HesStore.instance.events.length, localCount + 1);

        // Re-syncing the same remote doc does not duplicate events.
        final again = await HesSync.instance.syncPeer('tab-1');
        expect(again, contains('+0 events'));
        expect(HesStore.instance.events.length, localCount + 1);

        // Friend QR fetches Hunter Card without touching local events.
        final friendQr = jsonEncode({'v': 1, 'mode': 'friend', 'id': 'friend-1', 'name': 'Rival Phone', 'url': base});
        final friendMsg = await HesSync.instance.connectFromPayload(friendQr);
        expect(friendMsg, contains('Rival'));
        expect(friendMsg, contains('Rank A'));

        // Desktop / VPS sync succeeds.
        final deskMsg = await HesSync.instance.syncWithDesktop(url: base, key: 'desk-key');
        expect(deskMsg, contains('Desktop/VPS synced'));
      } finally {
        await server.close(force: true);
      }
    });
  });

  group('M6 · WhatsApp pairing code & receiver number', () {
    test('requests 8-char pairing code, checks status, and sends to receiver via whatsapp_send tool', () async {
      String? lastTo;
      String? lastMsg;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.headers.contentType = ContentType.json;
        if (req.uri.path == '/api/whatsapp/pair' && req.method == 'POST') {
          final d = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
          expect(d['phone'], '18765550123');
          expect(d['receiver'], '18765550999');
          req.response.write(jsonEncode({'pairing_code': 'ab12cd34', 'status': 'pairing'}));
        } else if (req.uri.path == '/api/whatsapp/status') {
          req.response.write(jsonEncode({'connected': true, 'status': 'connected'}));
        } else if (req.uri.path == '/api/whatsapp/send' && req.method == 'POST') {
          final d = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
          lastTo = '${d['to']}';
          lastMsg = '${d['text']}';
          req.response.write(jsonEncode({'ok': true}));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });

      try {
        final base = 'http://127.0.0.1:${server.port}';
        final pair = await WhatsAppLink.instance.requestPairingCode(
          agent: '+1 (876) 555-0123',
          receiver: '+1 876 555 0999',
          bridgeUrl: base,
          token: 'wa-secret-token',
        );
        expect(pair.code, 'AB12-CD34');

        final st = await WhatsAppLink.instance.status();
        expect(st.connected, isTrue);
        expect(st.agentNumber, '18765550123');
        expect(st.receiverNumber, '18765550999');

        final sent = await AssimilisTools.run('whatsapp_send', {'message': 'Daily quest due in 30 min'});
        expect(sent, contains('+18765550999'));
        expect(lastTo, '18765550999');
        expect(lastMsg, 'Daily quest due in 30 min');
      } finally {
        await server.close(force: true);
      }
    });
  });
}
