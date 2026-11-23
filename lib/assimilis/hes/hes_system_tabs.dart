import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../hub/brand.dart';
import '../../hub/hud.dart';
import 'hes_food.dart';
import 'hes_questionnaire_view.dart';
import 'hes_store.dart';
import 'hes_system.dart';
import 'phone_signals.dart';

String _ago(dynamic ts) {
  if (ts is! num) return '';
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000));
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}

Color _kindColor(String k) => switch (k) {
      'quest' => AssimilisBrand.violetSoft,
      'reward' || 'levelup' || 'achievement' => AssimilisBrand.mint,
      'penalty' || 'warning' => AssimilisBrand.red,
      'question' => const Color(0xFFFFB300),
      'story' => AssimilisBrand.magenta,
      _ => const Color(0xFF26C6DA),
    };

/// A System window: the blue-bordered notice from the manhwa.
class SystemWindow extends StatelessWidget {
  const SystemWindow({super.key, required this.kind, required this.text, this.time, this.child});
  final String kind, text;
  final String? time;
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    final c = _kindColor(kind);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AssimilisBrand.navyDeep.withValues(alpha: 0.85),
        border: Border.all(color: c.withValues(alpha: 0.8)),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.25), blurRadius: 14)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.info_outline_rounded, size: 14, color: c),
          const SizedBox(width: 6),
          Text('SYSTEM · ${kind.toUpperCase()}', style: AssimilisBrand.label(10, color: c, w: FontWeight.w800)),
          const Spacer(),
          if (time != null) Text(time!, style: AssimilisBrand.label(10)),
        ]),
        const SizedBox(height: 6),
        Text(text, style: AssimilisBrand.body(13.5)),
        if (child != null) ...[const SizedBox(height: 8), child!],
      ]),
    );
  }
}

/// The System tab: its windows, its questions to you, and a line to talk to it.
class SystemFeedTab extends StatefulWidget {
  const SystemFeedTab({super.key, this.onChanged});
  final VoidCallback? onChanged;
  @override
  State<SystemFeedTab> createState() => _SystemFeedTabState();
}

class _SystemFeedTabState extends State<SystemFeedTab> {
  final _sys = HesSystem.instance;
  List<Map<String, dynamic>> _feed = [];
  final _chat = <Map<String, dynamic>>[];
  final _input = TextEditingController();
  bool _busy = false;
  String? _status;
  bool _answered = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _feed = await _sys.feed(limit: 40);
    _answered = ((await _sys.profile())['answers'] as Map?)?.isNotEmpty == true;
    if (mounted) setState(() {});
  }

  Future<void> _run(String label, Future<String> Function() f) async {
    setState(() {
      _busy = true;
      _status = label;
    });
    String r;
    try {
      r = await f();
    } catch (e) {
      r = '$e'.replaceFirst('Exception: ', '');
    }
    _status = r;
    _busy = false;
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty || _busy) return;
    _input.clear();
    await _run('The System is listening…', () async {
      final r = await _sys.chat(t, history: _chat.length > 12 ? _chat.sublist(_chat.length - 12) : _chat);
      _chat
        ..add({'role': 'user', 'content': t})
        ..add({'role': 'assistant', 'content': r.text});
      return r.text.isEmpty ? 'Done.' : r.text;
    });
  }

  Future<void> _food() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AssimilisBrand.panel,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Take a photo'), onTap: () => Navigator.pop(c, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('From the gallery'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
        ]),
      ),
    );
    if (src == null) return;
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1280, imageQuality: 80);
    if (x == null) return;
    await _run('Reading your meal…', () async => HesFood.log(await HesFood.estimate(photo: File(x.path))));
  }

  @override
  Widget build(BuildContext context) {
    final questions = _feed.where((m) => m['kind'] == 'question' && m['answered'] != true).toList();
    final rest = _feed.where((m) => !(m['kind'] == 'question' && m['answered'] != true)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!_answered)
        SystemWindow(
          kind: 'quest',
          text: 'You have been chosen. Answer the Awakening so the System can shape itself to you.',
          child: FilledButton(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => Theme(data: AssimilisBrand.theme(), child: const HesQuestionnaireView())));
              _load();
              widget.onChanged?.call();
            },
            child: const Text('Begin the Awakening'),
          ),
        ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        HudChip('Check in', icon: Icons.bolt_rounded, onTap: _busy ? null : () => _run('The System is reviewing…', () => _sys.think(reason: 'the player asked for a check-in'))),
        HudChip('Food photo', icon: Icons.restaurant_rounded, onTap: _busy ? null : _food),
        HudChip('Awakening', icon: Icons.assignment_ind_rounded, onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => Theme(data: AssimilisBrand.theme(), child: const HesQuestionnaireView())));
          _load();
        }),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _input,
        enabled: !_busy,
        onSubmitted: (_) => _send(),
        style: AssimilisBrand.body(14),
        decoration: InputDecoration(
          hintText: 'Speak to the System…',
          prefixIcon: const Icon(Icons.terminal_rounded, color: AssimilisBrand.violet),
          suffixIcon: IconButton(onPressed: _send, icon: const Icon(Icons.send_rounded, color: AssimilisBrand.violet)),
        ),
      ),
      if (_status != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_busy) const Padding(padding: EdgeInsets.only(right: 8, top: 2), child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))),
            Expanded(child: Text(_status!, style: AssimilisBrand.body(13, color: AssimilisBrand.mint))),
          ]),
        ),
      const SizedBox(height: 12),
      for (final q in questions)
        _QuestionWindow(q: q, onAnswered: () {
          _load();
          widget.onChanged?.call();
        }),
      for (final m in rest) SystemWindow(kind: '${m['kind']}', text: '${m['text']}', time: _ago(m['at'])),
      if (_feed.isEmpty) const HudNote('No System windows yet. Answer the Awakening or tap Check in.'),
    ]);
  }
}

