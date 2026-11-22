import 'package:flutter/material.dart';

import '../../hub/brand.dart';
import 'hes_engine.dart';
import 'hes_store.dart';

/// HES: Human Efficiency System. Stats E→SSS+, level, quests, trackers, quick log.
class HesView extends StatefulWidget {
  const HesView({super.key});
  @override
  State<HesView> createState() => _HesViewState();
}

class _HesViewState extends State<HesView> {
  final _store = HesStore.instance;
  HesState? _s;
  List<Map<String, dynamic>> _quests = [];
  final _log = TextEditingController();
  String? _toast;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await _store.state();
    final q = await _store.quests();
    if (mounted) setState(() { _s = s; _quests = q; });
  }

  Future<void> _quickLog() async {
    final t = _log.text.trim();
    if (t.isEmpty) return;
    final r = await _store.quickLog(t);
    _log.clear();
    setState(() => _toast = r ?? 'No tracker matched "$t". Try "30 pushups" or "studied 45 min".');
    await _refresh();
  }

  static Color rankColor(String r) => switch (r) {
        'E' => Colors.grey,
        'D' => const Color(0xFF8BC34A),
        'C' => const Color(0xFF26C6DA),
        'B' => const Color(0xFF42A5F5),
        'A' => const Color(0xFFAB47BC),
        'S' => const Color(0xFFFFB300),
        'SS' => const Color(0xFFFF7043),
        _ => AssimilisBrand.magenta,
      };

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      backgroundColor: AssimilisBrand.navyDeep,
      appBar: AppBar(
        backgroundColor: AssimilisBrand.navyDeep,
        foregroundColor: Colors.white,
        title: const Text('HES · System'),
        actions: [IconButton(onPressed: _pickModules, icon: const Icon(Icons.tune_rounded), tooltip: 'Trackers')],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          border: Border.all(color: rankColor(s.rankName), width: 2),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(s.rankName,
                          style: TextStyle(color: rankColor(s.rankName), fontSize: 24, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Level ${s.level}',
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                        Text('${s.className} · Power ${s.powerValue}', style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: s.xpNext == 0 ? 0 : s.xp / s.xpNext,
                            minHeight: 8,
                            backgroundColor: Colors.white12,
                            color: AssimilisBrand.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('${s.xp} / ${s.xpNext} XP · ${s.coins} coins · ${s.ap} AP',
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ])),
                const SizedBox(height: 12),
                TextField(
                  controller: _log,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => _quickLog(),
                  decoration: InputDecoration(
                    hintText: 'Quick log: "30 pushups", "studied 45 min", "slept 7 h"',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: AssimilisBrand.navyRaised,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    suffixIcon: IconButton(
                        onPressed: _quickLog, icon: const Icon(Icons.send_rounded, color: AssimilisBrand.green)),
                  ),
                ),
                if (_toast != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('[SYSTEM] $_toast', style: const TextStyle(color: Color(0xFF7FD8B5))),
                  ),
                const SizedBox(height: 16),
                _title('Daily quests'),
                for (final q in _quests) _questTile(q),
                const SizedBox(height: 16),
                for (final b in _store.data!.branches) ...[
                  _title('${b['name']}'),
                  _panel(Column(children: [
                    for (final st in (b['stats'] as List))
                      if (s.assessed.contains(st['id'])) _statRow(st, s.stats[st['id']] ?? 0, s.caps[st['id']] ?? 100),
                  ])),
                  const SizedBox(height: 10),
                ],
              ]),
            ),
    );
  }

  Widget _statRow(Map st, double v, double cap) {
    final r = rank(v);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 44, child: Text('${st['short']}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: (v / cap).clamp(0, 1), minHeight: 6, backgroundColor: Colors.white10, color: rankColor(r)),
          ),
        ),
        SizedBox(width: 52, child: Text(v.toStringAsFixed(1), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white))),
        SizedBox(width: 42, child: Text(r, textAlign: TextAlign.right, style: TextStyle(color: rankColor(r), fontWeight: FontWeight.w800))),
      ]),
    );
  }

  Widget _questTile(Map<String, dynamic> q) {
    final done = (q['done'] as double) >= (q['target'] as double);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _panel(Row(children: [
        Icon(q['claimed'] == true ? Icons.verified_rounded : done ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            color: q['claimed'] == true || done ? AssimilisBrand.green : Colors.white38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${q['title']}', style: const TextStyle(color: Colors.white)),
            Text('${(q['done'] as double).toStringAsFixed(0)} / ${(q['target'] as double).toStringAsFixed(0)} ${q['unit']}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        if (q['claimed'] != true)
          TextButton(
            onPressed: done
                ? () async {
                    final r = await _store.claim(q);
                    setState(() => _toast = r);
                    _refresh();
                  }
                : null,
            child: Text(done ? 'Claim' : '+20 XP'),
          ),
      ])),
    );
  }

  Future<void> _pickModules() async {
    final d = _store.data!;
    final active = _store.activeModules.toSet();
    await showModalBottomSheet(
      context: context,
      backgroundColor: AssimilisBrand.navy,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SizedBox(
          height: MediaQuery.of(c).size.height * 0.75,
          child: ListView(children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Trackers', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final m in d.modules.values)
              CheckboxListTile(
                value: active.contains(m['id']),
                activeColor: AssimilisBrand.green,
                title: Text('${m['name']}', style: const TextStyle(color: Colors.white)),
                subtitle: Text('${m['domain']} · ${m['unit'] ?? ''}', style: const TextStyle(color: Colors.white54)),
                onChanged: (v) => set(() => v == true ? active.add(m['id']) : active.remove(m['id'])),
              ),
          ]),
        ),
      ),
    );
    await _store.setModules(active.toList());
    _refresh();
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: AssimilisBrand.green, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      );

  Widget _panel(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AssimilisBrand.navyRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x553D8C6E)),
        ),
        child: child,
      );
}
