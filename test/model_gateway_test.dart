import 'dart:convert';
import 'dart:io';

import 'package:assimilis_mobile/assimilis/links/chatgpt_auth.dart';
import 'package:assimilis_mobile/assimilis/links/model_gateway.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secure = <String, String>{};

  setUpAll(() {
    HttpOverrides.global = null; // flutter_test answers every real request with 400; the gateway tests need sockets
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
      final a = Map<String, dynamic>.from(c.arguments as Map? ?? {});
      switch (c.method) {
        case 'read':
          return secure[a['key']];
        case 'write':
          secure['${a['key']}'] = '${a['value']}';
          return null;
        case 'delete':
          secure.remove(a['key']);
          return null;
        case 'readAll':
          return secure;
        default:
          return null;
      }
    });
  });

  group('model gateway', () {
    setUpAll(() async => ModelGateway.instance.start());
    tearDownAll(() async => ModelGateway.instance.stop());

    Future<HttpClientResponse> call(String method, String path, {String? token, Object? body}) async {
      final c = HttpClient();
      final r = await c.openUrl(method, Uri.parse('http://127.0.0.1:${ModelGateway.port}$path'));
      if (token != null) r.headers.set('Authorization', 'Bearer $token');
      if (body != null) {
        r.headers.contentType = ContentType.json;
        r.write(jsonEncode(body));
      }
      return r.close();
    }

    test('answers health without a key and refuses a wrong key', () async {
      expect((await call('GET', '/health')).statusCode, 200);
      expect((await call('GET', '/v1/models', token: 'nope')).statusCode, 401);
    });

    test('lists models with its key', () async {
      final t = await ModelGateway.instance.token();
      expect(t, startsWith('asm_'));
      final r = await call('GET', '/v1/models', token: t);
      expect(r.statusCode, 200);
      final d = jsonDecode(await utf8.decodeStream(r));
      expect(d['object'], 'list');
      expect(d['data'], isA<List>());
    });

    test('names the usable models for an unknown one', () async {
      final r = await call('POST', '/v1/chat/completions', token: await ModelGateway.instance.token(), body: {
        'model': 'nowhere/x',
        'messages': [
          {'role': 'user', 'content': 'hi'}
        ],
      });
      expect(r.statusCode, 404);
      expect(await utf8.decodeStream(r), contains('Unknown model'));
    });

    test('a shared provider with no key is refused with a clear message', () async {
      final r = await call('POST', '/v1/chat/completions', token: await ModelGateway.instance.token(), body: {
        'model': 'openrouter/some-model',
        'messages': [
          {'role': 'user', 'content': 'hi'}
        ],
      });
      expect(r.statusCode, 401);
      expect(await utf8.decodeStream(r), contains('No OpenRouter key'));
    });
  });

  group('ChatGPT device-code sign-in', () {
    test('gets a link and code, waits for approval, then saves tokens', () async {
      var polls = 0;
      final mock = MockClient((req) async {
        final p = req.url.path;
        if (p == '/api/accounts/deviceauth/usercode') {
          expect(jsonDecode(req.body)['client_id'], ChatGptAuth.clientId);
          return http.Response(jsonEncode({'user_code': 'ABCD-1234', 'device_auth_id': 'dev-1', 'interval': '3'}), 200);
        }
        if (p == '/api/accounts/deviceauth/token') {
          polls++;
          if (polls < 2) return http.Response('{}', 403); // not approved yet
          return http.Response(jsonEncode({'authorization_code': 'code-1', 'code_verifier': 'ver-1'}), 200);
        }
        if (p == '/oauth/token') {
          expect(req.bodyFields['grant_type'], 'authorization_code');
          expect(req.bodyFields['code_verifier'], 'ver-1');
          expect(req.bodyFields['redirect_uri'], 'https://auth.openai.com/deviceauth/callback');
          return http.Response(jsonEncode({'access_token': 'at', 'refresh_token': 'rt', 'id_token': 'x.e30.y', 'expires_in': 3600}), 200);
        }
        return http.Response('not found', 404);
      });
      await http.runWithClient(() async {
        final code = await ChatGptAuth.instance.startDeviceSignIn();
        expect(code.userCode, 'ABCD-1234');
        expect(code.url, 'https://auth.openai.com/codex/device');
        expect(code.interval, 3);
        final msg = await ChatGptAuth.instance.finishDeviceSignIn(code);
        expect(msg, startsWith('Signed in to ChatGPT'));
      }, () => mock);
      expect(polls, 2);
      expect(await ChatGptAuth.instance.signedIn, isTrue);
      await ChatGptAuth.instance.signOut();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('ChatGPT with tools', () {
    test('chat-completions turns become a Codex Responses request', () {
      final b = ChatGptAuth.toResponsesBody([
        {'role': 'system', 'content': 'You are A.'},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'How many calories?'},
            {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,AAAA'}},
          ]
        },
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'call_1', 'type': 'function', 'function': {'name': 'hes_log', 'arguments': '{"text":"rice"}'}}
          ]
        },
        {'role': 'tool', 'tool_call_id': 'call_1', 'content': 'logged'},
      ], model: 'gpt-6-sol', tools: [
        {'type': 'function', 'function': {'name': 'hes_log', 'description': 'Log to HES', 'parameters': {'type': 'object', 'properties': {}}}}
      ]);
      expect(b['instructions'], 'You are A.');
      final input = b['input'] as List;
      expect(input[0]['content'][1], {'type': 'input_image', 'image_url': 'data:image/jpeg;base64,AAAA'});
      expect(input[1], {'type': 'function_call', 'call_id': 'call_1', 'name': 'hes_log', 'arguments': '{"text":"rice"}'});
      expect(input[2], {'type': 'function_call_output', 'call_id': 'call_1', 'output': 'logged'});
      expect((b['tools'] as List).first['name'], 'hes_log');
      expect(b['stream'], true);
    });

    test('an agent gets tool calls back from ChatGPT through the gateway', () async {
      secure['asm_chatgpt_tokens'] = jsonEncode({
        'access_token': 'at',
        'refresh_token': 'rt',
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      });
      Map? sent;
      final mock = MockClient.streaming((req, bodyStream) async {
        sent = jsonDecode(await utf8.decodeStream(bodyStream)) as Map;
        final events = [
          {'type': 'response.output_text.delta', 'delta': 'Logging it.'},
          {
            'type': 'response.output_item.done',
            'item': {'type': 'function_call', 'call_id': 'call_9', 'name': 'hes_log', 'arguments': '{"text":"30 pushups"}'}
          },
          {'type': 'response.completed'},
        ];
        return http.StreamedResponse(Stream.value(utf8.encode(events.map((e) => 'data: ${jsonEncode(e)}\n\n').join())), 200,
            headers: {'content-type': 'text/event-stream'});
      });
      await ModelGateway.instance.stop();
      await http.runWithClient(() async {
        await ModelGateway.instance.start(); // its handlers now use the mocked ChatGPT
        final c = HttpClient();
        final r = await c.postUrl(Uri.parse('${ModelGateway.baseUrl}/chat/completions'));
        r.headers.set('Authorization', 'Bearer ${await ModelGateway.instance.token()}');
        r.headers.contentType = ContentType.json;
        r.write(jsonEncode({
          'model': 'chatgpt/gpt-6-sol',
          'messages': [
            {'role': 'system', 'content': 'You are A.'},
            {'role': 'user', 'content': 'I did 30 pushups'},
          ],
          'tools': [
            {'type': 'function', 'function': {'name': 'hes_log', 'description': 'Log to HES', 'parameters': {'type': 'object', 'properties': {}}}}
          ],
        }));
        final res = await r.close();
        expect(res.statusCode, 200);
        final d = jsonDecode(await utf8.decodeStream(res));
        final msg = d['choices'][0]['message'];
        expect(d['choices'][0]['finish_reason'], 'tool_calls');
        expect(msg['content'], 'Logging it.');
        expect(msg['tool_calls'][0]['function']['name'], 'hes_log');
        expect(msg['tool_calls'][0]['id'], 'call_9');
      }, () => mock);
      await ModelGateway.instance.stop();
      expect(sent!['model'], 'gpt-6-sol');
      expect(sent!['instructions'], 'You are A.');
      expect((sent!['tools'] as List).single['name'], 'hes_log');
    });
  });
}