class _QuestionWindow extends StatefulWidget {
  const _QuestionWindow({required this.q, required this.onAnswered});
  final Map<String, dynamic> q;
  final VoidCallback onAnswered;
  @override
  State<_QuestionWindow> createState() => _QuestionWindowState();
}

class _QuestionWindowState extends State<_QuestionWindow> {
  final _c = TextEditingController();
  Future<void> _answer(String a) async {
    if (a.trim().isEmpty) return;
    await HesSystem.instance.answer('${widget.q['id']}', a.trim());
    widget.onAnswered();
  }

  @override
  Widget build(BuildContext context) {
    final opts = [for (final o in (widget.q['options'] as List? ?? const [])) '$o'];
    return SystemWindow(
      kind: 'question',
      text: '${widget.q['text']}',
      time: _ago(widget.q['at']),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (opts.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: [for (final o in opts) ActionChip(label: Text(o), onPressed: () => _answer(o))]),
        TextField(
          controller: _c,
          onSubmitted: _answer,
          decoration: InputDecoration(hintText: 'Your answer', suffixIcon: IconButton(icon: const Icon(Icons.send_rounded), onPressed: () => _answer(_c.text))),
        ),
      ]),
    );
  }
}

/// Quests the System, agents and reminders issued.
class SystemQuestList extends StatefulWidget {
  const SystemQuestList({super.key, this.onChanged});
  final VoidCallback? onChanged;
  @override
  State<SystemQuestList> createState() => _SystemQuestListState();
}

