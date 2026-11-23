import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../../controllers/server_controller.dart';
import '../../core/constants.dart';
import '../../services/hive_service.dart';
import '../../services/inference_service.dart';
import 'chatgpt_auth.dart';
import 'hermes_link.dart';
import 'shared_providers.dart';

/// One OpenAI-compatible endpoint on this phone (http://127.0.0.1:8790/v1) that every agent can point at, so any
/// model or key in Settings can be shared with any agent:
///
///   local/<name>        the downloaded model loaded in Chat & Models (served by its local server on :8080)
///   chatgpt/<model>     your ChatGPT subscription (device-code sign-in)
///   hermes/<model>      your Assimilis / Hermes on the laptop or VPS
///   <provider>/<model>  a shared API key (openrouter, openai, anthropic, gemini, deepseek, groq)
///
/// It only listens on loopback and needs its own token, so other apps on the phone cannot use your keys.
class ModelGateway {
  ModelGateway._();
  static final ModelGateway instance = ModelGateway._();

  static const port = 8790;
  static const baseUrl = 'http://127.0.0.1:$port/v1';
  static const _secure = FlutterSecureStorage();
  static const _tokenKey = 'asm_gateway_token';

  HttpServer? _server;
  String? _token;
  final _client = http.Client();

  bool get running => _server != null;

  /// The key agents use to call the gateway (made once, kept in the keystore).
  Future<String> token() async {
    if (_token != null) return _token!;
    var t = await _secure.read(key: _tokenKey);
    if (t == null || t.isEmpty) {
      final r = Random.secure();
      t = 'asm_${List.generate(24, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      await _secure.write(key: _tokenKey, value: t);
    }
    return _token = t;
  }

