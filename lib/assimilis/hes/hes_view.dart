import 'package:flutter/material.dart';

import '../../hub/brand.dart';
import '../../hub/hud.dart';
import 'hes_engine.dart';
import 'hes_store.dart';
import 'hes_system_tabs.dart';

/// HES: Human Efficiency System, run by the System (an AI brain that adapts to you).
/// Tabs: System · Status · Quests · Story · Data · Modules · Abilities · Log · Evolution.
class HesView extends StatefulWidget {
  const HesView({super.key, this.initialTab = 'system'});
  final String initialTab;
  @override
  State<HesView> createState() => _HesViewState();
}

class _HesViewState extends State<HesView> {
  final _store = HesStore.instance;
  HesState? _s;
  String _title = 'Novice';
  List<Map<String, dynamic>> _quests = [];
  final _log = TextEditingController();
  String? _toast;
  late String _tab = widget.initialTab;

  static const tabs = {
    'system': Icons.terminal_rounded,
    'status': Icons.radar_rounded,
    'quests': Icons.flag_rounded,
    'story': Icons.auto_stories_rounded,
    'data': Icons.sensors_rounded,
    'modules': Icons.tune_rounded,
    'abilities': Icons.auto_awesome_rounded,
    'log': Icons.list_alt_rounded,
    'evolution': Icons.timeline_rounded,
  };

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await _store.state();
    final q = await _store.quests();
    final t = await _store.title();
    if (mounted) setState(() { _s = s; _quests = q; _title = t; });
  }

  Future<void> _quickLog() async {
    final t = _log.text.trim();
    if (t.isEmpty) return;
    final r = await _store.quickLog(t);
    _log.clear();
    setState(() => _toast = r ?? 'No tracker matched "$t". Try "30 pushups" or "studied 45 min".');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return HudScaffold(
      title: 'HES',
      subtitle: 'HUMAN EFFICIENCY SYSTEM',
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              SizedBox(
                height: 46,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 6, 12, 6), children: [
                  for (final e in tabs.entries)
                    HudChip(e.key, icon: e.value, selected: _tab == e.key, onTap: () => setState(() => _tab = e.key)),
                ]),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 32), children: switch (_tab) {
                    'system' => [SystemFeedTab(onChanged: _refresh)],
                    'story' => [const StoryTab()],
                    'data' => [const PhoneDataTab()],
                    'quests' => _questsTab(),
                    'modules' => _modulesTab(),
                    'abilities' => _abilitiesTab(s),
                    'log' => _logTab(),
                    'evolution' => _evolutionTab(s),
                    _ => _statusTab(s),
                  }),
                ),
              ),
            ]),
    );
  }

  // ---------------- Status
  List<Widget> _statusTab(HesState s) {
    final open = _quests.where((q) => q['claimed'] != true).length;
    return [
      HudPanel(
        title: 'Status',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _kv('Title', '[$_title]', AssimilisBrand.violetSoft),
                _kv('Class', s.className, AssimilisBrand.text),
                const SizedBox(height: 8),
                Text('LEVEL', style: AssimilisBrand.label(10)),
                Text('${s.level}',
                    style: AssimilisBrand.display(40, w: FontWeight.w800)
                        .copyWith(shadows: [const Shadow(color: AssimilisBrand.violet, blurRadius: 16)])),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('RANK', style: AssimilisBrand.label(10)),
              const SizedBox(height: 4),
              RankBadge(s.rankName, size: 60),
              const SizedBox(height: 10),
              _right('Total power', s.powerValue.toStringAsFixed(1)),
              _right('Coins', '${s.coins}'),
              _right('AP', '${s.ap}'),
            ]),
          ]),
          const SizedBox(height: 8),
          HudBar(s.xpNext == 0 ? 0 : s.xp / s.xpNext, height: 8),
          const SizedBox(height: 4),
          Text('XP ${s.xp} / ${s.xpNext}', style: AssimilisBrand.label(11)),
          const Divider(height: 22),
          Row(children: [
            Expanded(child: Text("TODAY'S QUESTS ${_quests.length - open} / ${_quests.length}", style: AssimilisBrand.label(11, color: AssimilisBrand.text))),
            OutlinedButton(onPressed: () => setState(() => _tab = 'quests'), child: const Text('Open quests')),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      _quickLogBox(),
      for (final b in _store.data!.branches) ...[
        const SizedBox(height: 12),
        _branch(b, s),
      ],
    ];
  }

  Widget _branch(Map b, HesState s) {
    final stats = (b['stats'] as List).where((st) => s.assessed.contains(st['id'])).toList();
    if (stats.isEmpty) return const SizedBox.shrink();
    final values = [for (final st in stats) s.stats[st['id']] ?? 0.0];
    final avg = values.reduce((a, b) => a + b) / values.length;
    final r = rank(avg);
    return HudPanel(
      title: '${b['name']}',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(border: Border.all(color: AssimilisBrand.rankColor(r))),
        child: Text(r, style: AssimilisBrand.label(12, color: AssimilisBrand.rankColor(r))),
      ),
      child: Column(children: [
        if (stats.length >= 3)
          Center(
            child: RadarChart(
              labels: [for (final st in stats) '${st['name']}'],
              values: values,
              max: [25.0, ...values.map((v) => v * 1.25)].reduce((a, b) => a > b ? a : b),
              size: 230,
            ),
          ),
        for (var i = 0; i < stats.length; i++) _statRow(stats[i], values[i], s.caps[stats[i]['id']] ?? 100),
      ]),
    );
  }

  Widget _statRow(Map st, double v, double cap) {
    final r = rank(v);
    final col = AssimilisBrand.rankColor(r);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 40, child: Text('${st['short']}', style: AssimilisBrand.label(11, color: AssimilisBrand.text))),
        Expanded(child: HudBar(v / cap, color: col, height: 5)),
        SizedBox(width: 46, child: Text(v.toStringAsFixed(1), textAlign: TextAlign.right, style: AssimilisBrand.label(11, color: AssimilisBrand.text))),
        SizedBox(width: 36, child: Text(r, textAlign: TextAlign.right, style: AssimilisBrand.label(11, color: col, w: FontWeight.w800))),
      ]),
    );
  }

  Widget _quickLogBox() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _log,
          style: AssimilisBrand.body(14),
          onSubmitted: (_) => _quickLog(),
          decoration: InputDecoration(
            hintText: 'Quick log: "30 pushups", "studied 45 min", "slept 7 h"',
            prefixIcon: const Icon(Icons.bolt_rounded, color: AssimilisBrand.violet),
            suffixIcon: IconButton(onPressed: _quickLog, icon: const Icon(Icons.send_rounded, color: AssimilisBrand.violet)),
          ),
        ),
        if (_toast != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('[SYSTEM] $_toast', style: AssimilisBrand.label(11, color: AssimilisBrand.mint)),
          ),
      ]);

  Widget _kv(String k, String v, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(width: 56, child: Text(k.toUpperCase(), style: AssimilisBrand.label(10))),
          Text(v, style: AssimilisBrand.body(14, color: c, w: FontWeight.w600)),
        ]),
      );

  Widget _right(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(k.toUpperCase(), style: AssimilisBrand.label(10)),
          const SizedBox(width: 8),
          SizedBox(width: 56, child: Text(v, textAlign: TextAlign.right, style: AssimilisBrand.label(13, color: AssimilisBrand.text, w: FontWeight.w700))),
        ]),
      );

  // ---------------- Quests
  List<Widget> _questsTab() => [
        SystemQuestList(onChanged: _refresh),
        const HudHeader('Daily quests'),
        for (final q in _quests) _questTile(q),
        if (_quests.isEmpty) const HudNote('No quests. Pick trackers in MODULES.'),
        const SizedBox(height: 12),
        _quickLogBox(),
      ];

  Widget _questTile(Map<String, dynamic> q) {
    final done = (q['done'] as double) >= (q['target'] as double);
    final claimed = q['claimed'] == true;
    final col = claimed ? AssimilisBrand.green : done ? AssimilisBrand.violet : AssimilisBrand.faint;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HudPanel(
        accent: col,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(claimed ? Icons.verified_rounded : done ? Icons.check_circle_outline : Icons.radio_button_unchecked, color: col),
            const SizedBox(width: 10),
            Expanded(child: Text('${q['title']}', style: AssimilisBrand.body(14, w: FontWeight.w600))),
            if (!claimed)
              TextButton(
                onPressed: done
                    ? () async {
                        final r = await _store.claim(q);
                        setState(() => _toast = r);
                        _refresh();
                      }
                    : null,
                child: Text(done ? 'CLAIM' : '+20 XP', style: AssimilisBrand.label(11, color: done ? AssimilisBrand.violetSoft : AssimilisBrand.faint)),
              ),
          ]),
          const SizedBox(height: 6),
          HudBar((q['done'] as double) / (q['target'] as double), color: col, height: 4),
          const SizedBox(height: 4),
          Text('${(q['done'] as double).toStringAsFixed(0)} / ${(q['target'] as double).toStringAsFixed(0)} ${q['unit']}',
              style: AssimilisBrand.label(10)),
        ]),
      ),
    );
  }

  // ---------------- Modules
  List<Widget> _modulesTab() {
    final active = _store.activeModules.toSet();
    return [
      const HudHeader('Trackers'),
      for (final m in _store.data!.modules.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: HudPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            accent: active.contains(m['id']) ? AssimilisBrand.violet : AssimilisBrand.line,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: active.contains(m['id']),
              title: Text('${m['name']}', style: AssimilisBrand.body(14, w: FontWeight.w600)),
              subtitle: Text('${m['domain']} · ${m['kind']}${m['unit'] == null ? '' : ' · ${m['unit']}'}', style: AssimilisBrand.label(10)),
              onChanged: (v) async {
                v ? active.add(m['id']) : active.remove(m['id']);
                await _store.setModules(active.toList());
                _refresh();
              },
            ),
          ),
        ),
    ];
  }

  // ---------------- Abilities
  List<Widget> _abilitiesTab(HesState s) => [
        HudHeader('Abilities', trailing: Text('${s.ap} AP', style: AssimilisBrand.label(12, color: AssimilisBrand.violetSoft))),
        for (final a in _store.abilityDefs) _ability(a, s),
      ];

  Widget _ability(Map<String, dynamic> a, HesState s) {
    final owned = s.unlocked.contains(a['id']);
    final ready = !owned && _store.meets(a['requires'] as Map?, s);
    final col = owned ? AssimilisBrand.magenta : ready ? AssimilisBrand.violet : AssimilisBrand.line;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HudPanel(
        accent: col,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(owned ? Icons.auto_awesome : Icons.lock_outline_rounded, color: owned ? AssimilisBrand.magenta : AssimilisBrand.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${a['name']}', style: AssimilisBrand.body(14, w: FontWeight.w700)),
              Text('${a['desc'] ?? ''}', style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
              const SizedBox(height: 4),
              Text('${owned ? 'UNLOCKED' : a['requires_text'] ?? ''} · ${a['cost_ap'] ?? 1} AP', style: AssimilisBrand.label(10)),
            ]),
          ),
          if (!owned)
            FilledButton(
              onPressed: ready && s.ap >= ((a['cost_ap'] ?? 1) as num)
                  ? () async {
                      final r = await _store.unlock(a);
                      setState(() => _toast = r);
                      _refresh();
                    }
                  : null,
              child: const Text('Unlock'),
            ),
        ]),
      ),
    );
  }

  // ---------------- Log
  List<Widget> _logTab() {
    final ev = _store.events.reversed.take(80).toList();
    return [
      const HudHeader('Log'),
      for (final e in ev)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: HudPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            accent: e['status'] == 'applied' ? AssimilisBrand.violet : AssimilisBrand.line,
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${e['summary'] ?? e['module'] ?? e['kind']}',
                      style: AssimilisBrand.body(13,
                          color: e['status'] == 'applied' ? AssimilisBrand.text : AssimilisBrand.faint)),
                  Text(
                      '${DateTime.fromMillisecondsSinceEpoch(((e['at'] as num) * 1000).toInt()).toString().substring(0, 16)}'
                      ' · ${e['kind']}${e['quantity'] == null ? '' : ' · ${e['quantity']}'}${e['status'] == 'applied' ? '' : ' · undone'}',
                      style: AssimilisBrand.label(10)),
                ]),
              ),
              if (e['status'] == 'applied')
                IconButton(
                  tooltip: 'Undo',
                  icon: const Icon(Icons.undo_rounded, color: AssimilisBrand.muted, size: 20),
                  onPressed: () async {
                    await _store.undo('${e['id']}');
                    _refresh();
                  },
                ),
            ]),
          ),
        ),
      if (ev.isEmpty) const HudNote('Nothing logged yet.'),
    ];
  }

  // ---------------- Evolution
  List<Widget> _evolutionTab(HesState s) => [
        HudPanel(
          title: 'Evolution',
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            HudStat('Level', '${s.level}', color: AssimilisBrand.violetSoft),
            HudStat('Total XP', '${s.xpTotal}'),
            HudStat('Power', s.powerValue.toStringAsFixed(1)),
          ]),
        ),
        const HudHeader('Why did I get this XP?'),
        for (final x in s.xpLog.reversed.take(60))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(
                width: 64,
                child: Text('${(x['xp'] as int) > 0 ? '+' : ''}${x['xp']} XP',
                    style: AssimilisBrand.label(11, color: (x['xp'] as int) > 0 ? AssimilisBrand.mint : AssimilisBrand.red)),
              ),
              Expanded(child: Text('${x['why']}', style: AssimilisBrand.body(13))),
              Text('${x['day']}'.substring(5, 10), style: AssimilisBrand.label(10)),
            ]),
          ),
        if (s.xpLog.isEmpty) const HudNote('Claim quests and log activities to earn XP.'),
      ];
}
