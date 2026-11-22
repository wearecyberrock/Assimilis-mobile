import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'hes_engine.dart';

/// HES on the phone: the same data files and engine as the server, with events stored in
/// <app documents>/hes/hes.json. No server, no Gmail import.
class HesStore {
  HesStore._();
  static final HesStore instance = HesStore._();

  static const moduleFiles = [
    'abstain', 'ai_dependency', 'art', 'assignment', 'class_attendance', 'coding', 'combat_training', 'devotion',
    'grooming', 'hobby', 'integrity', 'memory_quiz', 'mood', 'plank', 'purpose_reflection', 'pushups', 'reading',
    'run', 'screen_time', 'self_defence_quiz', 'situps', 'sleep', 'social', 'spelling_quiz', 'squats', 'stretch',
    'study', 'vocabulary', 'wake', 'wealth', 'writing',
  ];
  static const defaultModules = [
    'pushups', 'situps', 'wake', 'study', 'reading', 'sleep', 'class_attendance', 'assignment', 'mood', 'coding',
  ];
  // Mission rewards from organelle/hes/missions.py.
  static const rewards = {'daily': (xp: 20, coins: 10), 'weekly': (xp: 100, coins: 50), 'side': (xp: 30, coins: 15)};

  HesData? data;
  Map<String, dynamic> _doc = {};
  File? _file;

  Future<HesData> load() async {
    if (data != null) return data!;
    final tree = jsonDecode(await rootBundle.loadString('assets/hes/tree.json'));
    final index = <String, Map<String, dynamic>>{};
    for (final b in tree['branches']) {
      for (final s in b['stats']) {
        index[s['id']] = {...Map<String, dynamic>.from(s), 'branch': b['id']};
      }
    }
    final classes = jsonDecode(await rootBundle.loadString('assets/hes/classes.json'));
    final abilitiesRaw = jsonDecode(await rootBundle.loadString('assets/hes/abilities.json'));
    final abilities = (abilitiesRaw is List ? abilitiesRaw : (abilitiesRaw['abilities'] as List))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final modules = <String, Map<String, dynamic>>{};
    for (final f in moduleFiles) {
      final m = Map<String, dynamic>.from(jsonDecode(await rootBundle.loadString('assets/hes/modules/$f.json')));
      modules[m['id']] = m;
    }
    data = HesData(index, List<Map<String, dynamic>>.from(tree['branches']), Map<String, dynamic>.from(classes),
        abilities, modules);
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/hes');
    await dir.create(recursive: true);
    _file = File('${dir.path}/hes.json');
    if (await _file!.exists()) {
      _doc = Map<String, dynamic>.from(jsonDecode(await _file!.readAsString()));
    }
    return data!;
  }

  Future<void> _save() async => _file!.writeAsString(jsonEncode(_doc));

  bool get onboarded => _doc['baseline'] != null;
  List<Map<String, dynamic>> get events => List<Map<String, dynamic>>.from(_doc['events'] ?? const []);
  List<String> get activeModules => List<String>.from(_doc['modules'] ?? defaultModules);
  Map<String, dynamic> get settings => Map<String, dynamic>.from(_doc['settings'] ?? const {});

  /// Start HES with starting stats (0–20 each; 10 if not given).
  Future<void> onboard({Map<String, double>? stats, List<String>? modules}) async {
    final d = await load();
    final assessed = d.defaultAssessed();
    _doc['baseline'] = {
      'start': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'assessed': assessed,
      'stats': {for (final s in assessed) s: clampD(stats?[s] ?? 10, 0, 20)},
    };
    _doc['modules'] = modules ?? defaultModules;
    _doc['events'] ??= [];
    await _save();
  }

  Future<void> setModules(List<String> ids) async {
    _doc['modules'] = ids;
    await _save();
  }

  Future<HesState> state() async {
    final d = await load();
    if (!onboarded) await onboard();
    return replay(d, Map<String, dynamic>.from(_doc['baseline']), events, settings, until: DateTime.now());
  }

  Future<Map<String, dynamic>> _add(Map<String, dynamic> e) async {
    final list = events
      ..add({
        'id': 'ev-${DateTime.now().microsecondsSinceEpoch}',
        'at': DateTime.now().millisecondsSinceEpoch / 1000,
        'status': 'applied',
        'source': 'you',
        ...e,
      });
    _doc['events'] = list;
    await _save();
    return list.last;
  }