  Future<void> start() async {
    if (_server != null) return;
    await token();
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: true);
    } on SocketException {
      return; // already served (another isolate) or the port is busy; agents will see the error on use
    }
    unawaited(_server!.forEach((r) => unawaited(_handle(r))));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ── routing ─────────────────────────────────────────────────────────────────────────────────────

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path.replaceAll(RegExp(r'/+$'), '');
      if (path == '/health') return await _json(req, {'status': 'ok'});
      if (req.headers.value(HttpHeaders.authorizationHeader)?.trim() != 'Bearer ${await token()}') {
        return await _json(req, {'error': {'message': 'Wrong Assimilis gateway key.'}}, status: 401);
      }
      if (req.method == 'GET' && path == '/v1/models') {
        final ids = await models();
        return await _json(req, {
          'object': 'list',
          'data': [for (final id in ids) {'id': id, 'object': 'model', 'owned_by': id.split('/').first}],
        });
      }
      if (req.method == 'POST' && path == '/v1/chat/completions') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        return await _chat(req, body);
      }
      return await _json(req, {'error': {'message': 'Not found'}}, status: 404);
    } catch (e) {
      try {
        await _json(req, {'error': {'message': '$e'}}, status: 502);
      } catch (_) {}
    }
  }

  /// Every model the gateway can serve right now, as `<source>/<model>`.
  Future<List<String>> models() async {
    final out = <String>[];
    final inf = Get.isRegistered<InferenceService>() ? Get.find<InferenceService>() : null;
    if (inf != null && inf.isModelLoaded.value) out.add('local/${inf.loadedModelName.value}');
    final last = Get.isRegistered<HiveService>() ? Get.find<HiveService>().getSetting<String>(AppConstants.keyLocalModelName) : null;
    if (last != null && last.isNotEmpty && !out.contains('local/$last')) out.add('local/$last');
    if (await ChatGptAuth.instance.signedIn) out.addAll(ChatGptAuth.models.map((m) => 'chatgpt/$m'));
    if (await HermesLink.instance.configured) {
      final hm = await HermesLink.instance.model;
      out.add('hermes/${hm.isEmpty ? 'default' : hm}');
    }
    final keys = await SharedProviders.load();
    for (final p in SharedProviders.all) {
      final k = keys[p.id];
      if ((k?['key'] ?? '').isEmpty) continue;
      out.add('${p.id}/${(k?['model'] ?? '').isNotEmpty ? k!['model'] : p.defaultModel}');
    }
    return out;
  }

  Future<void> _chat(HttpRequest req, Map<String, dynamic> body) async {
    final id = '${body['model'] ?? ''}';
    final slash = id.indexOf('/');
    final source = slash < 0 ? id : id.substring(0, slash);
    final model = slash < 0 ? '' : id.substring(slash + 1);
    final stream = body['stream'] == true;
    final messages = [for (final m in (body['messages'] as List? ?? const [])) Map<String, dynamic>.from(m as Map)];

    switch (source) {
      case 'local':
        final local = await _ensureLocal(model);
        return _forward(req, Uri.parse('$local/v1/chat/completions'), {...body, 'model': Get.find<InferenceService>().loadedModelName.value},
            key: Get.find<ServerController>().apiKey.value);
      case 'chatgpt':
        return _synth(req, id, stream, (onDelta) => ChatGptAuth.instance.chat(_flatMessages(messages), model: model.isEmpty ? ChatGptAuth.models.first : model, onDelta: onDelta));
      case 'hermes':
        return _synth(req, id, stream,
            (onDelta) => HermesLink.instance.chat(_transcript(messages), onDelta: onDelta, fresh: true, modelOverride: model == 'default' ? null : model));
      default:
        final p = SharedProviders.all.where((x) => x.id == source).firstOrNull;
        if (p == null) {
          return _json(req, {'error': {'message': 'Unknown model "$id". Use one of: ${(await models()).join(', ')}'}}, status: 404);
        }
        final key = (await SharedProviders.load())[p.id]?['key'] ?? '';
        if (key.isEmpty) return _json(req, {'error': {'message': 'No ${p.label} key saved in Settings.'}}, status: 401);
        return _forward(req, Uri.parse('${p.baseUrl}/chat/completions'), {...body, 'model': model.isEmpty ? p.defaultModel : model}, key: key);
    }
  }

  /// Makes sure a local model is loaded and Chat & Models' local server is running; returns its base URL.
  Future<String> _ensureLocal(String wanted) async {
    if (!Get.isRegistered<InferenceService>() || !Get.isRegistered<ServerController>()) {
      throw Exception('Local models are not available on this device.');
    }
    final inf = Get.find<InferenceService>();
    if (!inf.isModelLoaded.value) {
      final hive = Get.find<HiveService>();
      final path = hive.getSetting<String>(AppConstants.keyLocalModelPath) ?? '';
      if (path.isEmpty) throw Exception('No local model loaded. Load one in Settings → Models & keys.');
      final r = await inf.loadModel(path,
          modelName: hive.getSetting<String>(AppConstants.keyLocalModelName),
          modelRuntime: hive.getSetting<String>(AppConstants.keyLocalModelRuntime));
      if (r.startsWith('ERROR')) throw Exception(r);
    }
    final srv = Get.find<ServerController>();
    if (!srv.isRunning.value) await srv.startServer();
    if (!srv.isRunning.value) throw Exception(srv.lastError.value ?? 'The local model server did not start.');
    return 'http://127.0.0.1:${ServerController.port}';
  }

  /// Passes the request straight through (keeps tools, images and streaming).
  Future<void> _forward(HttpRequest req, Uri url, Map<String, dynamic> body, {String key = ''}) async {
    final out = http.Request('POST', url)
      ..headers.addAll({
        'Content-Type': 'application/json',
        if (key.isNotEmpty) 'Authorization': 'Bearer $key',
        if (url.host.contains('openrouter')) 'HTTP-Referer': 'https://elevedenbot.tech',
        if (url.host.contains('openrouter')) 'X-Title': 'Assimilis',
      })
      ..body = jsonEncode(body);
    final res = await _client.send(out).timeout(const Duration(minutes: 5));
    req.response.statusCode = res.statusCode;
    req.response.headers.set(HttpHeaders.contentTypeHeader, res.headers['content-type'] ?? 'application/json');
    await req.response.addStream(res.stream);
    await req.response.close();
  }

  /// Answers in OpenAI's format for sources that are not OpenAI-compatible (ChatGPT sign-in, Hermes).
  Future<void> _synth(HttpRequest req, String model, bool stream, Future<String> Function(void Function(String) onDelta) run) async {
    final id = 'chatcmpl-${DateTime.now().microsecondsSinceEpoch}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (!stream) {
      final text = await run((_) {});
      return _json(req, {
        'id': id,
        'object': 'chat.completion',
        'created': created,
        'model': model,
        'choices': [
          {'index': 0, 'message': {'role': 'assistant', 'content': text}, 'finish_reason': 'stop'}
        ],
      });
    }
    req.response.headers.set(HttpHeaders.contentTypeHeader, 'text/event-stream');
    req.response.bufferOutput = false;
    void chunk(Map<String, dynamic> delta, [String? finish]) => req.response.write('data: ${jsonEncode({
          'id': id,
          'object': 'chat.completion.chunk',
          'created': created,
          'model': model,
          'choices': [
            {'index': 0, 'delta': delta, 'finish_reason': finish}
          ],
        })}\n\n');
    chunk({'role': 'assistant', 'content': ''});
    try {
      await run((d) => chunk({'content': d}));
      chunk({}, 'stop');
    } catch (e) {
      chunk({'content': '\n[error] $e'}, 'stop');
    }
    req.response.write('data: [DONE]\n\n');
    await req.response.close();
  }

  static String _text(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      return content.map((p) => p is Map ? (p['text'] ?? (p['type'] == 'image_url' ? '[image]' : '')) : '$p').join('\n');
    }
    return content == null ? '' : '$content';
  }

  static List<Map<String, String>> _flatMessages(List<Map<String, dynamic>> m) => [
        for (final x in m)
          {
            'role': x['role'] == 'tool' ? 'user' : '${x['role']}',
            'content': x['role'] == 'tool' ? 'Tool result: ${_text(x['content'])}' : _text(x['content']),
          }
      ];

  static String _transcript(List<Map<String, dynamic>> m) {
    if (m.length == 1) return _text(m.first['content']);
    return [for (final x in m) '${'${x['role']}'.toUpperCase()}: ${_text(x['content'])}'].join('\n\n');
  }

  static Future<void> _json(HttpRequest req, Object body, {int status = 200}) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }
}
