import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';

import '../assimilis/a2a/devices_view.dart';
import '../assimilis/canvas/canvas_view.dart';
import '../assimilis/hes/hes_view.dart';
import '../assimilis/links/agent_models.dart';
import '../assimilis/links/links_view.dart';
import '../assimilis/reach/reach_view.dart';
import '../assimilis/reminders_view.dart';
import '../assimilis/settings.dart';
import '../assimilis/sync/qr_connect_view.dart';
import '../assimilis/team/team_view.dart';
import '../assimilis/uwi/vle_view.dart';
import '../assimilis/voice/voice_mode_view.dart';
import '../assimilis/whatsapp/whatsapp_view.dart';
import '../core/routes.dart';
import '../phone_agent/private_agent_main.dart' show PrivateAgentApp;
import '../views/cluster_view.dart';
import '../workstation/pocketstrike_main.dart' show PocketStrikeApp;
import 'brand.dart';
import 'core_orb.dart';
import 'core_view.dart';
import 'hub_view.dart' show phoneAgentOnboarded;
import 'hud.dart';
import 'permissions_view.dart';
import 'welcome_view.dart';

/// Assimilis Mobile's home: five sections (HES, Canvas, Agents, Team, Settings) and the Core, which is always one tap
/// away for talking to A. HES opens first: it is the centre of the app.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initial = 0});
  final int initial;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _tab = widget.initial;
  // Each section is built the first time it is opened, then kept (its state survives switching tabs).
  final _built = <int, Widget>{};

  static const _tabs = [
    (Icons.military_tech_rounded, 'HES'),
    (Icons.draw_rounded, 'Canvas'),
    (Icons.smart_toy_outlined, 'Agents'),
    (Icons.groups_2_outlined, 'Team'),
    (Icons.tune_rounded, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _firstRun();
  }

  Future<void> _firstRun() async {
    // Every agent gets the Assimilis tools: the Workstation through MCP.
    try {
      unawaited(AgentModels.ensureWorkstationTools(ProviderScope.containerOf(context, listen: false)));
    } catch (_) {}
    final s = await AssimilisSettings.get();
    if (s.onboarded || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const WelcomeView()));
  }

  Widget _section(int i) => _built.putIfAbsent(i, () => switch (i) {
        0 => const HesView(),
        1 => const CanvasView(),
        2 => const AgentsView(),
        3 => const TeamView(),
        _ => const SettingsHubView(),
      });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AssimilisBrand.theme(),
      child: Scaffold(
        backgroundColor: AssimilisBrand.graphite,
        body: IndexedStack(
          index: _tab,
          children: [for (var i = 0; i < _tabs.length; i++) _built.containsKey(i) || i == _tab ? _section(i) : const SizedBox.shrink()],
        ),
        floatingActionButton: _tab == 1
            ? null // the canvas has its own tools in that corner
            : Semantics(
                button: true,
                label: 'Talk to A',
                child: GestureDetector(
                  onTap: () => Get.to(() => Theme(data: AssimilisBrand.theme(), child: const VoiceModeView())),
                  child: const SizedBox(width: 64, height: 64, child: CoreOrb(size: 64)),
                ),
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          backgroundColor: AssimilisBrand.panel,
          indicatorColor: AssimilisBrand.violet.withValues(alpha: 0.22),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            for (final t in _tabs)
              NavigationDestination(icon: Icon(t.$1, color: AssimilisBrand.muted), selectedIcon: Icon(t.$1, color: AssimilisBrand.violetSoft), label: t.$2),
          ],
        ),
      ),
    );
  }
}

/// Opens a page in the Assimilis theme.
Future<void> openPage(Widget w) async {
  await Get.to(() => Theme(data: AssimilisBrand.theme(), child: w));
}

Widget sectionRow(IconData icon, String title, String sub, VoidCallback onTap, {Widget? trailing}) => Padding(
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
          trailing ?? const Icon(Icons.chevron_right_rounded, color: AssimilisBrand.faint),
        ]),
      ),
    );

