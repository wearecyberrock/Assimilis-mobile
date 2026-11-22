import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../settings.dart';

/// Link to your own Assimilis / Hermes (laptop or VPS) over LAN or Tailscale.
/// It answers with any model Hermes has, including your ChatGPT / Claude / Antigravity subscriptions
/// (they stay on that machine, so nothing breaks their terms here), and speaks with the core's own voice.
class HermesLink {
  HermesLink._();
  static final HermesLink instance = HermesLink._();
  static const _secure = FlutterSecureStorage();

  final _c = http.Client();
  final _cookies = <String, String>{};
  String? _sessionId;

  Future<String> get url async =>
      ((await AssimilisSettings.get()).blob('hermes_url') ?? '').replaceAll(RegExp(r'/+$'), '');
  Future<bool> get configured async => (await url).isNotEmpty;
  Future<String> get model async => (await AssimilisSettings.get()).blob('hermes_model') ?? '';

  Future<void> configure(String baseUrl, String password, {String? model}) async {
    final s = await AssimilisSettings.get();
    await s.setBlob('hermes_url', baseUrl.trim().replaceAll(RegExp(r'/+$'), ''));
    if (model != null) await s.setBlob('hermes_model', model);
    if (password.isNotEmpty) await _secure.write(key: 'asm_hermes_pw', value: password);
    _cookies.clear();
    _sessionId = null;
  }

  Map<String, String> _headers(String base, {bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        'Origin': base, // the server checks Origin on POST
        'Referer': '$base/',
        if (_cookies.isNotEmpty) 'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      };

  void _take(http.BaseResponse r) {
    final raw = r.headers['set-cookie'];
    if (raw == null) return;
    for (final part in raw.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'))) {
      final kv = part.split(';').first.trim();
      final i = kv.indexOf('=');
      if (i > 0) _cookies[kv.substring(0, i)] = kv.substring(i + 1);
    }
  }

  Future<void> _login() async {
    final base = await url;
    if (base.isEmpty) throw Exception('Add your Hermes address in Models & Links.');
    final pw = await _secure.read(key: 'asm_hermes_pw') ?? '';
    final r = await _c.post(Uri.parse('$base/api/auth/login'), headers: _headers(base), body: jsonEncode({'password': pw}))
        .timeout(const Duration(seconds: 20));
    _take(r);
    if (r.statusCode == 401) throw Exception('Hermes rejected the password.');
    if (r.statusCode >= 400) throw Exception('Hermes login failed (${r.statusCode}).');
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    final base = await url;
    if (_cookies.isEmpty) await _login();
    var r = await _c.post(Uri.parse('$base$path'), headers: _headers(base), body: jsonEncode(body)).timeout(const Duration(seconds: 60));
    if (r.statusCode == 401 || r.statusCode == 403) {
      _cookies.clear();
      await _login();
      r = await _c.post(Uri.parse('$base$path'), headers: _headers(base), body: jsonEncode(body)).timeout(const Duration(seconds: 60));
    }
    _take(r);
    return r;
  }

  /// Quick check for the Links screen.
  Future<String> test() async {
    final base = await url;
    final r = await _c.get(Uri.parse('$base/api/auth/status')).timeout(const Duration(seconds: 10));
    if (r.statusCode >= 400) return 'Reached ${Uri.parse(base).host} but it answered ${r.statusCode}.';
    await _login();
    final m = await models();
    return 'Connected to Hermes. ${m.length} models available.';
  }

  /// Every model Hermes can use (its /api/models/all list).
  Future<List<String>> models() async {
    final base = await url;
    if (_cookies.isEmpty) await _login();
    final r = await _c.get(Uri.parse('$base/api/models/all'), headers: _headers(base, json: false)).timeout(const Duration(seconds: 20));
    if (r.statusCode >= 400) return [];
    final d = jsonDecode(r.body);
    final out = <String>[];
    void walk(dynamic x) {
      if (x is Map) {
        final id = x['id'] ?? x['model'];
        if (id is String && id.isNotEmpty) out.add(id);
        x.values.forEach(walk);
      } else if (x is List) {
        x.forEach(walk);
      }
    }
    walk(d);
    return out.toSet().toList();
  }

  void newConversation() => _sessionId = null;

  /// Send a turn to Hermes and collect the streamed reply.
  Future<String> chat(String message, {void Function(String)? onDelta}) async {
    final base = await url;
    if (_sessionId == null) {
      final r = await _post('/api/session/new', {'title': 'Assimilis Mobile'});
      final d = jsonDecode(r.body);
      _sessionId = d['session']?['session_id'] ?? d['session_id'] ?? d['id'];
      if (_sessionId == null) throw Exception('Hermes did not start a session (${r.statusCode}).');
    }
    final m = await model;
    final start = await _post('/api/chat/start', {
      'session_id': _sessionId,
      'message': message,
      if (m.isNotEmpty) 'model': m,
    });
    if (start.statusCode >= 400) throw Exception('Hermes: ${start.body.length > 200 ? start.body.substring(0, 200) : start.body}');
    final sid = jsonDecode(start.body)['stream_id'];
    final req = http.Request('GET', Uri.parse('$base/api/chat/stream?stream_id=$sid'))..headers.addAll(_headers(base, json: false));
    final res = await _c.send(req).timeout(const Duration(seconds: 30));
    final out = StringBuffer();
    String event = 'message';
    await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter()).timeout(const Duration(minutes: 5))) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        final data = line.substring(5).trim();
        if (event == 'token') {
          try {
            final t = '${jsonDecode(data)['text'] ?? ''}';
            out.write(t);
            onDelta?.call(t);
          } catch (_) {}
        } else if (event == 'apperror') {
          throw Exception('Hermes: $data');
        } else if (event == 'done' || event == 'stream_end' || event == 'cancel') {
          break;
        }
      }
    }
    return out.toString().trim();
  }

  /// The core's own voice: Fish Audio if the server has a key, otherwise its Edge voice.
  Future<Uint8List?> speak(String text, {String persona = 'jarvis'}) async {
    final r = await _post('/api/world/voice', {'op': 'speak', 'text': text, 'engine': 'auto', 'persona': persona, 'prefer_fish': true});
    if (r.statusCode >= 400) return null;
    final d = jsonDecode(r.body);
    final b64 = d['audio_b64'] as String?;
    return b64 == null || b64.isEmpty ? null : base64Decode(b64);
  }
}
