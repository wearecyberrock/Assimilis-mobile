import 'package:flutter/material.dart';

import '../../hub/brand.dart';
import '../../hub/hud.dart';
import '../canvas/notes_store.dart';
import '../links/model_gateway.dart';
import 'team_engine.dart';

/// Team task runner UI: starts ONLY when the user taps "Start team task".
/// Lets the user configure roles (Manager, Worker, Checker, Researcher, Phone Operator),
/// per-role model overrides, and Workstation / Phone Agent / A2A permissions.
class TeamTaskSection extends StatefulWidget {
  const TeamTaskSection({super.key});
  @override
  State<TeamTaskSection> createState() => _TeamTaskSectionState();
}

class _TeamTaskSectionState extends State<TeamTaskSection> {
  final _goal = TextEditingController();
  final _roles = TeamEngine.defaultRoles();
  bool _allowWorkstation = true;
  bool _allowPhone = true;
  bool _allowA2a = true;
  bool _running = false;
  final _liveSteps = <TeamStep>[];
  TeamTaskRun? _activeRun;
  List<TeamTaskRun> _history = [];
  String? _toast;

  @override
  void initState() {
    super.initState();
    TeamEngine.instance.history().then((h) {
      if (mounted) setState(() => _history = h);
    });
  }

  @override
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  Future<void> _pickModel(TeamRole role) async {
    final models = await ModelGateway.instance.models();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AssimilisBrand.panel,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
          Text('${role.name.toUpperCase()} MODEL', style: AssimilisBrand.label(11, color: AssimilisBrand.violetSoft)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.auto_awesome_rounded, color: AssimilisBrand.violetSoft),
            title: const Text('Default (from Settings)'),
            subtitle: Text('Uses ${role.agentKey} assignment or A\'s brain', style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
            onTap: () => Navigator.pop(ctx, '__default__'),
          ),
          for (final m in models)
            ListTile(
              leading: const Icon(Icons.memory_rounded, size: 18, color: AssimilisBrand.muted),
              title: Text(m, style: AssimilisBrand.label(12, color: AssimilisBrand.text)),
              onTap: () => Navigator.pop(ctx, m),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      role.modelOverride = picked == '__default__' ? null : picked;
    });
  }

  Future<void> _start() async {
    final g = _goal.text.trim();
    if (g.isEmpty || _running) return;
    setState(() {
      _running = true;
      _liveSteps.clear();
      _activeRun = null;
      _toast = null;
    });
    final run = await TeamEngine.instance.runTask(
      goal: g,
      roles: _roles,
      allowWorkstation: _allowWorkstation,
      allowPhoneAgent: _allowPhone,
      allowA2a: _allowA2a,
      onStep: (s) {
        if (mounted) setState(() => _liveSteps.add(s));
      },
    );
    final hist = await TeamEngine.instance.history();
    if (!mounted) return;
    setState(() {
      _running = false;
      _activeRun = run;
      _history = hist;
    });
  }

  Future<void> _saveToCanvas(TeamTaskRun run) async {
    final store = NotesStore.instance;
    await store.load();
    final trace = run.steps.map((s) => '- **${s.roleName}** (${s.kind}): ${s.summary}').join('\n');
    final body = '# Team Report\n\n**Goal:** ${run.goal}\n\n## Result\n\n${run.finalAnswer}\n\n## Trace\n\n$trace';
    final title = run.goal.length > 40 ? '${run.goal.substring(0, 40)}…' : run.goal;
    await store.quickNote(title, body, book: 'Team', section: 'Reports');
    if (mounted) setState(() => _toast = 'Saved report to Canvas (Team › Reports).');
  }

  Color _roleColor(String roleId) => switch (roleId) {
        'manager' => AssimilisBrand.violetSoft,
        'worker' => AssimilisBrand.mint,
        'checker' => const Color(0xFFFFB300),
        'workstation' => const Color(0xFF38BDF8),
        'operator' => AssimilisBrand.magenta,
        'system' => AssimilisBrand.red,
        _ => AssimilisBrand.violet,
      };

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HudPanel(
        title: 'Team task (on demand)',
        trailing: Text(_running ? 'ACTIVE' : 'IDLE',
            style: AssimilisBrand.label(10, color: _running ? AssimilisBrand.mint : AssimilisBrand.faint)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'Team agents only run when you start a task here. The Manager delegates subtasks, hands jobs to Workstation/Phone/A2A, and the Checker verifies the result.',
            style: AssimilisBrand.body(12, color: AssimilisBrand.muted),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _goal,
            maxLines: 3,
            minLines: 2,
            enabled: !_running,
            decoration: const InputDecoration(
              hintText: 'e.g. Research quantum error correction, plot the threshold curve on Canvas, and verify the summary',
            ),
          ),
          const SizedBox(height: 10),
          Text('ROLES (TAP TO TOGGLE · LONG-PRESS FOR MODEL)', style: AssimilisBrand.label(10)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in _roles)
              GestureDetector(
                onLongPress: _running ? null : () => _pickModel(r),
                child: FilterChip(
                  selected: r.enabled,
                  onSelected: _running || r.id == 'manager'
                      ? null
                      : (v) => setState(() => r.enabled = v),
                  label: Text(
                    r.modelOverride == null ? r.name : '${r.name} · ${r.modelOverride!.split('/').last}',
                    style: AssimilisBrand.label(11, color: r.enabled ? AssimilisBrand.text : AssimilisBrand.muted),
                  ),
                  selectedColor: _roleColor(r.id).withValues(alpha: 0.22),
                  side: BorderSide(color: r.enabled ? _roleColor(r.id) : AssimilisBrand.line),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Text('TOOLS & AGENTS', style: AssimilisBrand.label(10)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            FilterChip(
              label: const Text('Workstation'),
              selected: _allowWorkstation,
              onSelected: _running ? null : (v) => setState(() => _allowWorkstation = v),
            ),
            FilterChip(
              label: const Text('Phone Agent'),
              selected: _allowPhone,
              onSelected: _running ? null : (v) => setState(() => _allowPhone = v),
            ),
            FilterChip(
              label: const Text('Nearby A2A'),
              selected: _allowA2a,
              onSelected: _running ? null : (v) => setState(() => _allowA2a = v),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _running ? null : _start,
                icon: Icon(_running ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded),
                label: Text(_running ? 'Team working…' : 'Start team task'),
              ),
            ),
            if (_running) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => TeamEngine.instance.cancel(),
                icon: const Icon(Icons.stop_rounded, color: AssimilisBrand.red),
                label: const Text('Stop'),
              ),
            ],
          ]),
          if (_toast != null) ...[
            const SizedBox(height: 8),
            Text(_toast!, style: AssimilisBrand.body(12, color: AssimilisBrand.mint)),
          ],
        ]),
      ),
      if (_liveSteps.isNotEmpty || _activeRun != null) ...[
        const HudHeader('Live transcript'),
        HudPanel(
          accent: _activeRun?.status == 'error' ? AssimilisBrand.red : AssimilisBrand.mint,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final s in _liveSteps)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _roleColor(s.roleId).withValues(alpha: 0.18),
                      border: Border.all(color: _roleColor(s.roleId).withValues(alpha: 0.6)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(s.roleName.toUpperCase(), style: AssimilisBrand.label(9, color: _roleColor(s.roleId))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s.summary, style: AssimilisBrand.body(12, color: AssimilisBrand.text)),
                  ),
                ]),
              ),
            if (_activeRun != null && _activeRun!.finalAnswer.isNotEmpty) ...[
              const Divider(height: 18),
              Row(children: [
                Expanded(child: Text('FINAL RESULT', style: AssimilisBrand.label(11, color: AssimilisBrand.mint))),
                TextButton.icon(
                  onPressed: () => _saveToCanvas(_activeRun!),
                  icon: const Icon(Icons.note_add_outlined, size: 16),
                  label: const Text('Save to Canvas'),
                ),
              ]),
              const SizedBox(height: 4),
              SelectableText(_activeRun!.finalAnswer, style: AssimilisBrand.body(13)),
            ],
          ]),
        ),
      ],
      if (_history.isNotEmpty) ...[
        HudHeader(
          'Recent team runs',
          trailing: TextButton(
            onPressed: () async {
              await TeamEngine.instance.clearHistory();
              if (mounted) setState(() => _history = []);
            },
            child: const Text('Clear'),
          ),
        ),
        for (final r in _history.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: HudPanel(
              padding: EdgeInsets.zero,
              accent: r.status == 'done' ? AssimilisBrand.violet : AssimilisBrand.red,
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(r.goal, maxLines: 1, overflow: TextOverflow.ellipsis, style: AssimilisBrand.body(13, w: FontWeight.w600)),
                subtitle: Text('${r.rolesUsed.join(' · ')} · ${r.steps.length} steps · ${r.status}',
                    style: AssimilisBrand.label(10)),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(r.finalAnswer, style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _saveToCanvas(r),
                      icon: const Icon(Icons.note_add_outlined, size: 15),
                      label: const Text('Save to Canvas'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ]);
  }
}
