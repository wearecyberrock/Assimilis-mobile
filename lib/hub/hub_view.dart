import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../assimilis/canvas/canvas_view.dart';
import '../assimilis/hes/hes_store.dart';
import '../assimilis/hes/hes_view.dart';
import '../assimilis/links/links_view.dart';
import '../assimilis/reach/reach_view.dart';
import '../assimilis/reminders.dart';
import '../assimilis/reminders_view.dart';
import '../assimilis/uwi/uwi_client.dart';
import '../assimilis/uwi/uwi_view.dart';
import '../assimilis/voice/voice_mode_view.dart';
import '../core/routes.dart';
import '../phone_agent/private_agent_main.dart' show PrivateAgentApp;
import '../views/cluster_view.dart';
import '../workstation/pocketstrike_main.dart' show PocketStrikeApp;
import 'brand.dart';
import 'core_view.dart';
import 'hud.dart';
import 'permissions_view.dart';

/// Whether the Phone Agent's own onboarding is finished (set in main.dart).
bool phoneAgentOnboarded = false;

/// Assimilis Mobile home: the Core, a status strip, and every part of the app.
class HubView extends StatefulWidget {
  const HubView({super.key});
  @override
  State<HubView> createState() => _HubViewState();
}

class _HubViewState extends State<HubView> {
  final _core = GlobalKey<CoreViewState>();
  String _rank = '–', _level = '–', _reminder = 'None set', _deadline = 'Sign in to UWI';

  @override
  void initState() {
    super.initState();
    _status();
  }

  Future<void> _status() async {
    try {
      final s = await HesStore.instance.state();
      _rank = s.rankName;
      _level = 'LV ${s.level}';
    } catch (_) {}
    try {
      final r = await Reminders.instance.list();
      if (r.isNotEmpty) _reminder = '${r.first.title} · ${_when(r.first.at)}';
    } catch (_) {}
    try {
      final u = await UwiClient.cached();
      final d = List<Map>.from(u?['deadlines'] ?? const [])
          .where((e) => DateTime.tryParse('${e['at']}')?.isAfter(DateTime.now()) ?? false)
          .toList()
        ..sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));
      if (d.isNotEmpty) _deadline = '${d.first['course']} · ${_when(DateTime.parse('${d.first['at']}'))}';
      else if (u != null) _deadline = 'Nothing due';
    } catch (_) {}
    if (mounted) setState(() {});
  }

  static String _when(DateTime d) {
    final diff = d.difference(DateTime.now());
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  Future<void> _go(Widget w) async {
    _core.currentState?.pause();
    await Get.to(() => Theme(data: AssimilisBrand.theme(), child: w));
    _core.currentState?.resume();
    _core.currentState?.refreshGraph();
    _status();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AssimilisBrand.theme(),
      child: Scaffold(
        backgroundColor: AssimilisBrand.graphite,
        body: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: GridBackdrop())),
          SafeArea(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              // Header: the Core
              GestureDetector(
                onTap: () => _go(const VoiceModeView()),
                child: Column(children: [
                  CoreView(key: _core, size: 250),
                  Text('ASSIMILIS',
                      style: AssimilisBrand.display(28, color: AssimilisBrand.text, w: FontWeight.w800).copyWith(
                          letterSpacing: 8, shadows: [const Shadow(color: AssimilisBrand.violet, blurRadius: 18)])),
                  const SizedBox(height: 4),
                  Text("HI, I'M A · TAP THE CORE TO TALK", style: AssimilisBrand.label(11, color: AssimilisBrand.violetSoft)),
                ]),
              ),
              const SizedBox(height: 18),
              // Status strip
              HudPanel(
                padding: const EdgeInsets.all(12),
                onTap: () => _go(const HesView()),
                child: Row(children: [
                  RankBadge(_rank, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('HES · $_level', style: AssimilisBrand.label(11, color: AssimilisBrand.text)),
                      const SizedBox(height: 6),
                      _line(Icons.notifications_active_outlined, _reminder),
                      const SizedBox(height: 3),
                      _line(Icons.school_outlined, _deadline),
                    ]),
                  ),
                ]),
              ),
              const HudHeader('Assimilis'),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.5,
                children: [
                  _tile(Icons.graphic_eq_rounded, 'Talk to A', 'Talk hands-free', AssimilisBrand.magenta, const VoiceModeView()),
                  _tile(Icons.draw_rounded, 'Canvas', 'Notes · maths · ink', AssimilisBrand.violet, const CanvasView()),
                  _tile(Icons.school_rounded, 'UWI', 'Courses · deadlines', AssimilisBrand.green, const UwiView()),
                  _tile(Icons.military_tech_rounded, 'HES', 'Stats · quests', const Color(0xFFFFB300), const HesView()),
                  _tile(Icons.alarm_rounded, 'Reminders', 'Alarms · timers', AssimilisBrand.red, const RemindersView()),
                  _tile(Icons.travel_explore_rounded, 'Reach', 'Web · GitHub · YouTube', const Color(0xFF26C6DA), const ReachView()),
                ],
              ),
              const HudHeader('Agents'),
              _row(Icons.chat_bubble_outline_rounded, 'Chat & Models', 'Local GGUF, image generation, cloud models',
                  () async { await Get.toNamed(AppRoutes.home); _status(); }),
              _row(Icons.hub_outlined, 'Workstation', 'ReAct agent, MCP, Hermes memory', () => _go(const PocketStrikeApp())),
              _row(Icons.phone_android_rounded, 'Phone Agent', 'Uses your phone for you',
                  () => _go(PrivateAgentApp(onboardingCompleted: phoneAgentOnboarded))),
              const HudHeader('System'),
              _row(Icons.memory_rounded, 'Devices & RAM', 'Pool phones and laptops to run bigger models', () => _go(const ClusterView())),
              _row(Icons.link_rounded, 'Models & Links', 'Shared models, Hermes on laptop/VPS, ChatGPT sign-in', () => _go(const LinksView())),
              _row(Icons.verified_user_outlined, 'Safety & Permissions', 'Ask me / Full allow, Android permissions', () => _go(const PermissionsView())),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _line(IconData i, String t) => Row(children: [
        Icon(i, size: 14, color: AssimilisBrand.muted),
        const SizedBox(width: 6),
        Expanded(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: AssimilisBrand.body(12, color: AssimilisBrand.muted))),
      ]);

  Widget _tile(IconData icon, String title, String sub, Color accent, Widget page) => HudPanel(
        accent: accent,
        padding: const EdgeInsets.all(12),
        onTap: () => _go(page),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 12)],
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const Spacer(),
          Text(title.toUpperCase(), style: AssimilisBrand.display(13, w: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AssimilisBrand.body(11, color: AssimilisBrand.muted)),
        ]),
      );

  Widget _row(IconData icon, String title, String sub, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: HudPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          onTap: onTap,
          child: Row(children: [
            Icon(icon, color: AssimilisBrand.violetSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AssimilisBrand.body(15, w: FontWeight.w600)),
                Text(sub, style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AssimilisBrand.faint),
          ]),
        ),
      );
}
