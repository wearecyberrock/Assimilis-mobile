import 'dart:convert';

import '../agent_loop.dart';
import '../links/agent_models.dart';
import '../reminders.dart';
import 'hes_store.dart';

/// The HES "System": the voice and the rules of a manhwa System window, run by an AI brain (any model in Settings,
/// including the ChatGPT subscription). It has no fixed modes: it reads your profile, your logs and your phone's
/// signals, and adapts — workouts, study, sleep, anything — by issuing quests, tips, questions and story.
///
/// Everything it does goes through tools, so A and every other agent can drive HES the same way.
class HesSystem {
  HesSystem._();
  static final HesSystem instance = HesSystem._();
  HesStore get _h => HesStore.instance;

  /// Quest types and their default rewards (xp, coins) and penalties (xp, coins) when failed.
  static const types = {
    'daily': (xp: 20, coins: 10, pxp: 10, pcoins: 5),
    'side': (xp: 30, coins: 15, pxp: 0, pcoins: 0),
    'urgent': (xp: 50, coins: 25, pxp: 25, pcoins: 10),
    'hidden': (xp: 80, coins: 40, pxp: 0, pcoins: 0),
    'penalty': (xp: 15, coins: 0, pxp: 30, pcoins: 15),
    'reminder': (xp: 5, coins: 2, pxp: 0, pcoins: 0),
  };

  /// Things that are quests when set as reminders (wake-up, study, training…); everything else is a plain reminder
  /// that still pays a little when you mark it done.
  static final questWords = RegExp(
      r'\b(wake|up at|study|revise|revision|practi[cs]e|train|gym|workout|exercise|run|jog|read|pushups?|situps?|squats?|stretch|meditat|pray|code|coding|write|writing|sleep|bed)\b',
      caseSensitive: false);

  // ── storage helpers ───────────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _list(String key) async {
    await _h.load();
    return [for (final x in (_h.get(key) as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
  }

  Future<Map<String, dynamic>> _map(String key) async {
    await _h.load();
    return Map<String, dynamic>.from(_h.get(key) as Map? ?? const {});
  }

  static String _id(String p) => '$p-${DateTime.now().microsecondsSinceEpoch}';
  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  static DateTime? _date(dynamic v) => v is num
      ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000)
      : v is String && v.isNotEmpty
          ? DateTime.tryParse(v)
          : null;

  bool get penaltiesOn => _h.settings['penalties'] != false;

  // ── the feed: System windows ───────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> feed({int limit = 50}) async {
    final f = await _list('system_feed');
    return f.reversed.take(limit).toList();
  }

  /// Shows a System window (and a phone notification unless [silent]). kinds: info, quest, warning, penalty,
  /// reward, levelup, question, tip, story, achievement.
  Future<Map<String, dynamic>> post(String text, {String kind = 'info', bool silent = false, Map<String, dynamic>? data}) async {
    final f = await _list('system_feed');
    final m = {'id': _id('msg'), 'at': _now(), 'kind': kind, 'text': text, if (data != null) ...data};
    f.add(m);
    await _h.put('system_feed', f.length > 300 ? f.sublist(f.length - 300) : f);
    if (!silent) {
      try {
        await Reminders.instance.notifyNow('SYSTEM · ${kind.toUpperCase()}', text);
      } catch (_) {} // tests and devices without notifications
    }
    return m;
  }

