import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// "Sign in with ChatGPT": the same OAuth flow the Codex CLI (and Hermes) use, so your ChatGPT
/// subscription can answer in Assimilis. The owner chose this knowing it is outside OpenAI's
/// intended use for third-party apps; tokens stay in the Android keystore.
class ChatGptAuth {
  ChatGptAuth._();
  static final ChatGptAuth instance = ChatGptAuth._();

  static const clientId = 'app_EMoamEEZ73f0CkXaXp7hrann'; // public Codex CLI client id
  static const _issuer = 'https://auth.openai.com';
  static const _port = 1455;
  static const _redirect = 'http://localhost:$_port/auth/callback';
  static const responsesUrl = 'https://chatgpt.com/backend-api/codex/responses';
  static const models = ['gpt-6-sol', 'gpt-6-astra', 'gpt-6-luna', 'gpt-6.1-sol', 'gpt-6.1-terra', 'gpt-5.6-sol'];

  static const _store = FlutterSecureStorage();
  static const _k = 'asm_chatgpt_tokens';

  Map<String, dynamic>? _tokens;

  Future<Map<String, dynamic>?> _load() async {
    if (_tokens != null) return _tokens;
    final raw = await _store.read(key: _k);
    _tokens = raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw));
    return _tokens;
  }

  Future<void> _save(Map<String, dynamic> t) async {
    _tokens = t;
    await _store.write(key: _k, value: jsonEncode(t));
  }

  Future<bool> get signedIn async => (await _load())?['refresh_token'] != null;

  Future<String?> get email async {
    final t = await _load();
    final c = _claims(t?['id_token']);
    return c['email'] as String?;
  }

  Future<void> signOut() async {
    _tokens = null;
    await _store.delete(key: _k);
  }

  static String _b64url(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  static Map<String, dynamic> _claims(String? jwt) {
    if (jwt == null) return {};
    final parts = jwt.split('.');
    if (parts.length < 2) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))));
    } catch (_) {
      return {};
    }
  }

  /// Opens ChatGPT's sign-in page and waits for the redirect back to this phone.
  Future<String> signIn() async {
    final rnd = Random.secure();
    final verifier = _b64url(List.generate(64, (_) => rnd.nextInt(256)));
    final challenge = _b64url(sha256.convert(ascii.encode(verifier)).bytes);
    final state = _b64url(List.generate(24, (_) => rnd.nextInt(256)));

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port, shared: true);
    final code = Completer<String>();
    final sub = server.listen((req) async {
      if (req.uri.path != '/auth/callback') {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final q = req.uri.queryParameters;
      final ok = q['state'] == state && q['code'] != null;
      req.response.headers.contentType = ContentType.html;
      req.response.write('<html><body style="background:#121216;color:#EDEDF2;font-family:sans-serif;text-align:center;padding-top:30vh">'
          '<h2 style="color:#A855F7">${ok ? 'Signed in to ChatGPT' : 'Sign-in failed'}</h2>'
          '<p>You can go back to Assimilis.</p></body></html>');
      await req.response.close();
      if (!code.isCompleted) ok ? code.complete(q['code']) : code.completeError(q['error_description'] ?? 'Sign-in was cancelled.');
    });

    final url = Uri.parse('$_issuer/oauth/authorize').replace(queryParameters: {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': _redirect,
      'scope': 'openid profile email offline_access',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'id_token_add_organizations': 'true',
      'codex_cli_simplified_flow': 'true',
      'state': state,
      'originator': 'codex_cli_rs',
    });
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      final c = await code.future.timeout(const Duration(minutes: 5));
      final res = await http.post(Uri.parse('$_issuer/oauth/token'), headers: {
        'Content-Type': 'application/x-www-form-urlencoded'
      }, body: {
        'grant_type': 'authorization_code',
        'code': c,
        'redirect_uri': _redirect,
        'client_id': clientId,
        'code_verifier': verifier,
      });
      if (res.statusCode >= 400) throw Exception('Token exchange failed (${res.statusCode}).');
      final t = Map<String, dynamic>.from(jsonDecode(res.body));
      t['expires_at'] = DateTime.now().millisecondsSinceEpoch ~/ 1000 + ((t['expires_in'] ?? 3600) as num).toInt();
      await _save(t);
      return 'Signed in to ChatGPT${(await email) == null ? '' : ' as ${await email}'}.';
    } finally {
      await sub.cancel();
      await server.close(force: true);
    }
  }

  Future<String> _accessToken() async {
    final t = await _load();
    if (t == null) throw Exception('Not signed in to ChatGPT.');
    final exp = (t['expires_at'] ?? 0) as int;
    if (DateTime.now().millisecondsSinceEpoch ~/ 1000 < exp - 120) return t['access_token'];
    final res = await http.post(Uri.parse('$_issuer/oauth/token'), headers: {
      'Content-Type': 'application/json'
    }, body: jsonEncode({
      'client_id': clientId,
      'grant_type': 'refresh_token',
      'refresh_token': t['refresh_token'],
      'scope': 'openid profile email',
    }));
    if (res.statusCode >= 400) throw Exception('ChatGPT session expired; sign in again.');
    final n = Map<String, dynamic>.from(jsonDecode(res.body));
    final merged = {...t, ...n};
    merged['expires_at'] = DateTime.now().millisecondsSinceEpoch ~/ 1000 + ((n['expires_in'] ?? 3600) as num).toInt();
    await _save(merged);
    return merged['access_token'];
  }

  /// One reply from the ChatGPT subscription (Responses API, streamed and collected).
  Future<String> chat(List<Map<String, String>> messages, {String system = '', String model = 'gpt-6-sol', void Function(String)? onDelta}) async {
    final token = await _accessToken();
    final t = await _load();
    final auth = _claims(t?['id_token'])['https://api.openai.com/auth'] as Map? ?? const {};
    final accountId = auth['chatgpt_account_id'] as String?;
    final req = http.Request('POST', Uri.parse(responsesUrl))
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'OpenAI-Beta': 'responses=experimental',
        'originator': 'codex_cli_rs',
        'session_id': _b64url(List.generate(16, (_) => Random().nextInt(256))),
        if (accountId != null) 'chatgpt-account-id': accountId,
      })
      ..body = jsonEncode({
        'model': model,
        'instructions': system,
        'input': [
          for (final m in messages)
            {
              'type': 'message',
              'role': m['role'] == 'assistant' ? 'assistant' : 'user',
              'content': [
                {'type': m['role'] == 'assistant' ? 'output_text' : 'input_text', 'text': m['content'] ?? ''}
              ],
            }
        ],
        'stream': true,
        'store': false,
      });
    final res = await http.Client().send(req).timeout(const Duration(seconds: 120));
    if (res.statusCode >= 400) {
      final body = await res.stream.bytesToString();
      throw Exception('ChatGPT returned ${res.statusCode}: ${body.length > 200 ? body.substring(0, 200) : body}');
    }
    final out = StringBuffer();
    await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      try {
        final ev = jsonDecode(data);
        if (ev['type'] == 'response.output_text.delta') {
          out.write(ev['delta']);
          onDelta?.call('${ev['delta']}');
        } else if (ev['type'] == 'response.failed' || ev['type'] == 'error') {
          throw Exception('${ev['response']?['error']?['message'] ?? ev['message'] ?? 'ChatGPT error'}');
        }
      } on FormatException {
        // ignore keep-alives
      }
    }
    return out.toString().trim();
  }
}
