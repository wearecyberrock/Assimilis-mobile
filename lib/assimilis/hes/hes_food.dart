import 'dart:convert';
import 'dart:io';

import '../agent_loop.dart';
import '../links/agent_models.dart';
import 'hes_store.dart';
import 'hes_system.dart';
import 'phone_signals.dart';

/// Food: a photo (or a description) of a meal → calories and macros from the HES brain (any vision model in
/// Settings, the ChatGPT subscription included), logged in HES and written to Health Connect.
class HesFood {
  static const _ask = '''You estimate food for a nutrition log. Look at the meal and answer ONLY with JSON:
{"name": "short meal name", "items": [{"name": "...", "grams": 0, "kcal": 0, "protein": 0, "carbs": 0, "fat": 0}],
 "total": {"kcal": 0, "protein": 0, "carbs": 0, "fat": 0}, "confidence": "low|medium|high", "note": "one short tip"}
Use typical portion sizes when unsure (Caribbean and international dishes included). Numbers only, grams for macros.''';

  /// Estimates a meal from an image file and/or a description.
  static Future<Map<String, dynamic>> estimate({File? photo, String description = '', Endpoint? endpoint}) async {
    final ep = endpoint ?? await AgentModels.endpointFor('hes');
    if (ep == null) throw Exception('Pick a model for HES in Settings → Models & keys (it needs to see images for photos).');
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': description.isEmpty ? 'Estimate this meal.' : 'Estimate this meal: $description'},
      if (photo != null)
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(await photo.readAsBytes())}'}
        },
    ];
    final r = await AgentLoop.run(ep, [
      {'role': 'system', 'content': _ask},
      {'role': 'user', 'content': content},
    ], runTool: (_, __) async => '', maxRounds: 1);
    return parse(r.text);
  }

  /// Pulls the JSON out of a model reply (it may wrap it in a code fence or prose).
  static Map<String, dynamic> parse(String text) {
    final s = text.indexOf('{'), e = text.lastIndexOf('}');
    if (s < 0 || e <= s) throw Exception('The model did not return a food estimate.');
    final m = Map<String, dynamic>.from(jsonDecode(text.substring(s, e + 1)) as Map);
    final t = Map<String, dynamic>.from(m['total'] as Map? ?? const {});
    if (t['kcal'] == null && m['items'] is List) {
      double sum(String k) => (m['items'] as List).fold<double>(0, (a, i) => a + (((i as Map)[k] ?? 0) as num).toDouble());
      m['total'] = {'kcal': sum('kcal'), 'protein': sum('protein'), 'carbs': sum('carbs'), 'fat': sum('fat')};
    }
    return m;
  }

  /// Logs an estimate: a HES meal event, today's totals, Health Connect, and a System window.
  static Future<String> log(Map<String, dynamic> meal, {String source = 'you'}) async {
    final t = Map<String, dynamic>.from(meal['total'] as Map? ?? const {});
    double n(String k) => ((t[k] ?? 0) as num).toDouble();
    await HesStore.instance.load();
    await HesStore.instance.addEvent({
      'kind': 'meal',
      'source': source,
      'summary': 'Meal: ${meal['name'] ?? 'food'} (${n('kcal').round()} kcal)',
      'data': {'meal': meal},
    });
    final today = await todayTotals();
    final hc = await PhoneSignals.instance.writeMeal('${meal['name'] ?? 'Meal'}', kcal: n('kcal'), protein: n('protein'), carbs: n('carbs'), fat: n('fat'));
    final line = '${meal['name'] ?? 'Meal'}: ${n('kcal').round()} kcal · P ${n('protein').round()} g · C ${n('carbs').round()} g · F ${n('fat').round()} g';
    await HesSystem.instance.post('[NUTRITION] $line\nToday: ${today['kcal']!.round()} kcal, ${today['protein']!.round()} g protein.'
        '${meal['note'] == null ? '' : '\n${meal['note']}'}', kind: 'info', silent: true);
    return '$line. Today so far: ${today['kcal']!.round()} kcal.${hc ? ' Saved to Health Connect.' : ''}';
  }

  static Future<Map<String, double>> todayTotals() async {
    await HesStore.instance.load();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch / 1000;
    final out = {'kcal': 0.0, 'protein': 0.0, 'carbs': 0.0, 'fat': 0.0};
    for (final e in HesStore.instance.events) {
      if (e['kind'] != 'meal' || e['status'] != 'applied' || (e['at'] as num) < start) continue;
      final t = ((e['data'] as Map?)?['meal'] as Map?)?['total'] as Map? ?? const {};
      for (final k in out.keys.toList()) {
        out[k] = out[k]! + ((t[k] ?? 0) as num).toDouble();
      }
    }
    return out;
  }

  // Tool for agents: log food from a description (photos come through the HES screen or a chat image).
  static final schemas = [
    {
      'type': 'function',
      'function': {
        'name': 'hes_food_log',
        'description': 'Log a meal from a description ("rice and peas with stew chicken, medium plate"): estimates calories and macros, '
            'logs it in HES and Health Connect. Pass kcal/protein/carbs/fat if you already know them.',
        'parameters': {
          'type': 'object',
          'properties': {
            'description': {'type': 'string'},
            'kcal': {'type': 'number'},
            'protein': {'type': 'number'},
            'carbs': {'type': 'number'},
            'fat': {'type': 'number'},
          },
          'required': ['description'],
        },
      },
    },
    {
      'type': 'function',
      'function': {'name': 'hes_food_today', 'description': 'Calories and macros eaten today.', 'parameters': {'type': 'object', 'properties': {}}},
    },
  ];

  static Future<String> runTool(String name, Map<String, dynamic> a) async {
    if (name == 'hes_food_today') return jsonEncode(await todayTotals());
    final meal = a['kcal'] != null
        ? {
            'name': '${a['description']}',
            'total': {'kcal': a['kcal'], 'protein': a['protein'] ?? 0, 'carbs': a['carbs'] ?? 0, 'fat': a['fat'] ?? 0},
          }
        : await estimate(description: '${a['description']}');
    return log(meal, source: 'agent');
  }

  static void install() => HesSystem.plugins['food'] = (schemas, runTool);
}