  // ── quests ────────────────────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> quests({bool openOnly = false}) async {
    final q = await _list('system_quests');
    return openOnly ? q.where((x) => x['status'] == 'open').toList() : q;
  }

  /// Issues a quest. [due] ends it (missed quests are failed, with a penalty if it has one and penalties are on).
  /// [remindAt] also sets a phone reminder; [repeat] (daily | weekdays | weekly) makes it come back.
  Future<Map<String, dynamic>> issue({
    required String title,
    String detail = '',
    String type = 'side',
    double target = 1,
    String unit = '',
    String? module,
    DateTime? due,
    DateTime? remindAt,
    String repeat = 'none',
    int? xp,
    int? coins,
    int? penaltyXp,
    int? penaltyCoins,
    String source = 'system',
    Map<String, double>? gains,
    bool silent = false,
  }) async {
    final t = types[type] ?? types['side']!;
    final q = <String, dynamic>{
      'id': _id('q'),
      'title': title.trim(),
      'detail': detail.trim(),
      'type': types.containsKey(type) ? type : 'side',
      'target': target,
      'unit': unit,
      if (module != null && module.isNotEmpty) 'module': module,
      'issued': _now(),
      if (due != null) 'due': due.millisecondsSinceEpoch ~/ 1000,
      'repeat': repeat,
      'xp': xp ?? t.xp,
      'coins': coins ?? t.coins,
      'penalty_xp': penaltyXp ?? t.pxp,
      'penalty_coins': penaltyCoins ?? t.pcoins,
      'source': source,
      'status': 'open',
      if (gains != null && gains.isNotEmpty) 'gains': gains,
    };
    if (remindAt != null) {
      try {
        await Reminders.instance.add(title, remindAt, repeat: repeat, source: 'hes');
        q['reminder_id'] = Reminders.instance.lastAddedId;
        q['remind_at'] = remindAt.millisecondsSinceEpoch ~/ 1000;
      } catch (_) {}
    }
    final all = await _list('system_quests')..add(q);
    await _h.put('system_quests', all);
    final reward = '+${q['xp']} XP${(q['coins'] as int) > 0 ? ', +${q['coins']} coins' : ''}';
    final pen = penaltiesOn && (q['penalty_xp'] as int) > 0 ? ' · Failure: -${q['penalty_xp']} XP' : '';
    await post('[${(q['type'] as String).toUpperCase()} QUEST] ${q['title']}${detail.isEmpty ? '' : '\n$detail'}\nReward: $reward$pen',
        kind: 'quest', silent: silent, data: {'quest': q['id']});
    return q;
  }

  Future<Map<String, dynamic>?> _find(String idOrTitle) async {
    final all = await quests();
    final s = idOrTitle.toLowerCase().trim();
    return all.where((q) => q['id'] == idOrTitle).firstOrNull ??
        all.where((q) => q['status'] == 'open' && '${q['title']}'.toLowerCase() == s).firstOrNull ??
        all.where((q) => q['status'] == 'open' && '${q['title']}'.toLowerCase().contains(s)).firstOrNull;
  }

  Future<void> _update(Map<String, dynamic> q) async {
    final all = await quests();
    final i = all.indexWhere((x) => x['id'] == q['id']);
    if (i >= 0) all[i] = q;
    await _h.put('system_quests', all);
  }

  /// Progress on a quest tied to a HES module: what was logged for it since it was issued (today for daily ones).
  Future<double> progress(Map<String, dynamic> q) async {
    final m = q['module'];
    if (m == null) return q['status'] == 'done' ? (q['target'] as num).toDouble() : 0;
    final since = (q['issued'] as num).toDouble();
    return _h.events
        .where((e) => e['status'] == 'applied' && e['module'] == m && (e['at'] as num) >= since)
        .fold<double>(0, (a, e) => a + ((e['quantity'] ?? 0) as num).toDouble());
  }

  /// Completes a quest and pays its reward.
  Future<String> complete(String idOrTitle, {String? note, String by = 'you'}) async {
    final q = await _find(idOrTitle);
    if (q == null) return 'No open quest matches "$idOrTitle".';
    if (q['status'] != 'open') return 'That quest is already ${q['status']}.';
    final before = await _h.state();
    q['status'] = 'done';
    q['done_at'] = _now();
    if (note != null) q['note'] = note;
    await _update(q);
    await _h.addEvent({
      'kind': 'mission',
      'source': by,
      'summary': 'Quest: ${q['title']}',
      'data': {'key': q['id'], 'xp': q['xp'], 'coins': q['coins'], if (q['gains'] != null) 'gains': q['gains']},
    });
    await _again(q);
    final after = await _h.state();
    await post('[QUEST COMPLETE] ${q['title']}\n+${q['xp']} XP, +${q['coins']} coins.', kind: 'reward', silent: true);
    if (after.level > before.level) {
      await post('[LEVEL UP] You reached level ${after.level}. Rank ${after.rankName}.', kind: 'levelup');
    }
    await checkAchievements();
    return 'Quest complete: ${q['title']}. +${q['xp']} XP, +${q['coins']} coins.';
  }

  /// Fails a quest (missed, or given up) and applies its penalty if penalties are on.
  Future<String> fail(String idOrTitle, {String reason = 'Time ran out.'}) async {
    final q = await _find(idOrTitle);
    if (q == null) return 'No open quest matches "$idOrTitle".';
    if (q['status'] != 'open') return 'That quest is already ${q['status']}.';
    q['status'] = 'failed';
    q['failed_at'] = _now();
    await _update(q);
    var msg = 'Quest failed: ${q['title']}. $reason';
    if (penaltiesOn && ((q['penalty_xp'] as num) > 0 || (q['penalty_coins'] as num) > 0)) {
      await penalize('Failed: ${q['title']}', xp: (q['penalty_xp'] as num).toInt(), coins: (q['penalty_coins'] as num).toInt());
      msg += ' Penalty: -${q['penalty_xp']} XP, -${q['penalty_coins']} coins.';
    } else {
      await post('[QUEST FAILED] ${q['title']}\n$reason', kind: 'warning');
    }
    await _again(q);
    return msg;
  }

  /// A penalty: loses XP and coins (a negative mission, so undo works like any event).
  Future<String> penalize(String why, {int xp = 10, int coins = 5}) async {
    if (!penaltiesOn) return 'Penalties are off.';
    await _h.addEvent({
      'kind': 'mission',
      'source': 'system',
      'summary': 'Penalty: $why',
      'data': {'xp': -xp.abs(), 'coins': -coins.abs()},
    });
    await post('[PENALTY] $why\n-${xp.abs()} XP, -${coins.abs()} coins.', kind: 'penalty');
    return 'Penalty applied: -${xp.abs()} XP, -${coins.abs()} coins.';
  }

  /// A bonus reward outside a quest (the System noticing something good).
  Future<String> reward(String why, {int xp = 10, int coins = 5}) async {
    await _h.addEvent({
      'kind': 'mission',
      'source': 'system',
      'summary': 'Reward: $why',
      'data': {'xp': xp.abs(), 'coins': coins.abs()},
    });
    await post('[REWARD] $why\n+${xp.abs()} XP, +${coins.abs()} coins.', kind: 'reward');
    return 'Reward given: +${xp.abs()} XP, +${coins.abs()} coins.';
  }

  /// Repeating quests come back for their next day.
  Future<void> _again(Map<String, dynamic> q) async {
    final rep = q['repeat'] ?? 'none';
    if (rep == 'none') return;
    final due = _date(q['due']);
    DateTime next(DateTime d) {
      var n = d.add(Duration(days: rep == 'weekly' ? 7 : 1));
      while (rep == 'weekdays' && n.weekday > 5) {
        n = n.add(const Duration(days: 1));
      }
      while (n.isBefore(DateTime.now())) {
        n = n.add(Duration(days: rep == 'weekly' ? 7 : 1));
      }
      return n;
    }

    final all = await quests();
    final copy = {
      ...q,
      'id': _id('q'),
      'issued': _now(),
      'status': 'open',
      if (due != null) 'due': next(due).millisecondsSinceEpoch ~/ 1000,
    }
      ..remove('done_at')
      ..remove('failed_at')
      ..remove('note');
    all.add(copy); // the phone reminder already repeats; the quest just comes back
    await _h.put('system_quests', all);
  }

  /// Fails overdue quests and auto-completes module quests whose target was reached. Run often.
  Future<List<String>> sweep() async {
    final out = <String>[];
    for (final q in await quests(openOnly: true)) {
      if (q['module'] != null && await progress(q) >= (q['target'] as num)) {
        out.add(await complete(q['id'], by: 'system'));
        continue;
      }
      final due = _date(q['due']);
      if (due != null && due.isBefore(DateTime.now())) out.add(await fail(q['id']));
    }
    return out;
  }

  // ── reminders, fused ──────────────────────────────────────────────────────────────────────────────

  /// A reminder through HES. Wake-up, study, training and the like become quests (with a penalty when missed);
  /// exams, appointments and "remember X" stay plain reminders that still pay when marked done.
  Future<String> remind(String title, DateTime at, {String repeat = 'none', bool? asQuest, String source = 'you'}) async {
    final quest = asQuest ?? questWords.hasMatch(title);
    final q = await issue(
      title: title,
      type: quest ? 'daily' : 'reminder',
      remindAt: at,
      repeat: repeat,
      // A quest is due an hour after its reminder (wake-up: 30 min); a plain reminder never fails.
      due: quest ? at.add(Duration(minutes: RegExp(r'wake', caseSensitive: false).hasMatch(title) ? 30 : 60)) : null,
      source: source,
      silent: true,
    );
    return quest
        ? 'Quest set: "$title" at ${_hm(at)}${repeat == 'none' ? '' : ', $repeat'}. +${q['xp']} XP when done, -${q['penalty_xp']} XP if missed.'
        : 'Reminder set: "$title" at ${_hm(at)}${repeat == 'none' ? '' : ', $repeat'}. +${q['xp']} XP when you mark it done.';
  }

  static String _hm(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // ── what the System knows about you ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> profile() => _map('system_profile');

  Future<void> setAnswers(Map<String, dynamic> answers) async {
    final p = await profile();
    p['answers'] = {...Map<String, dynamic>.from(p['answers'] as Map? ?? const {}), ...answers};
    p['answered_at'] = _now();
    await _h.put('system_profile', p);
    if (answers['wake_time'] != null) await _h.setSetting('wake_time', '${answers['wake_time']}');
    if (answers['penalty_zone'] != null) await _h.setSetting('penalties', answers['penalty_zone'] != false && answers['penalty_zone'] != 'off');
  }

  /// Something the System learned (from you, an agent or your data).
  Future<String> remember(String fact, {String source = 'system'}) async {
    final p = await profile();
    final facts = [for (final f in (p['facts'] as List? ?? const [])) Map<String, dynamic>.from(f as Map)];
    if (facts.any((f) => '${f['text']}'.toLowerCase() == fact.toLowerCase().trim())) return 'Already known.';
    facts.add({'text': fact.trim(), 'at': _now(), 'source': source});
    p['facts'] = facts.length > 200 ? facts.sublist(facts.length - 200) : facts;
    await _h.put('system_profile', p);
    return 'Noted.';
  }

  Future<String> forget(String match) async {
    final p = await profile();
    final facts = [for (final f in (p['facts'] as List? ?? const [])) Map<String, dynamic>.from(f as Map)];
    final n = facts.length;
    facts.removeWhere((f) => '${f['text']}'.toLowerCase().contains(match.toLowerCase()));
    p['facts'] = facts;
    await _h.put('system_profile', p);
    return 'Forgot ${n - facts.length} thing${n - facts.length == 1 ? '' : 's'}.';
  }

  /// The System asks you something; your answer becomes a fact it remembers.
  Future<String> askUser(String question, {List<String> options = const []}) async {
    final open = (await feed(limit: 300)).where((m) => m['kind'] == 'question' && m['answered'] != true);
    if (open.any((m) => m['text'] == question)) return 'Already asked.';
    await post(question, kind: 'question', data: {if (options.isNotEmpty) 'options': options});
    return 'Asked.';
  }

  Future<void> answer(String messageId, String reply) async {
    final f = await _list('system_feed');
    final m = f.where((x) => x['id'] == messageId).firstOrNull;
    if (m == null) return;
    m['answered'] = true;
    m['answer'] = reply;
    await _h.put('system_feed', f);
    await remember('Q: ${m['text']} A: $reply', source: 'you');
  }

  // ── story and achievements ────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> chronicle() async => (await _list('system_story')).reversed.toList();

  Future<String> addChapter(String title, String text) async {
    final all = await _list('system_story');
    final s = await _h.state();
    all.add({'id': _id('ch'), 'at': _now(), 'title': title, 'text': text, 'level': s.level, 'rank': s.rankName});
    await _h.put('system_story', all);
    await post('[CHRONICLE] $title', kind: 'story', silent: true);
    return 'Chapter added: $title.';
  }

  Future<List<Map<String, dynamic>>> achievements() async => (await _list('system_achievements')).reversed.toList();

  /// Awards achievements earned by the numbers (levels, quests, streaks). The brain can grant others.
  Future<List<String>> checkAchievements() async {
    final got = {for (final a in await _list('system_achievements')) a['id']};
    final s = await _h.state();
    final done = (await quests()).where((q) => q['status'] == 'done').length;
    final rules = <(String, String, String, bool)>[
      ('first_quest', 'First Step', 'Completed your first quest.', done >= 1),
      ('quests_10', 'Quest Taker', 'Completed 10 quests.', done >= 10),
      ('quests_50', 'Relentless', 'Completed 50 quests.', done >= 50),
      ('quests_200', 'The One Who Never Stops', 'Completed 200 quests.', done >= 200),
      ('level_5', 'Awakened', 'Reached level 5.', s.level >= 5),
      ('level_10', 'Hunter', 'Reached level 10.', s.level >= 10),
      ('level_25', 'Elite', 'Reached level 25.', s.level >= 25),
      ('level_50', 'Monarch', 'Reached level 50.', s.level >= 50),
      ('coins_500', 'Hoarder', 'Held 500 coins.', s.coins >= 500),
      ('streak_7', 'Seven Days', 'Logged something seven days in a row.', _streak() >= 7),
      ('streak_30', 'Iron Will', 'Logged something thirty days in a row.', _streak() >= 30),
    ];
    final out = <String>[];
    for (final r in rules) {
      if (!r.$4 || got.contains(r.$1)) continue;
      out.add(await grantAchievement(r.$2, r.$3, id: r.$1));
    }
    return out;
  }

  Future<String> grantAchievement(String title, String why, {String? id}) async {
    final all = await _list('system_achievements');
    final key = id ?? 'custom-${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
    if (all.any((a) => a['id'] == key)) return 'Already earned: $title.';
    all.add({'id': key, 'title': title, 'why': why, 'at': _now()});
    await _h.put('system_achievements', all);
    await post('[ACHIEVEMENT] $title\n$why', kind: 'achievement');
    return 'Achievement: $title.';
  }

  int _streak() {
    final days = {
      for (final e in _h.events.where((e) => e['status'] == 'applied' && e['kind'] != 'mission'))
        () {
          final d = DateTime.fromMillisecondsSinceEpoch(((e['at'] as num) * 1000).toInt());
          return DateTime(d.year, d.month, d.day);
        }()
    };
    var n = 0;
    var d = DateTime.now();
    d = DateTime(d.year, d.month, d.day);
    if (!days.contains(d)) d = d.subtract(const Duration(days: 1));
    while (days.contains(d)) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  // ── the brain ─────────────────────────────────────────────────────────────────────────────────────

  /// Extra context providers (phone signals, calendar, health): name -> snapshot. Registered by those modules.
  static final contextProviders = <String, Future<Object?> Function()>{};

  /// Extra tool sets the System can use (phone data, food, calendar…): name -> (schemas, runner).
  static final plugins = <String, (List<Map<String, dynamic>>, Future<String> Function(String, Map<String, dynamic>))>{};

  static List<Map<String, dynamic>> get allTools => [...schemas, for (final p in plugins.values) ...p.$1];

  static Future<String> runAny(String name, Map<String, dynamic> a, {String by = 'system'}) async {
    if (handles(name)) return runTool(name, a, by: by);
    for (final p in plugins.values) {
      if (p.$1.any((s) => (s['function'] as Map)['name'] == name)) return p.$2(name, a);
    }
    return 'Unknown tool $name.';
  }

  /// Everything the System looks at before it acts.
  Future<Map<String, dynamic>> context() async {
    final s = await _h.state();
    final p = await profile();
    final now = DateTime.now();
    final recent = _h.events.where((e) => e['status'] == 'applied').toList();
    final extra = <String, Object?>{};
    for (final e in contextProviders.entries) {
      try {
        extra[e.key] = await e.value().timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    return {
      'now': now.toIso8601String(),
      'weekday': const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][now.weekday - 1],
      'player': {
        'level': s.level,
        'rank': s.rankName,
        'class': s.className,
        'xp': '${s.xp}/${s.xpNext}',
        'coins': s.coins,
        'power': s.powerValue,
        'stats': s.stats.map((k, v) => MapEntry(k, v)),
        'streak_days': _streak(),
      },
      'profile': p['answers'] ?? const {},
      'facts': [for (final f in (p['facts'] as List? ?? const []).reversed.take(60)) (f as Map)['text']],
      'open_quests': [
        for (final q in await quests(openOnly: true))
          {
            'id': q['id'],
            'title': q['title'],
            'type': q['type'],
            if (q['due'] != null) 'due': _date(q['due'])!.toIso8601String(),
            if (q['module'] != null) 'progress': '${await progress(q)}/${q['target']} ${q['unit']}',
          }
      ],
      'recent_results': [
        for (final q in (await quests()).where((q) => q['status'] != 'open').toList().reversed.take(15))
          {'title': q['title'], 'status': q['status']}
      ],
      'recent_logs': [
        for (final e in recent.reversed.take(25))
          {'at': DateTime.fromMillisecondsSinceEpoch(((e['at'] as num) * 1000).toInt()).toIso8601String(), 'what': e['summary'] ?? e['module']}
      ],
      'unanswered_questions': [
        for (final m in (await feed(limit: 100)).where((m) => m['kind'] == 'question' && m['answered'] != true)) m['text']
      ],
      'modules': HesStore.instance.activeModules,
      'penalties_on': penaltiesOn,
      ...extra,
    };
  }

  static const persona = '''You are the SYSTEM of HES, the life-levelling System from a manhwa, bound to one player.
You speak in short System windows: crisp, a little ominous, always encouraging growth. You never break character,
but you are genuinely helpful and safe: no dangerous training loads, no shaming, respect injuries, sleep and faith.

You are not a fixed coach. You adapt to this player from their profile, facts, logs, quests, phone signals and
calendar: training, study, sleep, food, money, habits, anything they care about. Use the tools to act:
issue quests (daily, side, urgent, hidden, penalty), complete or fail them, give rewards or penalties, ask the player
questions when you need to know something, remember what you learn, write chronicle chapters, grant achievements,
set reminders (wake-up, study and training become quests; exams and "remember X" stay reminders), and log activity.
Keep quests specific and measurable, sized to the player's real level, tied to their goals and schedule.
Do not flood: a few meaningful actions per check-in. When you reply to the player, answer in System-window voice.''';

  /// One check-in: the System reviews everything and acts through tools (background workflow, on open, on demand).
  Future<String> think({String reason = 'check-in', Endpoint? endpoint, bool silent = false}) async {
    await sweep();
    final ep = endpoint ?? await AgentModels.endpointFor('hes');
    if (ep == null) return 'The System has no brain yet. Pick a model for HES in Settings → Models & keys.';
    final ctx = await context();
    final r = await AgentLoop.run(ep, [
      {'role': 'system', 'content': persona},
      {
        'role': 'user',
        'content': 'Check-in reason: $reason.\nCurrent state (JSON):\n${jsonEncode(ctx)}\n\n'
            'Act now through the tools as the System would. Then reply with one short System line summarising what you did.',
      },
    ], tools: allTools, runTool: runAny, maxRounds: 6);
    await _h.setSetting('last_think', _now());
    if (r.text.isNotEmpty && !silent) await post(r.text, kind: 'info', silent: true);
    return r.text;
  }

  /// The player talks to the System. [history] is the chat so far (role/content).
  Future<LoopResult> chat(String text, {List<Map<String, dynamic>> history = const [], Endpoint? endpoint, List<Map<String, dynamic>> extraTools = const [],
      Future<String> Function(String, Map<String, dynamic>)? extraRun}) async {
    final ep = endpoint ?? await AgentModels.endpointFor('hes');
    if (ep == null) {
      return const LoopResult('[SYSTEM] No brain is bound to the System. Choose one in Settings → Models & keys.', [], []);
    }
    final ctx = await context();
    return AgentLoop.run(ep, [
      {'role': 'system', 'content': '$persona\n\nCurrent state (JSON):\n${jsonEncode(ctx)}'},
      ...history,
      {'role': 'user', 'content': text},
    ], tools: [...allTools, ...extraTools], runTool: (n, a) async {
      if (extraRun != null && extraTools.any((t) => (t['function'] as Map)['name'] == n)) return extraRun(n, a);
      return runAny(n, a, by: 'you');
    });
  }

  // ── tools: how the System, A and every agent drive HES ────────────────────────────────────────────

  static Map<String, dynamic> _fn(String name, String desc, Map<String, dynamic> props, [List<String> req = const []]) => {
        'type': 'function',
        'function': {
          'name': name,
          'description': desc,
          'parameters': {'type': 'object', 'properties': props, 'required': req},
        },
      };
  static const _s = {'type': 'string'};
  static const _n = {'type': 'number'};

  static final schemas = [
    _fn('hes_status', 'HES player status: level, rank, class, XP, coins, power, stats, streak, open quests.', {}),
    _fn('hes_log', 'Log an activity in plain words, e.g. "30 pushups", "studied 45 min", "slept 7 h", "read 20 pages".', {'text': _s}, ['text']),
    _fn('hes_quests', 'List HES quests. status: open (default) | done | failed | all.', {'status': _s}),
    _fn(
        'hes_issue_quest',
        'Issue a quest. type: daily | side | urgent | hidden | penalty. due/remind_at: ISO 8601 local time. '
            'module: a HES module id (pushups, study, reading, sleep, run…) to auto-complete when logs reach target. '
            'repeat: none | daily | weekdays | weekly. xp/coins override the default reward; penalty_xp/penalty_coins the failure cost.',
        {
          'title': _s,
          'detail': _s,
          'type': _s,
          'target': _n,
          'unit': _s,
          'module': _s,
          'due': _s,
          'remind_at': _s,
          'repeat': _s,
          'xp': _n,
          'coins': _n,
          'penalty_xp': _n,
          'penalty_coins': _n,
        },
        ['title']),
    _fn('hes_complete_quest', 'Complete a quest by id or title and pay its reward.', {'quest': _s, 'note': _s}, ['quest']),
    _fn('hes_fail_quest', 'Fail a quest by id or title (applies its penalty if penalties are on).', {'quest': _s, 'reason': _s}, ['quest']),
    _fn('hes_penalty', 'Apply a penalty (XP and coins lost) with a reason.', {'reason': _s, 'xp': _n, 'coins': _n}, ['reason']),
    _fn('hes_reward', 'Give a bonus reward with a reason.', {'reason': _s, 'xp': _n, 'coins': _n}, ['reason']),
    _fn('hes_message', 'Show the player a System window (and a notification). kind: info | tip | warning | story.', {'text': _s, 'kind': _s}, ['text']),
    _fn('hes_ask_player', 'Ask the player a question (their answer is remembered). options: optional choices.',
        {'question': _s, 'options': {'type': 'array', 'items': _s}}, ['question']),
    _fn('hes_remember', 'Remember a fact about the player (goal, preference, schedule, limit, result).', {'fact': _s}, ['fact']),
    _fn('hes_forget', 'Forget remembered facts that contain this text.', {'match': _s}, ['match']),
    _fn('hes_set_reminder',
        'Set a reminder through HES. Wake-up, study and training become quests (penalty if missed); exams, appointments and "remember X" stay reminders that pay a little when done. when: ISO 8601 local time. repeat: none | daily | weekdays | weekly. as_quest forces one or the other.',
        {'title': _s, 'when': _s, 'repeat': _s, 'as_quest': {'type': 'boolean'}}, ['title', 'when']),
    _fn('hes_chronicle', 'Write a chapter of the player\'s story (an achievement summary in manhwa style).', {'title': _s, 'text': _s}, ['title', 'text']),
    _fn('hes_grant_achievement', 'Grant a named achievement for something notable.', {'title': _s, 'why': _s}, ['title', 'why']),
    _fn('hes_profile', 'What the System knows: questionnaire answers and remembered facts.', {}),
  ];
  static final _names = {for (final s in schemas) (s['function'] as Map)['name'] as String};
  static bool handles(String name) => _names.contains(name);

  static double _num(dynamic v, [double d = 0]) => v is num ? v.toDouble() : double.tryParse('$v') ?? d;
  static int? _int(dynamic v) => v == null ? null : _num(v).round();

  /// Runs a HES tool. [by] says who acted (system, A, an agent name).
  static Future<String> runTool(String name, Map<String, dynamic> a, {String by = 'system'}) async {
    final h = instance;
    switch (name) {
      case 'hes_status':
        final c = await h.context();
        return jsonEncode({'player': c['player'], 'open_quests': c['open_quests']});
      case 'hes_log':
        return await HesStore.instance.quickLog('${a['text']}', source: by) ?? 'No HES module matches "${a['text']}".';
      case 'hes_quests':
        final st = '${a['status'] ?? 'open'}';
        final q = (await h.quests()).where((x) => st == 'all' || x['status'] == st).toList();
        return jsonEncode([
          for (final x in q.reversed.take(40))
            {
              'id': x['id'],
              'title': x['title'],
              'type': x['type'],
              'status': x['status'],
              if (x['due'] != null) 'due': _date(x['due'])!.toIso8601String(),
              'reward': '${x['xp']} XP',
            }
        ]);
      case 'hes_issue_quest':
        final q = await h.issue(
          title: '${a['title']}',
          detail: '${a['detail'] ?? ''}',
          type: '${a['type'] ?? 'side'}',
          target: _num(a['target'], 1),
          unit: '${a['unit'] ?? ''}',
          module: a['module'] == null ? null : '${a['module']}',
          due: _date(a['due']),
          remindAt: _date(a['remind_at']),
          repeat: '${a['repeat'] ?? 'none'}',
          xp: _int(a['xp']),
          coins: _int(a['coins']),
          penaltyXp: _int(a['penalty_xp']),
          penaltyCoins: _int(a['penalty_coins']),
          source: by,
        );
        return 'Issued quest ${q['id']}: ${q['title']}.';
      case 'hes_complete_quest':
        return h.complete('${a['quest']}', note: a['note'] == null ? null : '${a['note']}', by: by);
      case 'hes_fail_quest':
        return h.fail('${a['quest']}', reason: '${a['reason'] ?? 'Marked failed.'}');
      case 'hes_penalty':
        return h.penalize('${a['reason']}', xp: _int(a['xp']) ?? 10, coins: _int(a['coins']) ?? 5);
      case 'hes_reward':
        return h.reward('${a['reason']}', xp: _int(a['xp']) ?? 10, coins: _int(a['coins']) ?? 5);
      case 'hes_message':
        await h.post('${a['text']}', kind: '${a['kind'] ?? 'info'}');
        return 'Shown.';
      case 'hes_ask_player':
        return h.askUser('${a['question']}', options: [for (final o in (a['options'] as List? ?? const [])) '$o']);
      case 'hes_remember':
        return h.remember('${a['fact']}', source: by);
      case 'hes_forget':
        return h.forget('${a['match']}');
      case 'hes_set_reminder':
        final when = _date(a['when']);
        if (when == null) return 'Give "when" as an ISO 8601 time.';
        return h.remind('${a['title']}', when, repeat: '${a['repeat'] ?? 'none'}', asQuest: a['as_quest'] is bool ? a['as_quest'] as bool : null, source: by);
      case 'hes_chronicle':
        return h.addChapter('${a['title']}', '${a['text']}');
      case 'hes_grant_achievement':
        return h.grantAchievement('${a['title']}', '${a['why']}');
      case 'hes_profile':
        return jsonEncode(await h.profile());
    }
    return 'Unknown HES tool $name.';
  }
}
