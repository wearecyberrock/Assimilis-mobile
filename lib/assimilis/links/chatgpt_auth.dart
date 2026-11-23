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

  /// One reply from the ChatGPT subscription as plain text.
  Future<String> chat(List<Map<String, String>> messages, {String system = '', String model = 'gpt-6-sol', void Function(String)? onDelta}) async {
    final r = await complete([
      if (system.isNotEmpty) {'role': 'system', 'content': system},
      ...messages,
    ], model: model, onDelta: onDelta);
    return '${r['content'] ?? ''}'.trim();
  }

  /// A full chat-completions turn through the ChatGPT subscription (Codex Responses API), with tools.
  ///
  /// Takes OpenAI chat-completions [messages] (system, user with text or images, assistant with tool_calls, tool
  /// results) and [tools], and returns an OpenAI assistant message: `{role, content, tool_calls?}`. Text is
  /// streamed to [onDelta]. This is what lets every agent do anything (phone, HES, MCP tools) on ChatGPT.
  Future<Map<String, dynamic>> complete(List<Map<String, dynamic>> messages,
      {String model = 'gpt-6-sol', List? tools, dynamic toolChoice, void Function(String)? onDelta}) async {
    final token = await _accessToken();
    final t = await _load();
    final auth = _claims(t?['id_token'])['https://api.openai.com/auth'] as Map? ?? const {};
    final accountId = auth['chatgpt_account_id'] as String?;
    final body = toResponsesBody(messages, model: model, tools: tools, toolChoice: toolChoice);
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
      ..body = jsonEncode(body);
    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 120));
      if (res.statusCode >= 400) {
        final b = await res.stream.bytesToString();
        throw Exception('ChatGPT returned ${res.statusCode}: ${b.length > 200 ? b.substring(0, 200) : b}');
      }
      final text = StringBuffer();
      final calls = <Map<String, dynamic>>[];
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        Map ev;
        try {
          ev = jsonDecode(data) as Map;
        } on FormatException {
          continue; // keep-alives
        }
        switch (ev['type']) {
          case 'response.output_text.delta':
            text.write(ev['delta']);
            onDelta?.call('${ev['delta']}');
          case 'response.output_item.done':
            final item = ev['item'] as Map? ?? const {};
            if (item['type'] == 'function_call') {
              calls.add({
                'id': '${item['call_id'] ?? item['id']}',
                'type': 'function',
                'function': {'name': '${item['name']}', 'arguments': '${item['arguments'] ?? '{}'}'},
              });
            }
          case 'response.failed':
          case 'error':
            throw Exception('${ev['response']?['error']?['message'] ?? ev['message'] ?? 'ChatGPT error'}');
        }
      }
      return {
        'role': 'assistant',
        'content': text.toString(),
        if (calls.isNotEmpty) 'tool_calls': calls,
      };
    } finally {
      client.close();
    }
  }

  static String _textOf(dynamic content) {
    if (content is String) return content;
    if (content is List) return content.map((p) => p is Map ? '${p['text'] ?? ''}' : '$p').where((x) => x.isNotEmpty).join('\n');
    return content == null ? '' : '$content';
  }

  /// Chat-completions request → Codex Responses request (public for tests).
  static Map<String, dynamic> toResponsesBody(List<Map<String, dynamic>> messages, {required String model, List? tools, dynamic toolChoice}) {
    final instructions = [for (final m in messages) if (m['role'] == 'system' || m['role'] == 'developer') _textOf(m['content'])]
        .where((x) => x.isNotEmpty)
        .join('\n\n');
    final input = <Map<String, dynamic>>[];
    for (final m in messages) {
      final role = '${m['role']}';
      if (role == 'system' || role == 'developer') continue;
      if (role == 'tool') {
        input.add({'type': 'function_call_output', 'call_id': '${m['tool_call_id']}', 'output': _textOf(m['content'])});
        continue;
      }
      if (role == 'assistant') {
        final txt = _textOf(m['content']);
        if (txt.isNotEmpty) {
          input.add({
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': txt}
            ],
          });
        }
        for (final c in (m['tool_calls'] as List? ?? const [])) {
          final f = (c as Map)['function'] as Map? ?? const {};
          input.add({'type': 'function_call', 'call_id': '${c['id']}', 'name': '${f['name']}', 'arguments': '${f['arguments'] ?? '{}'}'});
        }
        continue;
      }
      final content = m['content'];
      final parts = <Map<String, dynamic>>[];
      if (content is List) {
        for (final p in content) {
          if (p is! Map) continue;
          if (p['type'] == 'image_url') {
            final u = p['image_url'];
            parts.add({'type': 'input_image', 'image_url': u is Map ? '${u['url']}' : '$u'});
          } else if (p['text'] != null) {
            parts.add({'type': 'input_text', 'text': '${p['text']}'});
          }
        }
      } else {
        parts.add({'type': 'input_text', 'text': _textOf(content)});
      }
      input.add({'type': 'message', 'role': 'user', 'content': parts});
    }
    return {
      'model': model,
      'instructions': instructions,
      'input': input,
      if (tools != null && tools.isNotEmpty) ...{
        'tools': [
          for (final tl in tools)
            if (tl is Map && tl['type'] == 'function')
              {
                'type': 'function',
                'name': (tl['function'] as Map)['name'],
                'description': (tl['function'] as Map)['description'] ?? '',
                'parameters': (tl['function'] as Map)['parameters'] ?? {'type': 'object', 'properties': {}},
                'strict': false,
              }
        ],
        'tool_choice': toolChoice is String ? toolChoice : 'auto',
        'parallel_tool_calls': true,
      },
      'stream': true,
      'store': false,
    };
  }
}
