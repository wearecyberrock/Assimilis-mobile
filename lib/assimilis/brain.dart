import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../services/inference_service.dart';
import 'a2a/a2a.dart';
import 'links/chatgpt_auth.dart';
import 'links/hermes_link.dart';
import 'settings.dart';
import 'tools.dart';

/// One message in a Jarvis conversation.
class BrainMessage {
  final String role; // user | assistant | tool
  final String content;
  final List<String> toolsUsed;
  BrainMessage(this.role, this.content, {this.toolsUsed = const []});
}

/// The Assimilis brain behind Jarvis and voice mode.
/// * Cloud: any OpenAI-compatible endpoint with tool calling (OpenRouter by default).
/// * Offline: the GGUF model loaded in Chat & Models (no tools, plain answers).
class AssimilisBrain {
  AssimilisBrain._() {
    // Other devices (A2A) can ask this A; a request that already hopped is never passed on again.
    A2a.askHandler = (text, {bool allowOffload = true}) async => (await ask(text, allowOffload: allowOffload)).content;
    A2a.phoneTaskHandler = (task) => AssimilisTools.run('phone_task', {'task': task});
  }
  static final AssimilisBrain instance = AssimilisBrain._();

  final List<Map<String, dynamic>> _history = [];
  void reset() => _history.clear();

  String _system() {
    final now = DateTime.now();
    final who = AssimilisSettings.cachedName.isEmpty ? '' : ' The owner\x27s name is ${AssimilisSettings.cachedName}.';
    return '''You are Assimilis, "A" for short, the owner's assistant on their Android phone.$who Speak calmly and
clearly, like a capable British engineer: short sentences, no filler. Replies are read aloud, so keep
them under 3 sentences unless asked for detail, and never read out code or long URLs.
The current local date and time is ${now.toIso8601String()} (${_weekday(now.weekday)}).
You can act through tools: alarms, timers and reminders; Canvas notes and maths; HES stats and
quests; Agent Reach web/GitHub/YouTube/Reddit/RSS reading;
and phone_task, which operates the phone's screen for multi-step jobs in other apps.
Use a tool whenever it helps; then answer from its result. Resolve relative times ("tomorrow at 7")
into ISO 8601 local time yourself.''';
  }

