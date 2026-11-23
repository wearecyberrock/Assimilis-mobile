import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

import 'hes_store.dart';
import 'hes_system.dart';

/// What the phone knows about your day, for the HES System and every agent:
/// sleep, steps, workouts, heart rate and weight from Health Connect (Google Fit, smartwatches and other apps write
/// there); the phone's calendars, including Google calendars synced to the phone (read and write); the next alarm;
/// screen time; and a location history HES keeps itself (sampled in the background).
class PhoneSignals {
  PhoneSignals._();
  static final PhoneSignals instance = PhoneSignals._();

  static const _ch = MethodChannel('com.assimilis/phone_data');
  final _health = Health();
  bool _healthConfigured = false;

  static const healthTypes = [
    HealthDataType.STEPS,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.WORKOUT,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WEIGHT,
    HealthDataType.NUTRITION,
  ];

  /// Hooks the System's context and tools up. Call once at start-up (also in the background isolate).
  static void install() {
    HesSystem.contextProviders['phone'] = () => instance.snapshot();
    HesSystem.plugins['phone'] = (schemas, runTool);
  }

  // ── connecting (permissions) ──────────────────────────────────────────────────────────────────────

  /// Asks for what HES needs. Returns what is connected.
  Future<Map<String, bool>> connect({bool calendar = true, bool location = true, bool health = true, bool screenTime = true}) async {
    final out = <String, bool>{};
    if (calendar) out['calendar'] = (await Permission.calendarFullAccess.request()).isGranted;
    if (location) {
      final fg = await Permission.locationWhenInUse.request();
      out['location'] = fg.isGranted;
      // Background location lets HES keep your location history when the app is closed (asked separately by Android).
      if (fg.isGranted) out['location_background'] = (await Permission.locationAlways.request()).isGranted;
    }
    if (health) out['health'] = await connectHealth();
    if (screenTime) {
      out['screen_time'] = await _ch.invokeMethod<bool>('usageGranted') ?? false;
      if (!out['screen_time']!) await _ch.invokeMethod('openUsageAccess');
    }
    await HesStore.instance.setSetting('signals_connected', out);
    return out;
  }

