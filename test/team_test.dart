import 'dart:convert';
import 'dart:io';

import 'package:assimilis_mobile/assimilis/team/team_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = null;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('manager delegates to worker and workstation, then checker triggers revision', () async {
    var turn = 0;
    final calls = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
      final msgs = List<Map<String, dynamic>>.from(body['messages'] as List);
      final sys = '${msgs.first['content']}';
      turn++;

      Map<String, dynamic> reply;
      if (sys.contains('You are the Manager') && msgs.length == 2 && !'${msgs[1]['content']}'.contains('Checker feedback')) {
        // Turn 1: Manager delegates to worker and calls workstation_task.
        reply = {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'delegate_to_role',
                'arguments': jsonEncode({'role': 'worker', 'instruction': 'Compute 12 * 12'}),
              },
            },
            {
              'id': 'call_2',
              'type': 'function',
              'function': {
                'name': 'workstation_task',
                'arguments': jsonEncode({'task': 'Verify device clock'}),
              },
            },
          ],
        };
      } else if (sys.contains('You are the Worker')) {
        if (msgs.length == 2) {
          reply = {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': 'call_w1',
                'type': 'function',
                'function': {'name': 'calculate', 'arguments': jsonEncode({'expression': '12 * 12'})},
              },
            ],
          };
        } else {
          reply = {'role': 'assistant', 'content': 'Worker result: 144.'};
        }
      } else if (sys.contains('Assimilis Workstation agent')) {
        if (msgs.length == 2) {
          reply = {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': 'call_ws1',
                'type': 'function',
                'function': {'name': 'get_current_time', 'arguments': '{}'},
              },
            ],
          };
        } else {
          reply = {'role': 'assistant', 'content': 'Workstation checked time.'};
        }
      } else if (sys.contains('You are the Checker')) {
        reply = {'role': 'assistant', 'content': 'REVISE: Mention the exact product 144 and Workstation check clearly.'};
      } else if ('${msgs[1]['content']}'.contains('Checker feedback')) {
        reply = {'role': 'assistant', 'content': 'Final verified answer: 12 * 12 = 144, and Workstation verified time.'};
      } else {
        reply = {'role': 'assistant', 'content': 'Draft answer: about 144.'};
      }

      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'id': 'cmpl-$turn',
          'choices': [
            {'index': 0, 'message': reply, 'finish_reason': 'stop'}
          ],
        }));
      await req.response.close();
    });

    try {
      final base = 'http://127.0.0.1:${server.port}/v1';
      final run = await TeamEngine.instance.runTask(
        goal: 'Compute 12 * 12 and check device time',
        roles: TeamEngine.defaultRoles(),
        endpointResolver: (role) async => (base: base, model: 'mock-${role.id}', key: 'k'),
        toolRunner: (name, args) async {
          calls.add(name);
          if (name == 'calculate') return '12 * 12 = 144';
          if (name == 'get_current_time') return '2026-11-23T12:00:00';
          return 'ok:$name';
        },
      );

      expect(run.status, 'done');
      expect(calls, containsAll(['calculate', 'get_current_time']));
      expect(run.steps.any((s) => s.roleId == 'worker'), isTrue);
      expect(run.steps.any((s) => s.roleId == 'workstation'), isTrue);
      expect(run.steps.any((s) => s.roleId == 'checker'), isTrue);
      expect(run.finalAnswer, contains('Final verified answer: 12 * 12 = 144'));

      final hist = await TeamEngine.instance.history();
      expect(hist, isNotEmpty);
      expect(hist.first.id, run.id);
    } finally {
      await server.close(force: true);
    }
  });

  test('checker APPROVED skips extra revision pass', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var managerCalls = 0;
    server.listen((req) async {
      final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
      final sys = '${(body['messages'] as List).first['content']}';
      String content;
      if (sys.contains('You are the Checker')) {
        content = 'APPROVED: Everything checks out.';
      } else {
        managerCalls++;
        content = 'Complete clean answer.';
      }
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': content}
            }
          ],
        }));
      await req.response.close();
    });

    try {
      final base = 'http://127.0.0.1:${server.port}/v1';
      final run = await TeamEngine.instance.runTask(
        goal: 'Simple check',
        roles: TeamEngine.defaultRoles(),
        allowPhoneAgent: false,
        allowA2a: false,
        endpointResolver: (role) async => (base: base, model: 'mock', key: 'k'),
      );
      expect(run.status, 'done');
      expect(managerCalls, 1);
      expect(run.finalAnswer, 'Complete clean answer.');
    } finally {
      await server.close(force: true);
    }
  });
}
