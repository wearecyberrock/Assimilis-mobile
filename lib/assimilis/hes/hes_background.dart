import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'hes_store.dart';
import 'hes_system.dart';
import 'hes_food.dart';
import 'phone_signals.dart';

/// The System's background workflow: every ~30 minutes Android wakes HES (even with the app closed) to sample your
/// location, fail missed quests, complete reached ones, and every few hours let the brain check in: a morning
/// briefing after you wake, check-ins through the day, and an evening review that writes the day's chronicle.
class HesBackground {
  static const task = 'hes-system-tick';

  static Future<void> start() async {
    await Workmanager().initialize(hesBackgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      'hes-system',
      task,
      frequency: const Duration(minutes: 30),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static int _min(String hhmm, int fallback) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm);
    return m == null ? fallback : int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  /// Why the brain should check in now, or null. Pure, so it is tested without a phone.
  static String? reasonAt(DateTime now, Map<String, dynamic> settings, Map<String, dynamic> answers) {
    final m = now.hour * 60 + now.minute;
    final today = '${now.year}-${now.month}-${now.day}';
    final quietStart = _min('${answers['quiet_start'] ?? '23:00'}', 23 * 60);
    final quietEnd = _min('${answers['quiet_end'] ?? answers['wake_time'] ?? '06:30'}', 6 * 60 + 30);
    final quiet = quietStart > quietEnd ? (m >= quietStart || m < quietEnd) : (m >= quietStart && m < quietEnd);
    if (quiet) return null;
    final wake = _min('${answers['wake_time'] ?? settings['wake_time'] ?? '06:30'}', 6 * 60 + 30);
    if (settings['last_morning'] != today && m >= wake && m < wake + 240) {
      return 'morning briefing: greet the player, look at sleep, alarm, calendar and yesterday, and issue today\'s quests';
    }
    if (settings['last_evening'] != today && m >= 21 * 60) {
      return 'evening review: judge today\'s quests, reward or penalise, and write today\'s chronicle chapter';
    }
    final last = (settings['last_think'] as num?)?.toInt() ?? 0;
    final every = ((settings['think_every_hours'] as num?) ?? 3).toDouble();
    if (now.millisecondsSinceEpoch ~/ 1000 - last >= every * 3600) {
      return 'check-in: react to what changed (location, health, calendar, screen time, progress)';
    }
    return null;
  }

  /// One background tick. Returns what it did (for logs and tests).
  static Future<String> tick({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final h = HesStore.instance;
    await h.load();
    final did = <String>[];
    if (await PhoneSignals.instance.sampleLocation() != null) did.add('location');
    final swept = await HesSystem.instance.sweep();
    if (swept.isNotEmpty) did.add('swept ${swept.length}');
    final answers = Map<String, dynamic>.from(((await HesSystem.instance.profile())['answers'] as Map?) ?? const {});
    final reason = h.settings['system_paused'] == true ? null : reasonAt(t, h.settings, answers);
    if (reason != null) {
      await HesSystem.instance.think(reason: reason);
      final today = '${t.year}-${t.month}-${t.day}';
      if (reason.startsWith('morning')) await h.setSetting('last_morning', today);
      if (reason.startsWith('evening')) await h.setSetting('last_evening', today);
      did.add(reason.split(':').first);
    }
    return did.isEmpty ? 'nothing' : did.join(', ');
  }
}

@pragma('vm:entry-point')
void hesBackgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    PhoneSignals.install();
    HesFood.install();
    try {
      await HesBackground.tick();
    } catch (_) {
      // Never let one bad tick stop the schedule.
    }
    return true;
  });
}
