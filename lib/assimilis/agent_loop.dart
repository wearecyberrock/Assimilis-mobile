import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where a brain answers: an OpenAI-compatible base URL, a model id and a key. The model gateway makes every
/// source (local, ChatGPT, Hermes, shared keys) look like this.
typedef Endpoint = ({String base, String model, String key});

/// Result of one agent run.
class LoopResult {
  final String text;
  final List<String> toolsUsed;
  final List<Map<String, dynamic>> messages;
  const LoopResult(this.text, this.toolsUsed, this.messages);
}

/// A plain tool-calling loop on any OpenAI-compatible endpoint: ask, run the tools it calls, feed the results back,
/// until it answers. Used by the HES System and team tasks.
class AgentLoop {
  static Future<LoopResult> run(
    Endpoint ep,
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>> tools = const [],
    required Future<String> Function(String name, Map<String, dynamic> args) runTool,
    int maxRounds = 8,
    void Function(String name)? onTool,
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    final msgs = [...messages];
    final used = <String>[];
    try {
      for (var round = 0; round < maxRounds; round++) {
        final res = await c
            .post(Uri.parse('${ep.base.replaceAll(RegExp(r'/+$'), '')}/chat/completions'),
                headers: {
                  'Content-Type': 'application/json',
                  if (ep.key.isNotEmpty) 'Authorization': 'Bearer ${ep.key}',
                  'X-Title': 'Assimilis',
                },
                body: jsonEncode({
                  'model': ep.model,
                  'messages': msgs,
                  if (tools.isNotEmpty) 'tools': tools,
                  if (tools.isNotEmpty) 'tool_choice': 'auto',
                }))
            .timeout(const Duration(seconds: 120));
        if (res.statusCode >= 400) {
          throw Exception('The model returned ${res.statusCode}: ${res.body.length > 240 ? res.body.substring(0, 240) : res.body}');
        }
        final msg = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes))['choices'][0]['message'] as Map);
        final calls = (msg['tool_calls'] as List?) ?? const [];
        if (calls.isEmpty) {
          final text = '${msg['content'] ?? ''}'.trim();
          msgs.add({'role': 'assistant', 'content': text});
          return LoopResult(text, used, msgs);
        }
        msgs.add({'role': 'assistant', 'content': msg['content'] ?? '', 'tool_calls': calls});
        for (final call in calls) {
          final f = (call as Map)['function'] as Map;
          final name = '${f['name']}';
          Map<String, dynamic> args;
          try {
            args = Map<String, dynamic>.from(jsonDecode('${f['arguments'] ?? '{}'}') as Map);
          } catch (_) {
            args = {};
          }
          onTool?.call(name);
          used.add(name);
          String out;
          try {
            out = await runTool(name, args);
          } catch (e) {
            out = 'Error: $e';
          }
          msgs.add({'role': 'tool', 'tool_call_id': '${call['id']}', 'content': out});
        }
      }
      return LoopResult('I ran several steps; see what changed.', used, msgs);
    } finally {
      if (client == null) c.close();
    }
  }
}