Widget _page(String title, String subtitle, List<Widget> children) => Stack(children: [
      const Positioned.fill(child: CustomPaint(painter: GridBackdrop())),
      SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
          Text(title.toUpperCase(),
              style: AssimilisBrand.display(22, w: FontWeight.w800).copyWith(letterSpacing: 4, shadows: [const Shadow(color: AssimilisBrand.violet, blurRadius: 14)])),
          const SizedBox(height: 4),
          Text(subtitle, style: AssimilisBrand.body(13, color: AssimilisBrand.muted)),
          const SizedBox(height: 14),
          ...children,
        ]),
      ),
    ]);

/// The agents: A (Assimilis) and the three agents, each with its own models and keys (shared in Settings).
class AgentsView extends StatelessWidget {
  const AgentsView({super.key});
  @override
  Widget build(BuildContext context) => _page('Agents', 'A and the three agents. Each has its own model; share them in Settings.', [
        GestureDetector(
          onTap: () => openPage(const VoiceModeView()),
          child: const Center(child: CoreView(size: 200)),
        ),
        const SizedBox(height: 8),
        sectionRow(Icons.graphic_eq_rounded, 'A (Assimilis)', 'Talk hands-free; A runs HES and the team', () => openPage(const VoiceModeView())),
        const HudHeader('The three agents'),
        sectionRow(Icons.chat_bubble_outline_rounded, 'Chat & Models', 'Local models, image generation, cloud models',
            () => Get.toNamed(AppRoutes.home)),
        sectionRow(Icons.hub_outlined, 'Workstation', 'Agent with tools, MCP servers and memory', () => openPage(const PocketStrikeApp())),
        sectionRow(Icons.phone_android_rounded, 'Phone Agent', 'Uses your phone for you: taps, types, opens apps',
            () => openPage(PrivateAgentApp(onboardingCompleted: phoneAgentOnboarded))),
      ]);
}

/// Team: the agents working together on demand (manager, worker, checker and other roles), plus A2A, QR sync and RAM pool.
class TeamView extends StatelessWidget {
  const TeamView({super.key});
  @override
  Widget build(BuildContext context) => _page('Team', 'Start a team task with roles, or coordinate nearby devices.', [
        const TeamTaskSection(),
        const HudHeader('Devices & network'),
        sectionRow(Icons.qr_code_2_rounded, 'QR Connect & Sync', 'Connect HES devices, other players, and sync with desktop / VPS',
            () => openPage(const QrConnectView())),
        sectionRow(Icons.hub_rounded, "Nearby A's", 'Talk to A on your other devices and pass jobs around', () => openPage(const DevicesView())),
        sectionRow(Icons.memory_rounded, 'Devices & RAM', 'Pool phones and laptops to run bigger models', () => openPage(const ClusterView())),
      ]);
}

/// Settings: every agent's models and keys in one place, plus the phone's permissions, channels and shared tools.
class SettingsHubView extends StatelessWidget {
  const SettingsHubView({super.key});
  @override
  Widget build(BuildContext context) => _page('Settings', 'Models, keys, permissions, channels and the tools every agent shares.', [
        sectionRow(Icons.psychology_alt_rounded, 'Models & keys', "Every agent's models and API keys; share them between agents", () => openPage(const LinksView())),
        sectionRow(Icons.verified_user_outlined, 'Safety & Permissions', 'Ask me / Full allow, and Android permissions', () => openPage(const PermissionsView())),
        sectionRow(Icons.chat_rounded, 'WhatsApp', 'Link a spare agent number with a pairing code and set a receiver number', () => openPage(const WhatsAppView())),
        sectionRow(Icons.school_rounded, 'UWI Mona VLE', 'Multi-user encrypted VLE scanner (courses, deadlines, resources, news)', () => openPage(const VleView())),
        sectionRow(Icons.qr_code_2_rounded, 'QR Connect & Sync', 'Pair HES across your devices, other players, desktop or VPS', () => openPage(const QrConnectView())),
        sectionRow(Icons.travel_explore_rounded, 'Agent Reach', 'Web search and readers every agent can use', () => openPage(const ReachView())),
        sectionRow(Icons.alarm_rounded, 'Alarms & Reminders', 'Alarms, timers and reminders', () => openPage(const RemindersView())),
      ]);
}
