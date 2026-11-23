import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../hub/brand.dart';
import '../../hub/hud.dart';
import 'hes_system.dart';

/// The HES questionnaire: one page per group, every question type the server's HES uses. On finish the System
/// reads it, asks follow-up questions where it needs more, and sets up the first quests and reminders.
class HesQuestionnaireView extends StatefulWidget {
  const HesQuestionnaireView({super.key});
  @override
  State<HesQuestionnaireView> createState() => _HesQuestionnaireViewState();
}

class _HesQuestionnaireViewState extends State<HesQuestionnaireView> {
  List<Map<String, dynamic>> _groups = [];
  final _a = <String, dynamic>{};
  final _text = <String, TextEditingController>{};
  int _page = 0;
  bool _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = jsonDecode(await rootBundle.loadString('assets/hes/questionnaire.json')) as Map;
    final prev = Map<String, dynamic>.from(((await HesSystem.instance.profile())['answers'] as Map?) ?? const {});
    _groups = [for (final g in q['groups'] as List) Map<String, dynamic>.from(g as Map)];
    for (final g in _groups) {
      for (final x in g['questions'] as List) {
        final id = '${x['id']}';
        _a[id] = prev[id] ?? x['default'];
        if (x['type'] == 'text' || x['type'] == 'schedule' || x['type'] == 'number') {
          _text[id] = TextEditingController(text: _a[id] == null ? '' : (_a[id] is List ? (_a[id] as List).join('\n') : '${_a[id]}'));
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _collect() {
    for (final g in _groups) {
      for (final x in g['questions'] as List) {
        final id = '${x['id']}';
        final c = _text[id];
        if (c == null) continue;
        final v = c.text.trim();
        _a[id] = switch (x['type']) {
          'number' => v.isEmpty ? null : num.tryParse(v),
          'schedule' => v.isEmpty ? <String>[] : v.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList(),
          _ => v,
        };
      }
    }
  }

  Future<void> _finish() async {
    _collect();
    final missing = [
      for (final g in _groups)
        for (final x in g['questions'] as List)
          if (x['required'] == true && '${_a[x['id']] ?? ''}'.trim().isEmpty) '${x['label']}'
    ];
    if (missing.isNotEmpty) {
      setState(() => _msg = 'Please answer: ${missing.join(', ')}');
      return;
    }
    setState(() {
      _busy = true;
      _msg = 'The System is reading your answers…';
    });
    await HesSystem.instance.setAnswers({for (final e in _a.entries) if (e.value != null) e.key: e.value});
    String r;
    try {
      r = await HesSystem.instance.think(
          reason: 'onboarding: the player just answered the questionnaire. Remember what matters, ask follow-up questions '
              'where something is unclear, set their wake-up and study reminders, and issue their first quests.');
    } catch (e) {
      r = 'Saved. The System will read it when it has a brain (Settings → Models & keys). ($e)';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _msg = r;
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.of(context).pop(true);
  }

  bool _visible(Map x) {
    final cond = x['show_if'];
    return cond == null || _a['$cond'] == true;
  }

  Widget _question(Map x) {
    final id = '${x['id']}';
    final label = Text('${x['label']}${x['required'] == true ? ' *' : ''}', style: AssimilisBrand.body(14, w: FontWeight.w600));
    Widget field;
    switch (x['type']) {
      case 'text':
        field = TextField(
          controller: _text[id],
          maxLength: (x['max'] as num?)?.toInt(),
          maxLines: x['multiline'] == true ? 4 : 1,
          minLines: 1,
        );
      case 'number':
        field = TextField(
          controller: _text[id],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: '${x['unit'] ?? ''}'),
        );
      case 'schedule':
        field = TextField(
          controller: _text[id],
          maxLines: 5,
          minLines: 2,
          decoration: const InputDecoration(hintText: 'One per line, e.g.\nMon 09:00-11:00 Chemistry\nTue Thu 13:00-15:00 Calculus'),
        );
      case 'bool':
        field = SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _a[id] == true,
          title: Text(_a[id] == true ? 'Yes' : 'No', style: AssimilisBrand.body(13)),
          onChanged: (v) => setState(() => _a[id] = v),
        );
      case 'select':
        field = Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in x['options'] as List)
            ChoiceChip(label: Text('$o'), selected: _a[id] == o, onSelected: (_) => setState(() => _a[id] = o)),
        ]);
      case 'multi':
        final sel = {...(_a[id] as List? ?? const [])};
        final others = sel.where((s) => !(x['options'] as List).contains(s)).toList();
        field = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in [...x['options'] as List, ...others])
              FilterChip(
                label: Text('$o'),
                selected: sel.contains(o),
                onSelected: (on) => setState(() => _a[id] = on ? [...sel, o] : sel.where((s) => s != o).toList()),
              ),
          ]),
          if (x['allow_other'] == true)
            TextField(
              decoration: const InputDecoration(hintText: 'Other (press enter to add)'),
              onSubmitted: (v) {
                if (v.trim().isEmpty) return;
                setState(() => _a[id] = [...sel, v.trim()]);
              },
            ),
        ]);
      case 'scale':
        final labels = [for (final l in x['labels'] as List) '$l'];
        final v = ((_a[id] ?? 3) as num).toInt().clamp(1, labels.length);
        field = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Slider(min: 1, max: labels.length.toDouble(), divisions: labels.length - 1, value: v.toDouble(), onChanged: (n) => setState(() => _a[id] = n.round())),
          Text(labels[v - 1], textAlign: TextAlign.center, style: AssimilisBrand.label(11, color: AssimilisBrand.violetSoft)),
        ]);
      case 'time':
        final t = '${_a[id] ?? x['default'] ?? '07:00'}';
        field = OutlinedButton.icon(
          icon: const Icon(Icons.schedule_rounded, size: 18),
          label: Text(t),
          onPressed: () async {
            final p = t.split(':');
            final r = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.tryParse(p[0]) ?? 7, minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0));
            if (r != null) setState(() => _a[id] = '${r.hour.toString().padLeft(2, '0')}:${r.minute.toString().padLeft(2, '0')}');
          },
        );
      default:
        field = const SizedBox.shrink();
    }
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [label, const SizedBox(height: 6), field]));
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty) return const HudScaffold(title: 'Awakening', body: Center(child: CircularProgressIndicator()));
    final g = _groups[_page];
    final last = _page == _groups.length - 1;
    return HudScaffold(
      title: 'Awakening',
      subtitle: 'THE SYSTEM WANTS TO KNOW YOU · ${_page + 1} / ${_groups.length}',
      body: Column(children: [
        LinearProgressIndicator(value: (_page + 1) / _groups.length, color: AssimilisBrand.violet, backgroundColor: AssimilisBrand.line),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
            Text('${g['title']}'.toUpperCase(), style: AssimilisBrand.display(18, w: FontWeight.w800).copyWith(letterSpacing: 3)),
            const SizedBox(height: 14),
            for (final x in g['questions'] as List)
              if (_visible(x as Map)) _question(x),
            if (_msg != null) Text('[SYSTEM] $_msg', style: AssimilisBrand.label(11, color: AssimilisBrand.mint)),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(children: [
              if (_page > 0) OutlinedButton(onPressed: _busy ? null : () => setState(() => _page--), child: const Text('Back')),
              const Spacer(),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        _collect();
                        if (last) {
                          _finish();
                        } else {
                          setState(() => _page++);
                        }
                      },
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(last ? 'Bind to the System' : 'Next'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