  /// Log a tracked activity: module id + quantity (reps, minutes, pages, 1 for yes / 0 for a relapse).
  Future<String> log(String moduleId, double quantity, {String source = 'you', String? note}) async {
    final d = await load();
    final m = d.modules[moduleId];
    if (m == null) return 'No HES module called $moduleId.';
    final before = await state();
    await _add({'kind': 'log', 'module': moduleId, 'quantity': quantity, 'source': source, 'summary': note ?? m['name']});
    final after = await state();
    final unit = m['unit'] ?? '';
    final lvl = after.level > before.level ? ' Level up! You are now level ${after.level}.' : '';
    return 'Logged ${_num(quantity)} ${unit.isEmpty ? '' : '$unit '}of ${m['name']}.$lvl';
  }

  /// "did 30 pushups", "read 20 pages", "slept 7 hours", "studied 45 min". Null if nothing matched.
  Future<String?> quickLog(String text, {String source = 'you'}) async {
    final d = await load();
    final lower = text.toLowerCase();
    Map<String, dynamic>? best;
    var bestLen = 0;
    for (final m in d.modules.values) {
      final names = [m['id'], m['name'], ...(m['aliases'] as List? ?? const [])].map((e) => '$e'.toLowerCase());
      for (final a in names) {
        if (a.length > bestLen && RegExp('(^|[^a-z])${RegExp.escape(a)}').hasMatch(lower)) {
          best = m;
          bestLen = a.length;
        }
      }
    }
    if (best == null) return null;
    final n = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(lower);
    var q = n != null ? double.parse(n.group(1)!) : 1.0;
    final kind = best['kind'];
    if ((kind == 'boolean' || kind == 'abstain_streak') &&
        RegExp(r"\b(relapse|failed|slipped|broke|didn't|did not)\b").hasMatch(lower)) {
      q = 0;
    }
    if (lower.contains('hour') && '${best['unit']}'.startsWith('min')) q *= 60;
    return log(best['id'], q, source: source, note: text);
  }

  /// Today's daily quests for the active modules: (module, title, target, done so far, claimed).
  Future<List<Map<String, dynamic>>> quests() async {
    final d = await load();
    final today = dayOf(DateTime.now());
    final out = <Map<String, dynamic>>[];
    for (final id in activeModules) {
      final m = d.modules[id];
      if (m == null) continue;
      var missions = (m['missions'] as List? ?? const []).where((ms) => ms['type'] == 'daily').toList();
      if (missions.isEmpty && m['goal'] != null) {
        // Modules without a daily mission get one from their goal.
        final unit = '${m['unit'] ?? ''}';
        missions = [
          {'type': 'daily', 'key': id, 'title': '${m['name']}: {target}${unit.isEmpty ? '' : ' $unit'}', 'unit': unit}
        ];
      } else if (missions.isEmpty && (m['kind'] == 'boolean' || m['kind'] == 'checkin')) {
        missions = [
          {'type': 'daily', 'key': id, 'title': m['kind'] == 'checkin' ? 'Check in: ${m['name']}' : '${m['name']} today', 'unit': ''}
        ];
      }
      for (final ms in missions) {
        final target = ((ms['overload']?['default'] ?? m['goal'] ?? 1) as num).toDouble();
        final done = events
            .where((e) =>
                e['status'] == 'applied' &&
                e['module'] == id &&
                dayOf(DateTime.fromMillisecondsSinceEpoch(((e['at'] as num) * 1000).toInt())) == today)
            .fold<double>(0, (a, e) => a + ((e['quantity'] ?? 0) as num).toDouble());
        final key = '${ms['key']}@${today.toIso8601String()}';
        final claimed = events.any((e) => e['kind'] == 'mission' && e['data']?['key'] == key && e['status'] == 'applied');
        out.add({
          'module': id,
          'key': key,
          'title': _fill('${ms['title']}', target),
          'target': target,
          'done': done,
          'claimed': claimed,
          'unit': ms['unit'] ?? m['unit'] ?? '',
        });
      }
    }
    return out;
  }

