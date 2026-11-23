import 'dart:convert';

import '../phone_agent/models/agent_action.dart';
import '../phone_agent/services/action_handler.dart';
import '../phone_agent/services/ai_service.dart';
import 'a2a/a2a.dart';
import 'canvas/maths.dart';
import 'canvas/notes_store.dart';
import 'hes/hes_store.dart';
import 'hes/hes_system.dart';
import 'hes/phone_signals.dart';
import 'reach/agent_reach.dart';
import 'reminders.dart';

/// Tools the Assimilis brain (Jarvis) can call. OpenAI function-calling schemas + handlers.
class AssimilisTools {
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
    _fn('set_alarm', 'Set a real alarm in the phone\'s Clock app.', {'hour': _n, 'minute': _n, 'label': _s}, ['hour', 'minute']),
    _fn('set_timer', 'Start a countdown timer in the Clock app.', {'seconds': _n, 'label': _s}, ['seconds']),
    _fn('set_reminder',
        'Schedule a reminder (through HES: wake-up, study and training become quests; others stay reminders that pay a little when done). when = ISO 8601 local time. repeat: none|daily|weekly|weekdays.',
        {'title': _s, 'when': _s, 'repeat': _s}, ['title', 'when']),
    _fn('list_reminders', 'List upcoming reminders with their ids.', {}),
    _fn('cancel_reminder', 'Cancel a reminder by id.', {'id': _n}, ['id']),
    _fn('show_alarms', 'Open the Clock app alarm list.', {}),
    _fn('create_note', 'Create a Canvas note page. Markdown with \$LaTeX\$ and prompt(graph, "f(x)") / prompt(math, "expr") blocks allowed.',
        {'title': _s, 'content': _s, 'notebook': _s, 'section': _s}, ['title', 'content']),
    _fn('search_notes', 'Search Canvas notes; returns titles, ids and snippets.', {'query': _s}, ['query']),
    _fn('read_note', 'Read a Canvas page by id.', {'id': _s}, ['id']),
    _fn('append_note', 'Append markdown to an existing Canvas page by id.', {'id': _s, 'content': _s}, ['id', 'content']),
    _fn('calculate', 'Evaluate a maths expression exactly (supports sqrt, sin, cos, tan, ln, log, ^, pi, e).', {'expression': _s}, ['expression']),
    _fn('derivative', 'Symbolic derivative with respect to x.', {'expression': _s}, ['expression']),
    _fn('integral', 'Numeric definite integral of f(x) from a to b.', {'expression': _s, 'a': _n, 'b': _n}, ['expression', 'a', 'b']),
    _fn('web_search', 'Search the web (Agent Reach / Exa).', {'query': _s}, ['query']),
    _fn('read_url', 'Read a web page, GitHub repo, YouTube video (captions) or Reddit thread as text.', {'url': _s}, ['url']),
    _fn('github', 'GitHub repo info + README ("owner/repo") or a repo search.', {'query': _s}, ['query']),
    _fn('reddit', 'Hot posts of a subreddit ("r/name") or a Reddit post URL.', {'target': _s}, ['target']),
    _fn('rss', 'Latest items of an RSS/Atom feed.', {'url': _s}, ['url']),
    _fn('list_devices', 'Nearby Assimilis devices (A2A) with their brain, loaded model and RAM.', {}),
    _fn('ask_device', 'Send a request to another Assimilis device. skill: ask (its A answers), generate (raw text from its loaded model; use for heavy jobs), phone_task (it uses that device). device: name, or "best" for the strongest.',
        {'device': _s, 'message': _s, 'skill': _s}, ['device', 'message']),
    _fn('phone_task', 'Operate the phone screen to do a multi-step job in other apps (open apps, tap, type, scroll). '
        'Risky steps ask the owner on screen unless Full allow is on.', {'task': _s}, ['task']),
    // HES: every agent can drive the System.
    ...HesSystem.schemas,
    // Phone data: calendars, health, location history, screen time, next alarm.
    ...PhoneSignals.schemas,
  ];

  static String statusFor(String name) => switch (name) {
        'set_alarm' => 'Setting an alarm…',
        'set_timer' => 'Starting a timer…',
        'set_reminder' => 'Setting a reminder…',
        'create_note' || 'append_note' => 'Writing to Canvas…',
        'search_notes' || 'read_note' => 'Checking your notes…',
        'calculate' || 'derivative' || 'integral' => 'Calculating…',
        _ when name.startsWith('hes_') => 'Updating HES…',
        'web_search' => 'Searching the web…',
        'read_url' || 'github' || 'reddit' || 'rss' => 'Reading…',
        'phone_task' => 'Working on your phone…',
        'list_devices' || 'ask_device' => 'Talking to your devices…',
        _ => 'Working…',
      };

  static num _num(dynamic v, [num d = 0]) => v is num ? v : num.tryParse('$v') ?? d;

  static Future<String> run(String name, Map<String, dynamic> a) async {
    try {
      final r = Reminders.instance;
      final notes = NotesStore.instance;
      if (HesSystem.handles(name)) return await HesSystem.runTool(name, a, by: 'A');
      if (PhoneSignals.handles(name)) return await PhoneSignals.runTool(name, a);
      switch (name) {
        case 'set_alarm':
          return await r.alarm(_num(a['hour']).toInt(), _num(a['minute']).toInt(), label: a['label']);
        case 'set_timer':
          return await r.timer(_num(a['seconds']).toInt(), label: a['label']);
        case 'set_reminder':
          final when = DateTime.tryParse('${a['when']}');
          if (when == null) return 'Could not read the time "${a['when']}". Use ISO 8601.';
          return await HesSystem.instance.remind('${a['title']}', when, repeat: '${a['repeat'] ?? 'none'}', source: 'A');
        case 'list_reminders':
          final list = await r.list();
          return list.isEmpty
              ? 'No reminders.'
              : list.map((x) => '#${x.id} ${x.title} at ${x.at.toIso8601String()} (${x.repeat})').join('\n');
        case 'cancel_reminder':
          return await r.cancel(_num(a['id']).toInt());
        case 'show_alarms':
          return await r.showAlarms();
        case 'create_note':
          await notes.load();
          final p = await notes.quickNote('${a['title']}', '${a['content']}',
              book: '${a['notebook'] ?? 'Inbox'}', section: '${a['section'] ?? 'Notes'}');
          return 'Created note ${p['id']} "${p['title']}" in ${a['notebook'] ?? 'Inbox'}.';
        case 'search_notes':
          await notes.load();
          final hits = notes.search('${a['query']}').take(8);
          return hits.isEmpty
              ? 'No notes match.'
              : hits.map((h) {
                  final t = '${h.page['text']}'.replaceAll('\n', ' ');
                  return '${h.page['id']} · ${h.book['name']} › ${h.section['name']} › ${h.page['title']}: '
                      '${t.length > 140 ? t.substring(0, 140) : t}';
                }).join('\n');
        case 'read_note':
          await notes.load();
          final f = notes.find('${a['id']}');
          if (f == null) return 'No page with id ${a['id']}.';
          return '# ${f.page['title']}\n${f.page['text']}\n'
              '${(f.page['nodes'] as List).map((n) => '- card: ${n['text']}').join('\n')}';
        case 'append_note':
          await notes.load();
          final f = notes.find('${a['id']}');
          if (f == null) return 'No page with id ${a['id']}.';
          f.page['text'] = '${f.page['text']}\n\n${a['content']}';
          await notes.touch(f.page);
          return 'Added to "${f.page['title']}".';
        case 'calculate':
          return '${a['expression']} = ${Maths.calc('${a['expression']}')}';
        case 'derivative':
          return 'd/dx ${a['expression']} = ${Maths.derive('${a['expression']}')}';
        case 'integral':
          return Maths.integrate('${a['expression']}', _num(a['a']).toDouble(), _num(a['b']).toDouble());
        case 'web_search':
          return await AgentReach.search('${a['query']}');
        case 'read_url':
          return await AgentReach.read('${a['url']}');
        case 'github':
          return await AgentReach.github('${a['query']}');
        case 'reddit':
          return await AgentReach.reddit('${a['target']}');
        case 'rss':
          return await AgentReach.rss('${a['url']}');
        case 'list_devices':
          final ps = A2a.instance.peers.values.toList();
          await Future.wait(ps.map(A2a.instance.refresh));
          return ps.isEmpty
              ? 'No other Assimilis devices found. They need the app open on the same Wi-Fi, or add one by Tailscale address.'
              : ps.map((p) => '${p.name}: ${p.card == null ? 'offline' : 'brain ${p.hasBrain ? 'yes' : 'no'}, model ${p.hasModel ? p.stats['model'] : 'none'}, ${p.ramGb.toStringAsFixed(0)} GB RAM'}').join('\n');
        case 'ask_device':
          final skill = '${a['skill'] ?? 'ask'}';
          final dev = '${a['device']}';
          final peer = dev == 'best' ? await A2a.instance.best(needModel: skill == 'generate') : A2a.instance.find(dev);
          if (peer == null) return 'No device called "$dev".';
          return '${peer.name}: ${await A2a.instance.send(peer, '${a['message']}', skill: skill)}';
        case 'phone_task':
          final ai = AiService();
          await ai.init();
          final res = await ActionHandler().execute(
            AgentAction(action: 'execute_task', params: {'goal': '${a['task']}'}, response: ''),
            aiService: ai,
          );
          return res.details ?? (res.success ? 'Done.' : 'The phone task failed.');
        default:
          return 'Unknown tool $name.';
      }
    } catch (e) {
      return 'Error in $name: $e';
    }
  }

  /// Offline, without tool calling: handle the commonest spoken commands directly.
  static Future<String?> offlineIntent(String text) async {
    final t = text.toLowerCase().trim();
    final timer = RegExp(r'timer (?:for )?(\d+)\s*(second|sec|minute|min|hour)').firstMatch(t);
    if (timer != null) {
      final n = int.parse(timer.group(1)!);
      final unit = timer.group(2)!;
      return Reminders.instance.timer(unit.startsWith('h') ? n * 3600 : unit.startsWith('m') ? n * 60 : n);
    }
    final alarm = RegExp(r'alarm (?:for |at )?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?').firstMatch(t);
    if (alarm != null) {
      var h = int.parse(alarm.group(1)!);
      final m = int.tryParse(alarm.group(2) ?? '0') ?? 0;
      if (alarm.group(3) == 'pm' && h < 12) h += 12;
      if (alarm.group(3) == 'am' && h == 12) h = 0;
      return Reminders.instance.alarm(h, m);
    }
    final calc = RegExp(r'^(?:what is|calculate|compute)\s+(.+?)\??$').firstMatch(t);
    if (calc != null && RegExp(r'[\d)]').hasMatch(calc.group(1)!)) {
      final r = Maths.calc(calc.group(1)!.replaceAll('times', '*').replaceAll('plus', '+').replaceAll('minus', '-'));
      if (!r.startsWith('Could not')) return '${calc.group(1)} is $r.';
    }
    if (t.startsWith('hes status') || t == 'my stats') return HesStore.instance.status();
    if (RegExp(r'^(i |log |did |just )').hasMatch(t)) {
      return HesStore.instance.quickLog(text, source: 'jarvis');
    }
    return null;
  }

  static String pretty(Object o) => const JsonEncoder.withIndent('  ').convert(o);
}