  static String _weekday(int d) =>
      const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d - 1];

  /// Which brain answered last (shown under replies).
  String lastBrain = '';

  /// Ask A. Brain order in "auto": your Hermes, ChatGPT sign-in, API key (with tools), local model.
  Future<BrainMessage> ask(String text, {void Function(String)? onStatus, bool allowOffload = true}) async {
    final s = await AssimilisSettings.get();
    final mode = s.blob('brain') ?? 'auto';
    final hasKey = (await s.apiKey()).isNotEmpty;
    final order = switch (mode) {
      'hermes' => ['hermes'],
      'chatgpt' => ['chatgpt'],
      'api' => ['api'],
      'local' => ['local'],
      _ => [
          if (await HermesLink.instance.configured) 'hermes',
          if (await ChatGptAuth.instance.signedIn) 'chatgpt',
          if (hasKey) 'api',
          if (!_localReady && allowOffload) 'device',
          'local',
        ],
    };
    Object? lastError;
    for (final b in order) {
      try {
        lastBrain = b;
        switch (b) {
          case 'hermes':
            final quick = await AssimilisTools.offlineIntent(text);
            if (quick != null) return BrainMessage('assistant', quick, toolsUsed: const ['on phone']);
            onStatus?.call('Asking your Hermes…');
            final r = await HermesLink.instance.chat(text);
            return BrainMessage('assistant', r.isEmpty ? 'Done.' : r, toolsUsed: const ['hermes']);
          case 'chatgpt':
            final quick = await AssimilisTools.offlineIntent(text);
            if (quick != null) return BrainMessage('assistant', quick, toolsUsed: const ['on phone']);
            _history.add({'role': 'user', 'content': text});
            final hist = [
              for (final m in _history.where((m) => (m['role'] == 'user' || m['role'] == 'assistant') && m['content'] is String))
                {'role': '${m['role']}', 'content': '${m['content']}'}
            ];
            final r = await ChatGptAuth.instance.chat(hist, system: _system(), model: s.blob('chatgpt_model') ?? ChatGptAuth.models.first);
            _history.add({'role': 'assistant', 'content': r});
            return BrainMessage('assistant', r.isEmpty ? 'Done.' : r, toolsUsed: const ['chatgpt']);
          case 'api':
            return await _askApi(text, onStatus: onStatus);
          case 'device':
            // No brain here: pass the question to the strongest nearby Assimilis (A2A).
            final peer = await A2a.instance.best();
            if (peer == null || !(peer.hasBrain || peer.hasModel)) throw Exception('no device with a brain nearby');
            onStatus?.call('Asking ${peer.name}…');
            final r = await A2a.instance.send(peer, text, skill: peer.hasBrain ? 'ask' : 'generate');
            return BrainMessage('assistant', r, toolsUsed: ['via ${peer.name}']);
          default:
            return await _local(text);
        }
      } catch (e) {
        lastError = e;
        if (_history.isNotEmpty && _history.last['role'] == 'user') _history.removeLast();
      }
    }
    return BrainMessage('assistant', 'I could not reach any brain: $lastError');
  }

  bool get _localReady => Get.isRegistered<InferenceService>() && Get.find<InferenceService>().isModelLoaded.value;

  Future<BrainMessage> _askApi(String text, {void Function(String)? onStatus}) async {
    final s = await AssimilisSettings.get();
    final key = await s.apiKey();
    _history.add({'role': 'user', 'content': text});
    if (_history.length > 30) _history.removeRange(0, _history.length - 30);

    if (key.isEmpty && !s.baseUrl.contains('192.168.') && !s.baseUrl.contains('localhost')) {
      return _local(text);
    }

    final used = <String>[];
    for (var round = 0; round < 6; round++) {
      final res = await http
          .post(
            Uri.parse('${s.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              if (key.isNotEmpty) 'Authorization': 'Bearer $key',
              'X-Title': 'Assimilis Mobile',
            },
            body: jsonEncode({
              'model': s.model,
              'messages': [
                {'role': 'system', 'content': _system()},
                ..._history,
              ],
              'tools': AssimilisTools.schemas,
              'tool_choice': 'auto',
            }),
          )
          .timeout(const Duration(seconds: 90));
      if (res.statusCode >= 400) {
        _history.removeLast();
        // Some free models refuse tools: retry once without them.
        if (round == 0 && res.body.contains('tool')) return _noTools(text, s, key);
        return BrainMessage('assistant', 'The model returned ${res.statusCode}: ${_short(res.body)}');
      }
      final msg = (jsonDecode(res.body)['choices'][0]['message']) as Map<String, dynamic>;
      final calls = (msg['tool_calls'] as List?) ?? const [];
      if (calls.isEmpty) {
        final answer = '${msg['content'] ?? ''}'.trim();
        _history.add({'role': 'assistant', 'content': answer});
        return BrainMessage('assistant', answer.isEmpty ? 'Done.' : answer, toolsUsed: used);
      }
      _history.add({'role': 'assistant', 'content': msg['content'] ?? '', 'tool_calls': calls});
      for (final c in calls) {
        final name = c['function']['name'] as String;
        Map<String, dynamic> args;
        try {
          args = Map<String, dynamic>.from(jsonDecode(c['function']['arguments'] ?? '{}'));
        } catch (_) {
          args = {};
        }
        onStatus?.call(AssimilisTools.statusFor(name));
        used.add(name);
        final out = await AssimilisTools.run(name, args);
        _history.add({'role': 'tool', 'tool_call_id': c['id'], 'content': out});
      }
    }
    return BrainMessage('assistant', 'I ran several steps; check the results above.', toolsUsed: used);
  }

  Future<BrainMessage> _noTools(String text, AssimilisSettings s, String key) async {
    _history.add({'role': 'user', 'content': text});
    final res = await http.post(
      Uri.parse('${s.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions'),
      headers: {'Content-Type': 'application/json', if (key.isNotEmpty) 'Authorization': 'Bearer $key'},
      body: jsonEncode({
        'model': s.model,
        'messages': [
          {'role': 'system', 'content': _system()},
          ..._history.where((m) => m['role'] != 'tool' && m['tool_calls'] == null),
        ],
      }),
    );
    if (res.statusCode >= 400) return BrainMessage('assistant', 'The model returned ${res.statusCode}: ${_short(res.body)}');
    final answer = '${jsonDecode(res.body)['choices'][0]['message']['content'] ?? ''}'.trim();
    _history.add({'role': 'assistant', 'content': answer});
    return BrainMessage('assistant', answer);
  }

  /// Offline: the local GGUF model from Chat & Models.
  Future<BrainMessage> _local(String text) async {
    if (!Get.isRegistered<InferenceService>() || !Get.find<InferenceService>().isModelLoaded.value) {
      _history.removeLast();
      return BrainMessage('assistant',
          'I need a brain first. Add an API key in Jarvis settings, or load a local model in Chat and Models.');
    }
    // Simple intents still work offline without tool calling.
    final quick = await AssimilisTools.offlineIntent(text);
    if (quick != null) {
      _history.add({'role': 'assistant', 'content': quick});
      return BrainMessage('assistant', quick, toolsUsed: const ['offline']);
    }
    final hist = _history
        .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
        .map((m) => {'role': '${m['role']}', 'content': '${m['content']}'})
        .toList();
    final answer = await Get.find<InferenceService>().generate(
      prompt: text,
      systemPrompt: _system(),
      conversationHistory: hist.length > 1 ? hist.sublist(0, hist.length - 1) : null,
      source: 'jarvis',
      maxTokens: 400,
    );
    _history.add({'role': 'assistant', 'content': answer});
    return BrainMessage('assistant', answer.trim());
  }

  static String _short(String s) => s.length > 300 ? '${s.substring(0, 300)}…' : s;
}
