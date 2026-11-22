import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'brand.dart';
import 'hud.dart';

/// Safety & Permissions: you decide what Assimilis Mobile may do.
/// * Every Android permission the app uses, each with its own Allow button, plus "Allow all".
/// * Phone Agent safety mode: "Ask me" (Allow/Deny on screen for risky actions) or "Full allow".
class PermissionsView extends StatefulWidget {
  const PermissionsView({super.key});

  @override
  State<PermissionsView> createState() => _PermissionsViewState();
}

class _Perm {
  final String title;
  final String why;
  final IconData icon;
  final Permission? permission; // null = special (opened in Android settings)
  final String? special;
  const _Perm(this.title, this.why, this.icon, {this.permission, this.special});
}

class _PermissionsViewState extends State<PermissionsView>
    with WidgetsBindingObserver {
  static const _agent = MethodChannel('com.privateagent/accessibility');

  static final _perms = <_Perm>[
    const _Perm(
      'Phone control (Accessibility)',
      'Read the screen, tap, type, scroll and open apps.',
      Icons.touch_app_rounded,
      special: 'accessibility',
    ),
    const _Perm(
      'Draw over other apps',
      'The floating Phone Agent bubble.',
      Icons.layers_rounded,
      permission: Permission.systemAlertWindow,
    ),
    const _Perm(
      'Microphone',
      'Voice commands and speech-to-text.',
      Icons.mic_rounded,
      permission: Permission.microphone,
    ),
    const _Perm(
      'Contacts',
      'Find people to call, text or email.',
      Icons.contacts_rounded,
      permission: Permission.contacts,
    ),
    const _Perm(
      'Phone calls',
      'Place calls.',
      Icons.call_rounded,
      permission: Permission.phone,
    ),
    const _Perm(
      'SMS',
      'Send text messages.',
      Icons.sms_rounded,
      permission: Permission.sms,
    ),
    const _Perm(
      'Notifications',
      'Task progress, downloads and image generation.',
      Icons.notifications_rounded,
      permission: Permission.notification,
    ),
    const _Perm(
      'Exact alarms',
      'Reminders, deadlines and quests on time.',
      Icons.alarm_on_rounded,
      permission: Permission.scheduleExactAlarm,
    ),
    const _Perm(
      'Camera',
      'Photos for vision models and QR codes.',
      Icons.photo_camera_rounded,
      permission: Permission.camera,
    ),
    const _Perm(
      'All files',
      'Import models and read/write documents in storage.',
      Icons.folder_rounded,
      permission: Permission.manageExternalStorage,
    ),
    const _Perm(
      'Run in background',
      'Keep local models and agents running (battery optimisation off).',
      Icons.battery_charging_full_rounded,
      permission: Permission.ignoreBatteryOptimizations,
    ),
    const _Perm(
      'Install apps',
      'Install app updates.',
      Icons.system_update_rounded,
      permission: Permission.requestInstallPackages,
    ),
    const _Perm(
      'Change system settings',
      'Brightness and other system controls.',
      Icons.settings_brightness_rounded,
      special: 'write_settings',
    ),
  ];

  final Map<String, bool> _granted = {};
  bool _fullAllow = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Android settings: re-check everything.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final g = <String, bool>{};
    for (final p in _perms) {
      if (p.permission != null) {
        g[p.title] = await p.permission!.isGranted;
      } else if (p.special == 'accessibility') {
        g[p.title] = await _call<bool>('isServiceRunning') ?? false;
      } else {
        g[p.title] =
            false; // Android gives no simple check for WRITE_SETTINGS here; button opens it.
      }
    }
    final full = await _call<bool>('getFullAllow') ?? false;
    if (mounted)
      setState(() {
        _granted
          ..clear()
          ..addAll(g);
        _fullAllow = full;
      });
  }

  Future<T?> _call<T>(String m, [Map<String, Object?>? a]) async {
    try {
      return await _agent.invokeMethod<T>(m, a);
    } catch (_) {
      return null;
    }
  }

  Future<void> _allow(_Perm p) async {
    if (p.special == 'accessibility') {
      await _call('openAccessibilitySettings');
    } else if (p.special == 'write_settings') {
      await const AndroidIntent(
        action: 'android.settings.action.MANAGE_WRITE_SETTINGS',
        data: 'package:com.assimilis.mobile',
      ).launch();
    } else {
      final s = await p.permission!.request();
      if (s.isPermanentlyDenied) await openAppSettings();
    }
    await _refresh();
  }

  Future<void> _allowAll() async {
    final runtime = _perms
        .where((p) => p.permission != null)
        .map((p) => p.permission!)
        .toList();
    await runtime.request();
    await _refresh();
    if (!(_granted['Phone control (Accessibility)'] ?? false)) {
      await _call('openAccessibilitySettings');
    }
  }

  Future<void> _setFullAllow(bool on) async {
    if (on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Turn on Full allow?'),
          content: const Text(
            'The Phone Agent will send, pay, delete, type passwords and run shell commands '
            'without asking you first. You can turn this off here at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Full allow'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _call('setFullAllow', {'on': on});
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return HudScaffold(
      title: 'Safety & Permissions',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _section('Phone Agent mode'),
          _card(
            Column(
              children: [
                RadioListTile<bool>(
                  value: false,
                  groupValue: _fullAllow,
                  onChanged: (_) => _setFullAllow(false),
                  activeColor: AssimilisBrand.violet,
                  title: const Text(
                    'Ask me',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Sending, paying, deleting, Enter, shell commands and banking apps '
                    'show Allow / Deny on screen first.',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
                RadioListTile<bool>(
                  value: true,
                  groupValue: _fullAllow,
                  onChanged: (_) => _setFullAllow(true),
                  activeColor: AssimilisBrand.violet,
                  title: const Text(
                    'Full allow',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'No prompts. The agent does everything it decides to do.',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _section('Android permissions')),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AssimilisBrand.violet,
                ),
                onPressed: _allowAll,
                icon: const Icon(Icons.done_all_rounded),
                label: const Text('Allow all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final p in _perms) _permTile(p),
        ],
      ),
    );
  }

  Widget _permTile(_Perm p) {
    final on = _granted[p.title] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _card(
        ListTile(
          leading: Icon(
            p.icon,
            color: on ? AssimilisBrand.violet : Colors.white54,
          ),
          title: Text(p.title, style: const TextStyle(color: Colors.white)),
          subtitle: Text(p.why, style: const TextStyle(color: Colors.white60)),
          trailing: on
              ? const Icon(
                  Icons.check_circle_rounded,
                  color: AssimilisBrand.violet,
                )
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AssimilisBrand.violet),
                  ),
                  onPressed: () => _allow(p),
                  child: const Text('Allow'),
                ),
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      t.toUpperCase(),
      style: const TextStyle(
        color: AssimilisBrand.violet,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    ),
  );

  Widget _card(Widget child) => HudPanel(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    child: child,
  );
}