class _SystemQuestListState extends State<SystemQuestList> {
  List<Map<String, dynamic>> _q = [];
  final _progress = <String, double>{};
  String? _msg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await HesSystem.instance.sweep();
    _q = await HesSystem.instance.quests(openOnly: true);
    for (final q in _q) {
      if (q['module'] != null) _progress['${q['id']}'] = await HesSystem.instance.progress(q);
    }
    if (mounted) setState(() {});
  }

  String _due(Map q) {
    final d = q['due'];
    if (d is! num) return q['type'] == 'reminder' ? 'reminder' : 'no deadline';
    final left = DateTime.fromMillisecondsSinceEpoch(d.toInt() * 1000).difference(DateTime.now());
    if (left.isNegative) return 'overdue';
    return left.inHours >= 1 ? '${left.inHours}h ${left.inMinutes % 60}m left' : '${left.inMinutes}m left';
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HudHeader('System quests', trailing: Text('${_q.length} open', style: AssimilisBrand.label(11, color: AssimilisBrand.violetSoft))),
      if (_q.isEmpty) const HudNote('No System quests yet. The System issues them at check-ins, or ask it in the System tab.'),
      for (final q in _q)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: HudPanel(
            accent: _kindColor(q['type'] == 'urgent' || q['type'] == 'penalty' ? 'penalty' : 'quest'),
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text('[${'${q['type']}'.toUpperCase()}]', style: AssimilisBrand.label(10, color: AssimilisBrand.violetSoft, w: FontWeight.w800)),
                const SizedBox(width: 8),
                Expanded(child: Text('${q['title']}', style: AssimilisBrand.body(14, w: FontWeight.w600))),
              ]),
              if ('${q['detail'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${q['detail']}', style: AssimilisBrand.body(12, color: AssimilisBrand.muted))),
              if (q['module'] != null) ...[
                const SizedBox(height: 6),
                HudBar(((_progress['${q['id']}'] ?? 0) / ((q['target'] as num).toDouble())).clamp(0, 1).toDouble(), height: 4),
                Text('${(_progress['${q['id']}'] ?? 0).toStringAsFixed(0)} / ${(q['target'] as num).toStringAsFixed(0)} ${q['unit']}', style: AssimilisBrand.label(10)),
              ],
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(
                      '+${q['xp']} XP · +${q['coins']} coins${(q['penalty_xp'] as num) > 0 && HesSystem.instance.penaltiesOn ? ' · fail −${q['penalty_xp']} XP' : ''} · ${_due(q)}',
                      style: AssimilisBrand.label(10)),
                ),
                TextButton(
                  onPressed: () async {
                    _msg = await HesSystem.instance.fail('${q['id']}', reason: 'Given up.');
                    await _load();
                    widget.onChanged?.call();
                  },
                  child: Text('GIVE UP', style: AssimilisBrand.label(10, color: AssimilisBrand.faint)),
                ),
                FilledButton(
                  onPressed: () async {
                    _msg = await HesSystem.instance.complete('${q['id']}');
                    await _load();
                    widget.onChanged?.call();
                  },
                  child: const Text('DONE'),
                ),
              ]),
            ]),
          ),
        ),
      if (_msg != null) Text('[SYSTEM] $_msg', style: AssimilisBrand.label(11, color: AssimilisBrand.mint)),
    ]);
  }
}

/// Story: achievements and the chronicle the System writes.
class StoryTab extends StatefulWidget {
  const StoryTab({super.key});
  @override
  State<StoryTab> createState() => _StoryTabState();
}

class _StoryTabState extends State<StoryTab> {
  List<Map<String, dynamic>> _ach = [], _ch = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await HesSystem.instance.checkAchievements();
    _ach = await HesSystem.instance.achievements();
    _ch = await HesSystem.instance.chronicle();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HudHeader('Achievements', trailing: Text('${_ach.length}', style: AssimilisBrand.label(11, color: AssimilisBrand.mint))),
      if (_ach.isEmpty) const HudNote('None yet. Complete your first quest.'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in _ach)
          Tooltip(
            message: '${a['why']}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(border: Border.all(color: AssimilisBrand.mint.withValues(alpha: 0.7)), color: AssimilisBrand.mint.withValues(alpha: 0.08)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.emoji_events_rounded, size: 14, color: AssimilisBrand.mint),
                const SizedBox(width: 6),
                Text('${a['title']}', style: AssimilisBrand.label(11, color: AssimilisBrand.text)),
              ]),
            ),
          ),
      ]),
      HudHeader('Chronicle',
          trailing: TextButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await HesSystem.instance.think(reason: 'the player asked for a chronicle chapter about their recent journey (use hes_chronicle)');
                    } catch (_) {}
                    _busy = false;
                    await _load();
                  },
            child: Text(_busy ? 'WRITING…' : 'WRITE A CHAPTER', style: AssimilisBrand.label(10, color: AssimilisBrand.violetSoft)),
          )),
      if (_ch.isEmpty) const HudNote('The System writes a chapter each evening.'),
      for (final c in _ch)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HudPanel(
            accent: AssimilisBrand.magenta,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${c['title']}', style: AssimilisBrand.display(13, w: FontWeight.w700)),
              Text('Level ${c['level']} · ${c['rank']} · ${_ago(c['at'])} ago', style: AssimilisBrand.label(10)),
              const SizedBox(height: 6),
              Text('${c['text']}', style: AssimilisBrand.body(13)),
            ]),
          ),
        ),
    ]);
  }
}

/// Phone data: connect calendar, location, Health Connect (Google Fit, smartwatch) and screen time; see what the
/// System sees; System settings (penalties, check-ins).
class PhoneDataTab extends StatefulWidget {
  const PhoneDataTab({super.key});
  @override
  State<PhoneDataTab> createState() => _PhoneDataTabState();
}

