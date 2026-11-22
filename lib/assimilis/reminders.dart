import 'dart:convert';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../phone_agent/services/alarm_service.dart';
import 'settings.dart';

/// A reminder: a notification at a time, once or repeating. Stored on the phone.
class Reminder {
  final int id;
  final String title;
  final DateTime at;
  final String repeat; // none | daily | weekly | weekdays
  final String source; // you | jarvis | hes
  Reminder({required this.id, required this.title, required this.at, this.repeat = 'none', this.source = 'you'});

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'at': at.toIso8601String(), 'repeat': repeat, 'source': source};
  static Reminder fromJson(Map<String, dynamic> j) => Reminder(
      id: j['id'], title: j['title'], at: DateTime.parse(j['at']), repeat: j['repeat'] ?? 'none', source: j['source'] ?? 'you');
}

/// Alarms (phone's Clock app), timers, and Assimilis reminders (scheduled notifications).
class Reminders {
  Reminders._();
  static final Reminders instance = Reminders._();
  final _n = FlutterLocalNotificationsPlugin();
  final _clock = AlarmService();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'assimilis_reminders',
    'Reminders',
    channelDescription: 'Assimilis reminders, deadlines and HES quests',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    color: null,
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final name = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('America/Jamaica'));
    }
    await _n.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _ready = true;
  }

  Future<List<Reminder>> list() async {
    final s = await AssimilisSettings.get();
    final raw = s.blob('reminders');
    if (raw == null) return [];
    final all = (jsonDecode(raw) as List).map((e) => Reminder.fromJson(Map<String, dynamic>.from(e))).toList();
    final now = DateTime.now();
    // Drop one-off reminders that already fired.
    return all.where((r) => r.repeat != 'none' || r.at.isAfter(now)).toList()..sort((a, b) => a.at.compareTo(b.at));
  }

  Future<void> _save(List<Reminder> all) async {
    final s = await AssimilisSettings.get();
    await s.setBlob('reminders', jsonEncode(all.map((r) => r.toJson()).toList()));
  }

  /// Schedule a reminder notification. Returns a confirmation sentence.
  Future<String> add(String title, DateTime at, {String repeat = 'none', String source = 'you'}) async {
    await init();
    final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 30);
    final r = Reminder(id: id, title: title, at: at, repeat: repeat, source: source);
    final when = tz.TZDateTime.from(at, tz.local);
    final android = await _n
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final exact = await android?.canScheduleExactNotifications() ?? false;
    await _n.zonedSchedule(
      id,
      'Assimilis reminder',
      title,
      when,
      const NotificationDetails(android: _channel),
      androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: switch (repeat) {
        'daily' => DateTimeComponents.time,
        'weekly' => DateTimeComponents.dayOfWeekAndTime,
        _ => null,
      },
    );
    if (repeat == 'weekdays') {
      // One weekly notification per weekday.
      for (var d = 1; d <= 5; d++) {
        var day = when;
        while (day.weekday != d || day.isBefore(tz.TZDateTime.now(tz.local))) {
          day = day.add(const Duration(days: 1));
        }
        await _n.zonedSchedule(id + d, 'Assimilis reminder', title, day, const NotificationDetails(android: _channel),
            androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime);
      }
    }
    final all = await list()..add(r);
    await _save(all);
    return 'Reminder set: "$title" ${_fmt(at)}${repeat == 'none' ? '' : ', $repeat'}.';
  }

  Future<String> cancel(int id) async {
    await init();
    await _n.cancel(id);
    for (var d = 1; d <= 5; d++) {
      await _n.cancel(id + d);
    }
    final all = await list();
    all.removeWhere((r) => r.id == id);
    await _save(all);
    return 'Reminder cancelled.';
  }

  /// Real alarm in the phone's Clock app (rings even in Do Not Disturb, per the Clock app).
  Future<String> alarm(int hour, int minute, {String? label}) =>
      _clock.setAlarm(hour: hour, minute: minute, label: label);

  Future<String> timer(int seconds, {String? label}) => _clock.setTimer(seconds: seconds, label: label);

  /// Open the Clock app's alarm list.
  Future<String> showAlarms() async {
    await const AndroidIntent(action: 'android.intent.action.SHOW_ALARMS').launch();
    return 'Opened your alarms.';
  }

  static String _fmt(DateTime d) {
    final now = DateTime.now();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final time = '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    if (sameDay) return 'today at $time';
    if (d.year == tomorrow.year && d.month == tomorrow.month && d.day == tomorrow.day) return 'tomorrow at $time';
    return 'on ${d.day}/${d.month} at $time';
  }
}