  Future<String> claim(Map<String, dynamic> quest) async {
    if (quest['claimed'] == true) return 'Already claimed.';
    if ((quest['done'] as double) < (quest['target'] as double)) {
      return 'Not done yet: ${_num(quest['done'])} of ${_num(quest['target'])}.';
    }
    final r = rewards['daily']!;
    await _add({
      'kind': 'mission',
      'summary': 'Quest: ${quest['title']}',
      'data': {'key': quest['key'], 'xp': r.xp, 'coins': r.coins},
    });
    return 'Quest complete: ${quest['title']}. +${r.xp} XP, +${r.coins} coins.';
  }

  Future<String> undo(String eventId) async {
    final list = events;
    for (final e in list) {
      if (e['id'] == eventId) e['status'] = 'undone';
    }
    _doc['events'] = list;
    await _save();
    return 'Undone.';
  }

  /// Spoken/typed status line, like `hes status` on the server.
  Future<String> status() async {
    final s = await state();
    final q = await quests();
    final open = q.where((e) => e['claimed'] != true).length;
    return 'Level ${s.level}, rank ${s.rankName}, ${s.className}. Power ${s.powerValue}, '
        '${s.xp} of ${s.xpNext} XP to the next level, ${s.coins} coins. $open quest${open == 1 ? '' : 's'} open today.';
  }

  /// Fill quest title placeholders: {target}, {time} (wake time setting), anything else removed.
  String _fill(String title, double target) => title
      .replaceAll('{target}', _num(target))
      .replaceAll('{time}', '${settings['wake_time'] ?? '06:30'}')
      .replaceAll(RegExp(r'{[a-z_]+}'), '')
      .replaceAll(RegExp(r's+'), ' ')
      .trim();

  Future<void> setSetting(String key, Object value) async {
    _doc['settings'] = {...settings, key: value};
    await _save();
  }

  // ---- Abilities and titles (abilities.json)
  List<Map<String, dynamic>> get abilityDefs => data?.abilities ?? const [];

  /// How many claimed quests match a mission key ("wake" matches "wake@2026-11-22").
  int _missionCount(String key) => events
      .where((e) => e['kind'] == 'mission' && e['status'] == 'applied')
      .where((e) => '${e['data']?['key'] ?? ''}'.split('@').first == key.split('@').first)
      .length;

  /// Whether requirements are met: {level: n}, {missions: {key: n}}, {streak: {module: days}}.
  bool meets(Map? req, HesState s) {
    if (req == null || req.isEmpty) return true;
    if (req['level'] is num && s.level < (req['level'] as num)) return false;
    final missions = req['missions'] as Map?;
    if (missions != null) {
      for (final e in missions.entries) {
        if (_missionCount('${e.key}') < (e.value as num)) return false;
      }
    }
    final streaks = req['streak'] as Map?;
    if (streaks != null) {
      for (final e in streaks.entries) {
        final pattern = '${e.key}'.replaceAll('*', '');
        final best = (data?.modules.keys ?? const <String>[])
            .where((m) => m.startsWith(pattern))
            .map((m) => streak(events, m).$2)
            .fold<int>(0, (a, b) => a > b ? a : b);
        if (best < (e.value as num)) return false;
      }
    }
    return true;
  }

  Future<String> unlock(Map<String, dynamic> ability) async {
    final s = await state();
    if (s.unlocked.contains(ability['id'])) return 'Already unlocked.';
    if (!meets(ability['requires'] as Map?, s)) return 'Not yet: ${ability['requires_text'] ?? 'requirements not met'}.';
    final cost = ((ability['cost_ap'] ?? 1) as num).toInt();
    if (s.ap < cost) return 'You need $cost AP (you have ${s.ap}).';
    await _add({'kind': 'ability', 'summary': 'Ability: ${ability['name']}', 'data': {'ability': ability['id']}});
    return 'Unlocked ${ability['name']}.';
  }

  /// Current title: the last title in abilities.json whose requirements are met.
  Future<String> title() async {
    final s = await state();
    var t = 'Novice';
    final raw = jsonDecode(await rootBundle.loadString('assets/hes/abilities.json'));
    for (final x in (raw['titles'] as List? ?? const [])) {
      if (meets(x['requires'] as Map?, s)) t = '${x['name']}';
    }
    return t;
  }

  static String _num(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