  /// Health Connect: installs it if missing, then asks for read access (and writing meals for food photos).
  Future<bool> connectHealth() async {
    try {
      await _configure();
      final st = await _health.getHealthConnectSdkStatus();
      if (st != HealthConnectSdkStatus.sdkAvailable) {
        await _health.installHealthConnect();
        return false;
      }
      await Permission.activityRecognition.request();
      final perms = [for (final t in healthTypes) t == HealthDataType.NUTRITION ? HealthDataAccess.READ_WRITE : HealthDataAccess.READ];
      final ok = await _health.requestAuthorization(healthTypes, permissions: perms);
      if (ok) await _health.requestHealthDataInBackgroundAuthorization();
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> _configure() async {
    if (_healthConfigured) return;
    await _health.configure();
    _healthConfigured = true;
  }

  Future<T?> _safe<T>(Future<T?> Function() f) async {
    try {
      return await f().timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  // ── reading ───────────────────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> nextAlarm() => _safe(() async {
        final r = await _ch.invokeMapMethod<String, dynamic>('nextAlarm');
        if (r == null) return null;
        return {'at': DateTime.fromMillisecondsSinceEpoch((r['at'] as num).toInt()).toIso8601String(), 'app': r['package']};
      });

  Future<Map<String, dynamic>?> screenTime() => _safe(() => _ch.invokeMapMethod<String, dynamic>('usageToday'));

  Future<List<Map<String, dynamic>>> calendars() async =>
      [for (final c in await _ch.invokeListMethod<Map>('calendars') ?? const []) Map<String, dynamic>.from(c)];

  Future<List<Map<String, dynamic>>> events(DateTime start, DateTime end) async => [
        for (final e in await _ch.invokeListMethod<Map>('events', {'start': start.millisecondsSinceEpoch, 'end': end.millisecondsSinceEpoch}) ??
            const [])
          {
            ...Map<String, dynamic>.from(e),
            'start': DateTime.fromMillisecondsSinceEpoch((e['start'] as num).toInt()).toIso8601String(),
            'end': DateTime.fromMillisecondsSinceEpoch((e['end'] as num).toInt()).toIso8601String(),
          }
      ];

  Future<int> addEvent(String title, DateTime start, DateTime end,
          {String? description, String? location, int? calendarId, bool allDay = false, int? remindMinutes}) async =>
      (await _ch.invokeMethod<int>('addEvent', {
        'title': title,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'all_day': allDay,
        if (description != null) 'description': description,
        if (location != null) 'location': location,
        if (calendarId != null) 'calendar_id': calendarId,
        if (remindMinutes != null) 'remind_minutes': remindMinutes,
      }))!;

  Future<bool> deleteEvent(int id) async => await _ch.invokeMethod<bool>('deleteEvent', {'id': id}) ?? false;

  /// Sleep, steps, workouts, heart rate and weight for the last [days] days.
  Future<Map<String, dynamic>?> healthSummary({int days = 1}) => _safe(() async {
        await _configure();
        final now = DateTime.now();
        final start = now.subtract(Duration(days: days, hours: 12));
        final pts = await _health.getHealthDataFromTypes(types: healthTypes, startTime: start, endTime: now);
        num sum(HealthDataType t) =>
            pts.where((p) => p.type == t).fold<num>(0, (a, p) => a + (p.value is NumericHealthValue ? (p.value as NumericHealthValue).numericValue : 0));
        final sleeps = pts.where((p) => p.type == HealthDataType.SLEEP_SESSION).toList()..sort((a, b) => b.dateTo.compareTo(a.dateTo));
        final hr = pts.where((p) => p.type == HealthDataType.HEART_RATE).map((p) => (p.value as NumericHealthValue).numericValue).toList();
        final weight = pts.where((p) => p.type == HealthDataType.WEIGHT).toList()..sort((a, b) => b.dateTo.compareTo(a.dateTo));
        final midnight = DateTime(now.year, now.month, now.day);
        int? stepsToday;
        try {
          stepsToday = await _health.getTotalStepsInInterval(midnight, now);
        } catch (_) {}
        return {
          'steps_today': stepsToday ?? sum(HealthDataType.STEPS).round(),
          if (sleeps.isNotEmpty)
            'last_sleep': {
              'from': sleeps.first.dateFrom.toIso8601String(),
              'to': sleeps.first.dateTo.toIso8601String(),
              'hours': (sleeps.first.dateTo.difference(sleeps.first.dateFrom).inMinutes / 60).toStringAsFixed(1),
            },
          'workouts': [
            for (final w in pts.where((p) => p.type == HealthDataType.WORKOUT).take(10))
              {
                'from': w.dateFrom.toIso8601String(),
                'minutes': w.dateTo.difference(w.dateFrom).inMinutes,
                'what': (w.toJson()['value'] as Map?)?['workoutActivityType'] ?? 'workout',
                'source': w.sourceName,
              }
          ],
          'active_kcal': sum(HealthDataType.ACTIVE_ENERGY_BURNED).round(),
          if (hr.isNotEmpty) 'heart_rate': {'min': hr.reduce(math.min), 'max': hr.reduce(math.max), 'avg': (hr.reduce((a, b) => a + b) / hr.length).round()},
          if (weight.isNotEmpty) 'weight_kg': (weight.first.value as NumericHealthValue).numericValue,
          'sources': {for (final p in pts) p.sourceName}.toList(),
        };
      });

  /// Logs a meal to Health Connect (from a food photo) so other health apps see it too.
  Future<bool> writeMeal(String name, {double? kcal, double? protein, double? carbs, double? fat, DateTime? at}) async {
    try {
      await _configure();
      final t = at ?? DateTime.now();
      final h = t.hour;
      final type = h < 11 ? MealType.BREAKFAST : (h < 16 ? MealType.LUNCH : (h < 21 ? MealType.DINNER : MealType.SNACK));
      return await _health.writeMeal(
          mealType: type, startTime: t, endTime: t.add(const Duration(minutes: 1)), name: name, caloriesConsumed: kcal, protein: protein, carbohydrates: carbs, fatTotal: fat);
    } catch (_) {
      return false;
    }
  }

  // ── location history (kept by HES) ────────────────────────────────────────────────────────────────

  /// Takes one location sample (background task and app start). Skips it if it barely moved within 10 minutes.
  Future<Map<String, dynamic>?> sampleLocation() async {
    final r = await _safe(() => _ch.invokeMapMethod<String, dynamic>('lastLocation'));
    if (r == null) return null;
    await HesStore.instance.load();
    final list = [for (final x in (HesStore.instance.get('location_history') as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    final p = {'t': (r['time'] as num).toInt() ~/ 1000, 'lat': r['lat'], 'lon': r['lon'], 'acc': r['accuracy']};
    if (list.isNotEmpty) {
      final last = list.last;
      if (last['t'] == p['t']) return null;
      if (_meters(last, p) < 60 && (p['t'] as int) - (last['t'] as int) < 600) return null;
    }
    list.add(p);
    await HesStore.instance.put('location_history', list.length > 4000 ? list.sublist(list.length - 4000) : list);
    return p;
  }

  static double _meters(Map a, Map b) {
    const r = 6371000.0;
    double rad(num d) => d * math.pi / 180;
    final dLat = rad((b['lat'] as num) - (a['lat'] as num)), dLon = rad((b['lon'] as num) - (a['lon'] as num));
    final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a['lat'] as num)) * math.cos(rad(b['lat'] as num)) * math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  /// Places you spend time (grid cells of ~150 m), with how often you are there by time of day, and today's trail.
  Future<Map<String, dynamic>> locationSummary({int days = 14}) async {
    await HesStore.instance.load();
    final since = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch ~/ 1000;
    final pts = [
      for (final x in (HesStore.instance.get('location_history') as List? ?? const []))
        if (((x as Map)['t'] as num) >= since) Map<String, dynamic>.from(x)
    ];
    final cells = <String, Map<String, dynamic>>{};
    for (final p in pts) {
      final key = '${((p['lat'] as num) * 700).round()},${((p['lon'] as num) * 700).round()}';
      final c = cells.putIfAbsent(key, () => {'lat': p['lat'], 'lon': p['lon'], 'samples': 0, 'night': 0, 'weekday_day': 0, 'days': <String>{}});
      final t = DateTime.fromMillisecondsSinceEpoch((p['t'] as int) * 1000);
      c['samples'] = (c['samples'] as int) + 1;
      if (t.hour >= 22 || t.hour < 6) c['night'] = (c['night'] as int) + 1;
      if (t.weekday <= 5 && t.hour >= 8 && t.hour < 17) c['weekday_day'] = (c['weekday_day'] as int) + 1;
      (c['days'] as Set<String>).add('${t.year}-${t.month}-${t.day}');
    }
    final places = cells.values.toList()..sort((a, b) => (b['samples'] as int).compareTo(a['samples'] as int));
    String guess(Map c) => (c['night'] as int) > (c['samples'] as int) / 3
        ? 'probably home'
        : ((c['weekday_day'] as int) > (c['samples'] as int) / 2 ? 'probably school or work' : 'visited');
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day).millisecondsSinceEpoch ~/ 1000;
    return {
      'samples': pts.length,
      'places': [
        for (final c in places.take(8))
          {
            'lat': (c['lat'] as num).toStringAsFixed(4),
            'lon': (c['lon'] as num).toStringAsFixed(4),
            'days_seen': (c['days'] as Set).length,
            'guess': guess(c),
          }
      ],
      'today': [
        for (final p in pts.where((p) => (p['t'] as int) >= todayStart).take(60))
          {
            'at': DateTime.fromMillisecondsSinceEpoch((p['t'] as int) * 1000).toIso8601String().substring(11, 16),
            'lat': (p['lat'] as num).toStringAsFixed(4),
            'lon': (p['lon'] as num).toStringAsFixed(4),
          }
      ],
    };
  }

  // ── what the System sees ──────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> snapshot() async {
    final now = DateTime.now();
    final out = <String, dynamic>{};
    final alarm = await nextAlarm();
    if (alarm != null) out['next_alarm'] = alarm;
    final st = await screenTime();
    if (st != null && st['granted'] == true) {
      out['screen_time_today'] = {'total_minutes': st['total_minutes'], 'top': (st['apps'] as List).take(5).toList()};
    }
    final cal = await _safe(() => events(now, now.add(const Duration(days: 7))));
    if (cal != null) {
      out['calendar_next_7_days'] = [for (final e in cal.take(25)) {'title': e['title'], 'start': e['start'], 'end': e['end'], 'all_day': e['all_day'], 'calendar': e['calendar']}];
    }
    final h = await healthSummary();
    if (h != null) out['health_today'] = h;
    final loc = await _safe(() => locationSummary());
    if (loc != null && (loc['samples'] as int) > 0) out['location'] = loc;
    return out;
  }

  // ── tools (A, the System and every agent) ─────────────────────────────────────────────────────────

  static Map<String, dynamic> _fn(String name, String desc, Map<String, dynamic> props, [List<String> req = const []]) => {
        'type': 'function',
        'function': {
          'name': name,
          'description': desc,
          'parameters': {'type': 'object', 'properties': props, 'required': req},
        },
      };
  static const _s = {'type': 'string'};
  static const _n = {'type': 'number'};

  static final schemas = [
    _fn('calendar_events', 'Events in the phone\'s calendars (including Google calendars on the phone). from/to: ISO 8601 (default: next 7 days).',
        {'from': _s, 'to': _s}),
    _fn('calendar_list', 'The phone\'s calendars (ids, names, accounts, which are writable).', {}),
    _fn('calendar_add_event',
        'Add an event to a phone calendar (default: the primary Google calendar). start/end: ISO 8601 local time. remind_minutes: alert before.',
        {'title': _s, 'start': _s, 'end': _s, 'description': _s, 'location': _s, 'calendar_id': _n, 'all_day': {'type': 'boolean'}, 'remind_minutes': _n},
        ['title', 'start']),
    _fn('calendar_delete_event', 'Delete a calendar event by id.', {'id': _n}, ['id']),
    _fn('health_summary', 'Sleep, steps, workouts, heart rate, calories and weight from Health Connect (Google Fit, smartwatch). days: how far back.',
        {'days': _n}),
    _fn('location_history', 'Places the player spends time (home, school/work guesses) and today\'s trail. days: how far back.', {'days': _n}),
    _fn('screen_time', 'Screen time today per app.', {}),
    _fn('next_alarm', 'The next alarm set on the phone.', {}),
  ];
  static final _names = {for (final s in schemas) (s['function'] as Map)['name'] as String};
  static bool handles(String name) => _names.contains(name);

  static Future<String> runTool(String name, Map<String, dynamic> a) async {
    final p = instance;
    try {
      switch (name) {
        case 'calendar_events':
          final from = DateTime.tryParse('${a['from'] ?? ''}') ?? DateTime.now();
          final to = DateTime.tryParse('${a['to'] ?? ''}') ?? from.add(const Duration(days: 7));
          return jsonEncode(await p.events(from, to));
        case 'calendar_list':
          return jsonEncode(await p.calendars());
        case 'calendar_add_event':
          final start = DateTime.tryParse('${a['start']}');
          if (start == null) return 'Give start as ISO 8601.';
          final end = DateTime.tryParse('${a['end'] ?? ''}') ?? start.add(const Duration(hours: 1));
          final id = await p.addEvent('${a['title']}', start, end,
              description: a['description'] as String?,
              location: a['location'] as String?,
              calendarId: (a['calendar_id'] as num?)?.toInt(),
              allDay: a['all_day'] == true,
              remindMinutes: (a['remind_minutes'] as num?)?.toInt());
          return 'Added to the calendar (event $id).';
        case 'calendar_delete_event':
          return await p.deleteEvent((a['id'] as num).toInt()) ? 'Deleted.' : 'No such event.';
        case 'health_summary':
          return jsonEncode(await p.healthSummary(days: ((a['days'] as num?) ?? 1).toInt()) ??
              {'error': 'Health Connect is not connected. Connect it in HES → Phone data.'});
        case 'location_history':
          return jsonEncode(await p.locationSummary(days: ((a['days'] as num?) ?? 14).toInt()));
        case 'screen_time':
          return jsonEncode(await p.screenTime() ?? {'error': 'Screen time access is not granted.'});
        case 'next_alarm':
          return jsonEncode(await p.nextAlarm() ?? {'next_alarm': null});
      }
    } on PlatformException catch (e) {
      return e.code == 'PERMISSION' ? 'Permission needed: ${e.message}. Connect phone data in HES.' : 'Phone error: ${e.message}';
    } on MissingPluginException {
      return 'Phone data is not available here.';
    }
    return 'Unknown tool $name.';
  }
}
