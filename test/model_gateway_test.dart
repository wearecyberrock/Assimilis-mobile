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
}