class _PhoneDataTabState extends State<PhoneDataTab> {
  Map<String, dynamic> _snap = {};
  Map<String, dynamic> _connected = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await HesStore.instance.load();
    _connected = Map<String, dynamic>.from(HesStore.instance.settings['signals_connected'] as Map? ?? const {});
    try {
      _snap = await PhoneSignals.instance.snapshot();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Widget _row(IconData i, String name, String key, String sub) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(i, color: _connected[key] == true ? AssimilisBrand.mint : AssimilisBrand.muted),
        title: Text(name, style: AssimilisBrand.body(14, w: FontWeight.w600)),
        subtitle: Text(sub, style: AssimilisBrand.body(11, color: AssimilisBrand.muted)),
        trailing: Text(_connected[key] == true ? 'ON' : 'OFF', style: AssimilisBrand.label(10, color: _connected[key] == true ? AssimilisBrand.mint : AssimilisBrand.faint)),
      );

  @override
  Widget build(BuildContext context) {
    final s = HesStore.instance.settings;
    final h = _snap['health_today'] as Map?;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HudPanel(
        title: 'Phone data',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('The System adapts to what your phone knows. Nothing leaves the phone except to the brain you chose.',
              style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
          _row(Icons.calendar_month_rounded, 'Calendars', 'calendar', 'Phone and Google calendars: read and add events'),
          _row(Icons.location_on_rounded, 'Location history', 'location_background', 'Places you spend time; kept by HES'),
          _row(Icons.favorite_rounded, 'Health Connect', 'health', 'Sleep, steps, workouts, heart rate: Google Fit and smartwatches'),
          _row(Icons.phone_android_rounded, 'Screen time', 'screen_time', 'Minutes per app today'),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_rounded),
            label: const Text('Connect phone data'),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      _connected = await PhoneSignals.instance.connect();
                    } catch (_) {}
                    _busy = false;
                    await _load();
                  },
          ),
        ]),
      ),
      const HudHeader('What the System sees now'),
      HudPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (h != null) ...[
            Text('Steps today: ${h['steps_today'] ?? '–'}', style: AssimilisBrand.body(13)),
            if (h['last_sleep'] != null) Text('Last sleep: ${(h['last_sleep'] as Map)['hours']} h', style: AssimilisBrand.body(13)),
            if (h['heart_rate'] != null) Text('Heart rate: ${(h['heart_rate'] as Map)['avg']} avg', style: AssimilisBrand.body(13)),
          ],
          if (_snap['next_alarm'] != null) Text('Next alarm: ${(_snap['next_alarm'] as Map)['at'].toString().replaceFirst('T', ' ').substring(0, 16)}', style: AssimilisBrand.body(13)),
          if (_snap['screen_time_today'] != null) Text('Screen time today: ${(_snap['screen_time_today'] as Map)['total_minutes']} min', style: AssimilisBrand.body(13)),
          if (_snap['calendar_next_7_days'] != null) Text('Calendar: ${(_snap['calendar_next_7_days'] as List).length} events in the next 7 days', style: AssimilisBrand.body(13)),
          if (_snap['location'] != null) Text('Places known: ${((_snap['location'] as Map)['places'] as List).length}', style: AssimilisBrand.body(13)),
          if (_snap.isEmpty) Text('Nothing connected yet.', style: AssimilisBrand.body(13, color: AssimilisBrand.muted)),
        ]),
      ),
      const HudHeader('System settings'),
      HudPanel(
        child: Column(children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s['penalties'] != false,
            title: Text('Penalties', style: AssimilisBrand.body(14, w: FontWeight.w600)),
            subtitle: Text('Missed quests cost XP and coins', style: AssimilisBrand.body(11, color: AssimilisBrand.muted)),
            onChanged: (v) async {
              await HesStore.instance.setSetting('penalties', v);
              setState(() {});
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s['system_paused'] != true,
            title: Text('Background check-ins', style: AssimilisBrand.body(14, w: FontWeight.w600)),
            subtitle: Text('Morning briefing, check-ins, evening review', style: AssimilisBrand.body(11, color: AssimilisBrand.muted)),
            onChanged: (v) async {
              await HesStore.instance.setSetting('system_paused', !v);
              setState(() {});
            },
          ),
          Row(children: [
            Expanded(child: Text('Check in every', style: AssimilisBrand.body(14))),
            DropdownButton<int>(
              value: ((s['think_every_hours'] as num?) ?? 3).toInt(),
              items: [for (final h in [1, 2, 3, 4, 6, 8]) DropdownMenuItem(value: h, child: Text('$h h'))],
              onChanged: (v) async {
                await HesStore.instance.setSetting('think_every_hours', v!);
                setState(() {});
              },
            ),
          ]),
        ]),
      ),
    ]);
  }
}
