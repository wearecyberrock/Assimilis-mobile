import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/routes.dart';
import '../phone_agent/private_agent_main.dart' show PrivateAgentApp;
import '../workstation/pocketstrike_main.dart' show PocketStrikeApp;
import '../assimilis/canvas/canvas_view.dart';
import '../assimilis/hes/hes_view.dart';
import '../assimilis/reach/reach_view.dart';
import '../assimilis/reminders_view.dart';
import '../assimilis/uwi/uwi_view.dart';
import '../assimilis/voice/voice_mode_view.dart';
import 'brand.dart';
import 'permissions_view.dart';

/// Whether the Phone Agent's own onboarding is finished (set in main.dart).
bool phoneAgentOnboarded = false;

/// Assimilis Mobile home: one place to open each part of the merged app.
class HubView extends StatelessWidget {
  const HubView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AssimilisBrand.navy,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(AssimilisBrand.icon, width: 52, height: 52),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Assimilis',
                      style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                  Text('Mobile', style: TextStyle(color: AssimilisBrand.green, fontSize: 15)),
                ]),
              ),
              AssimilisBrand.mascotImage(size: 56),
            ]),
            const SizedBox(height: 24),
            _tile(
              icon: Icons.graphic_eq_rounded,
              title: 'Jarvis',
              body: 'Voice mode. Talk hands-free in the Jarvis voice; it sets alarms, writes notes, logs HES, '
                  'checks UWI deadlines, reads the web and works your phone.',
              onTap: () => Get.to(() => const VoiceModeView()),
            ),
            _tile(
              icon: Icons.draw_rounded,
              title: 'Canvas',
              body: 'Notebooks, sections and pages. LaTeX maths, calculator, graphs, derivatives, ink and note cards.',
              onTap: () => Get.to(() => const CanvasView()),
            ),
            _tile(
              icon: Icons.school_rounded,
              title: 'UWI · Academic',
              body: 'Mona VLE courses, deadlines and announcements. One tap turns a deadline into reminders.',
              onTap: () => Get.to(() => const UwiView()),
            ),
            _tile(
              icon: Icons.military_tech_rounded,
              title: 'HES',
              body: 'Human Efficiency System: stats E to SSS+, level, daily quests and trackers.',
              onTap: () => Get.to(() => const HesView()),
            ),
            _tile(
              icon: Icons.alarm_rounded,
              title: 'Alarms & Reminders',
              body: 'Clock alarms, timers, and repeating reminders.',
              onTap: () => Get.to(() => const RemindersView()),
            ),
            _tile(
              icon: Icons.travel_explore_rounded,
              title: 'Agent Reach',
              body: 'Read-only web search and readers: pages, GitHub, YouTube captions, Reddit, RSS.',
              onTap: () => Get.to(() => const ReachView()),
            ),
            _tile(
              icon: Icons.chat_bubble_rounded,
              title: 'Chat & Models',
              body: 'Local GGUF models, on-device image generation (Stable Diffusion), LiteRT, '
                  'and cloud models (OpenAI, Claude, Gemini, Kimi).',
              onTap: () => Get.toNamed(AppRoutes.home),
            ),
            _tile(
              icon: Icons.hub_rounded,
              title: 'Workstation',
              body: 'ReAct agent with tools, MCP servers, Hermes memory, files, more local and cloud '
                  'providers, image generation.',
              onTap: () => Get.to(() => const PocketStrikeApp()),
            ),
            _tile(
              icon: Icons.phone_android_rounded,
              title: 'Phone Agent',
              body: 'Tell it what to do and it uses your phone for you: reads the screen, taps, '
                  'types, opens apps. Voice and floating bubble.',
              onTap: () => Get.to(() => PrivateAgentApp(onboardingCompleted: phoneAgentOnboarded)),
            ),
            _tile(
              icon: Icons.verified_user_rounded,
              title: 'Safety & Permissions',
              body: 'Allow each permission, or all at once. Choose "Ask me" or "Full allow" for the Phone Agent.',
              onTap: () => Get.to(() => const PermissionsView()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AssimilisBrand.navyRaised,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AssimilisBrand.green.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AssimilisBrand.green),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(body, style: const TextStyle(color: Colors.white70, height: 1.35)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ]),
          ),
        ),
      ),
    );
  }
}
