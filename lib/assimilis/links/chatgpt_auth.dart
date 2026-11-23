import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// A sign-in code from OpenAI: open [url] and type [userCode] there.
class ChatGptDeviceCode {
  final String userCode, deviceAuthId, url;
  final int interval;
  const ChatGptDeviceCode({required this.userCode, required this.deviceAuthId, required this.url, required this.interval});
}

/// "Sign in with ChatGPT": the same device-code flow the Codex CLI (and Hermes) use, so your ChatGPT
/// subscription can answer in Assimilis. The owner chose this knowing it is outside OpenAI's
/// intended use for third-party apps; tokens stay in the Android keystore.
class ChatGptAuth {
  ChatGptAuth._();
  static final ChatGptAuth instance = ChatGptAuth._();

  static const clientId = 'app_EMoamEEZ73f0CkXaXp7hrann'; // public Codex CLI client id
  static const _issuer = 'https://auth.openai.com';
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

  /// Step 1 of "Sign in with ChatGPT" (the device-code flow the Codex CLI and Hermes use): asks OpenAI for a code.
  /// Show the user [ChatGptDeviceCode.url] (the long link) and [ChatGptDeviceCode.userCode] (the key they type in).
  Future<ChatGptDeviceCode> startDeviceSignIn() async {
    final res = await http
        .post(Uri.parse('$_issuer/api/accounts/deviceauth/usercode'),
            headers: const {'Content-Type': 'application/json'}, body: jsonEncode({'client_id': clientId}))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('OpenAI refused the sign-in request (${res.statusCode}). Turn on "device code sign-in" for Codex in '
          'your ChatGPT security settings, then try again.');
    }
    if (res.statusCode != 200) throw Exception('OpenAI did not give a sign-in code (${res.statusCode}).');
    final d = Map<String, dynamic>.from(jsonDecode(res.body));
    final userCode = '${d['user_code'] ?? d['usercode'] ?? ''}';
    final id = '${d['device_auth_id'] ?? ''}';
    if (userCode.isEmpty || id.isEmpty) throw Exception('OpenAI\'s sign-in reply was missing the code.');
    final interval = max(3, int.tryParse('${d['interval'] ?? 5}') ?? 5);
    return ChatGptDeviceCode(userCode: userCode, deviceAuthId: id, interval: interval, url: '$_issuer/codex/device');
  }

  /// Step 2: waits (up to 15 minutes) until the user has typed the code on the link, then saves the tokens.
  /// [cancelled] is checked between polls so the dialog can stop waiting.
  Future<String> finishDeviceSignIn(ChatGptDeviceCode code, {bool Function()? cancelled}) async {
    final deadline = DateTime.now().add(const Duration(minutes: 15));
    Map<String, dynamic>? auth;
    var blips = 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(seconds: code.interval));
      if (cancelled?.call() == true) throw Exception('Sign-in cancelled.');
      http.Response poll;
      try {
        poll = await http
            .post(Uri.parse('$_issuer/api/accounts/deviceauth/token'),
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode({'device_auth_id': code.deviceAuthId, 'user_code': code.userCode}))
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        if (++blips >= 6) throw Exception('Lost the connection while waiting for ChatGPT: $e');
        continue;
      }
      blips = 0;
      if (poll.statusCode == 200) {
        auth = Map<String, dynamic>.from(jsonDecode(poll.body));
        break;
      }
      if (poll.statusCode == 403 || poll.statusCode == 404) continue; // not approved yet
      throw Exception('ChatGPT sign-in stopped (${poll.statusCode}).');
    }
    if (auth == null) throw Exception('The code expired. Start the sign-in again.');
    final authorizationCode = '${auth['authorization_code'] ?? ''}';
    final verifier = '${auth['code_verifier'] ?? ''}';
    if (authorizationCode.isEmpty || verifier.isEmpty) throw Exception('ChatGPT approved but sent no sign-in code.');
    http.Response? res;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        res = await http.post(Uri.parse('$_issuer/oauth/token'), headers: const {
          'Content-Type': 'application/x-www-form-urlencoded'
        }, body: {
          'grant_type': 'authorization_code',
          'code': authorizationCode,
          'redirect_uri': '$_issuer/deviceauth/callback',
          'client_id': clientId,
          'code_verifier': verifier,
        }).timeout(const Duration(seconds: 20));
        break;
      } catch (_) {
        if (attempt == 3) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
    if (res == null || res.statusCode != 200) throw Exception('Token exchange failed (${res?.statusCode}).');
    final t = Map<String, dynamic>.from(jsonDecode(res.body));
    if (t['access_token'] == null) throw Exception('ChatGPT sent no access token.');
    t['expires_at'] = DateTime.now().millisecondsSinceEpoch ~/ 1000 + ((t['expires_in'] ?? 3600) as num).toInt();
    await _save(t);
    final who = await email;
    return 'Signed in to ChatGPT${who == null ? '' : ' as $who'}.';
  }

  /// Opens the link in the browser for a [code] (the user then types the code there).
  Future<void> openLink(ChatGptDeviceCode code) => launchUrl(Uri.parse(code.url), mode: LaunchMode.externalApplication);

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
    final sys = [system, for (final m in messages) if (m['role'] == 'system') m['content'] ?? ''].where((x) => x.isNotEmpty).join('\n\n');
    messages = [for (final m in messages) if (m['role'] != 'system') m];
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
        'instructions': sys,
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
