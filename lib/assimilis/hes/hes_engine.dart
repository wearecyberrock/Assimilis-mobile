// HES engine, ported from organelle/hes/engine.py (Assimilis server). Pure functions: stats are always a
// deterministic replay of the events, so undo or a rule change just recomputes.
import 'dart:math' as math;

const dayHour = 4; // the HES day starts at local 04:00
const ladder = [(10, 'E'), (25, 'D'), (40, 'C'), (55, 'B'), (70, 'A'), (85, 'S'), (95, 'SS')];
const dailyStatCap = 0.8;
const moduleDailyCap = 0.6;
const moduleXpDay = 25;
const passiveSources = {'sensor', 'system', 'gmail', 'import', 'statement', 'photo'};
const decay = 0.05;
const scoreKinds = {'score', 'quiz', 'checkin'};

double clampD(num v, num lo, num hi) => math.max(lo.toDouble(), math.min(hi.toDouble(), v.toDouble()));

String rank(double v) {
  for (final (limit, name) in ladder) {
    if (v < limit) return name;
  }
  if (v <= 100) return 'SSS';
  if (v <= 115) return 'EX';
  if (v <= 130) return 'National';
  return 'Monarch';
}

/// HES day (date at local 00:00) for an instant; the day starts at 04:00.
DateTime dayOf(DateTime at) {
  final l = at.toLocal().subtract(const Duration(hours: dayHour));
  return DateTime(l.year, l.month, l.day);
}

int xpToNext(int level) => (100 * math.pow(level, 1.5)).round();

(int, int, int) levelFrom(num xpTotal, [bool allowNegative = false]) {
  var level = 1;
  var rest = allowNegative ? xpTotal.toInt() : math.max(0, xpTotal.toInt());
  while (rest >= xpToNext(level)) {
    rest -= xpToNext(level);
    level += 1;
  }
  return (level, rest, xpToNext(level));
}

int apForLevel(int level) {
  var s = 0;
  for (var n = 2; n <= level; n++) {
    s += 1 + (n % 5 == 0 ? 1 : 0);
  }
  return s;
}

double power(Map<String, double> stats, Iterable<String> assessed) =>
    (assessed.where(stats.containsKey).fold<double>(0, (a, s) => a + stats[s]!) * 10).round() / 10;

String overallRank(Map<String, double> stats, Iterable<String> assessed) {
  final v = assessed.where(stats.containsKey).map((s) => stats[s]!).toList();
  return v.isEmpty ? 'E' : rank(v.reduce((a, b) => a + b) / v.length);
}

/// Static HES data (tree.json, classes.json, abilities.json, modules/*.json).
class HesData {
  final Map<String, Map<String, dynamic>> statIndex; // id -> stat (with 'branch')
  final List<Map<String, dynamic>> branches;
  final Map<String, dynamic> classes;
  final List<Map<String, dynamic>> abilities;
  final Map<String, Map<String, dynamic>> modules;
  HesData(this.statIndex, this.branches, this.classes, this.abilities, this.modules);

  List<String> defaultAssessed() =>
      (statIndex.entries.where((e) => e.value['unassessed'] != true).map((e) => e.key).toList()..sort());
}

String classify(HesData data, Map<String, double> stats, Iterable<String> assessed) {
  final fallback = '${data.classes['fallback']}';
  final top = assessed.where((s) => stats.containsKey(s) && !s.startsWith('materials.')).toList()
    ..sort((a, b) {
      final c = stats[b]!.compareTo(stats[a]!);
      return c != 0 ? c : a.compareTo(b);
    });
  if (top.length < 2 || stats[top[0]]! <= 0) return fallback;
  bool fits(String stat, String want) => stat == want || (!want.contains('.') && stat.split('.').first == want);
  final a = top[0], b = top[1];
  for (final entry in (data.classes['classes'] as List)) {
    final m = (entry['match'] as List).cast<String>();
    if ((fits(a, m[0]) && fits(b, m[1])) || (fits(a, m[1]) && fits(b, m[0]))) return '${entry['name']}';
  }
  return fallback;
}

Map<String, double> feedDeltas(Map<String, dynamic> module, Map<String, dynamic> event) {
  final kind = module['kind'];
  final q = ((event['quantity'] ?? 0) as num).toDouble();
  final out = <String, double>{};
  void add(String s, double d) => out[s] = (out[s] ?? 0) + d;
  if ((kind == 'boolean' || kind == 'abstain_streak') && q <= 0) {
    for (final f in (module['relapse'] as List? ?? const [])) {
      add(f['stat'], (f['gain'] as num).toDouble());
    }
    return out;
  }
  final range = (module['range'] as List?) ?? const [0, 100];
  final lo = (range[0] as num).toDouble(), hi = (range[1] as num).toDouble();
  for (final f in (module['feeds'] as List? ?? const [])) {
    final g = (f['gain'] as num).toDouble();
    final per = ((f['per'] ?? 1) as num).toDouble() == 0 ? 1.0 : ((f['per'] ?? 1) as num).toDouble();
    double d;
    if (f['band'] != null) {
      final blo = (f['band'][0] as num).toDouble(), bhi = (f['band'][1] as num).toDouble();
      d = (blo <= q && q <= bhi) ? g : -g.abs() * math.min(1.0, (q < blo ? blo - q : q - bhi) / 2);
    } else if (scoreKinds.contains(kind)) {
      final mid = ((f['mid'] ?? (lo + hi) / 2) as num).toDouble();
      final span = q >= mid ? hi - mid : mid - lo;
      d = span != 0 ? g * clampD((q - mid) / span, -1, 1) : 0.0;
    } else if (kind == 'boolean' || kind == 'abstain_streak') {
      d = g;
    } else if (kind == 'ratio') {
      d = g * clampD(q, -1, 1);
    } else {
      d = g * q / per;
    }
    add(f['stat'], d);
  }
  return out;
}

int moduleXp(Map<String, dynamic> m) => (m['xp'] as int?) ?? 5;

bool earnsXp(Map<String, dynamic> m, Map<String, dynamic> e) =>
    moduleXp(m) > 0 && m['sensor'] != true && m['domain'] != 'materials.wealth' && !passiveSources.contains(e['source']);

/// Result of a replay.
class HesState {
  final Map<String, double> stats, caps;
  final List<String> assessed;
  final int level, xp, xpNext, xpTotal, ap, coins;
  final double powerValue;
  final String rankName, className;
  final List<String> unlocked;
  final List<Map<String, dynamic>> xpLog;
  HesState(this.stats, this.caps, this.assessed, this.level, this.xp, this.xpNext, this.xpTotal, this.ap, this.coins,
      this.powerValue, this.rankName, this.className, this.unlocked, this.xpLog);
}

/// Recompute everything from the baseline and the applied events. Pure and deterministic.
HesState replay(HesData data, Map<String, dynamic> baseline, List<Map<String, dynamic>> events,
    Map<String, dynamic> settings, {DateTime? until}) {
  final negative = settings['negative_scoring'] == true;
  final index = data.statIndex;
  final bs = Map<String, dynamic>.from(baseline['stats'] ?? {});
  final stats = {for (final k in index.keys) k: ((bs[k] ?? 0.0) as num).toDouble()};
  final floor = Map<String, double>.from(stats);
  final assessed = (List<String>.from(baseline['assessed'] ?? const [])).where(index.containsKey).toSet();
  final bc = Map<String, dynamic>.from(baseline['caps'] ?? {});
  final caps = {for (final k in index.keys) k: ((bc[k] ?? 100.0) as num).toDouble()};
  final adefs = {for (final a in data.abilities) a['id']: a};
  final startAt = DateTime.fromMillisecondsSinceEpoch(((baseline['start'] ?? 0) as num).toInt() * 1000);
  final startDay = dayOf(startAt);
  final evs = events.where((e) => e['status'] == 'applied').toList()
    ..sort((a, b) {
      final c = (a['at'] as num).compareTo(b['at'] as num);
      return c != 0 ? c : '${a['id']}'.compareTo('${b['id']}');
    });
  final endAt = until ??
      DateTime.fromMillisecondsSinceEpoch(
          (evs.fold<num>((baseline['start'] ?? 0) as num, (m, e) => math.max(m, e['at'] as num)) * 1000).toInt());
  var endDay = dayOf(endAt);
  if (endDay.isBefore(startDay)) endDay = startDay;
  final byDay = <DateTime, List<Map<String, dynamic>>>{};
  for (final e in evs) {
    final d = dayOf(DateTime.fromMillisecondsSinceEpoch(((e['at'] as num) * 1000).toInt()));
    if (!d.isAfter(endDay)) (byDay[d.isBefore(startDay) ? startDay : d] ??= []).add(e);
  }
  final lastFed = {for (final k in index.keys.where((k) => k.startsWith('flesh.'))) k: startDay};
  var xp = 0, apBonus = 0, apSpent = 0;
  final xpLog = <Map<String, dynamic>>[];
  var coins = 0.0;
  final passive = <String, double>{};
  final unlocked = <String>[];
  var day = startDay;
  while (!day.isAfter(endDay)) {
    final raw = <String, double>{};
    final perMod = <String, Map<String, double>>{};
    final xpMod = <String, double>{};
    final xpCount = <String, int>{};
    final trained = <String>{};
    for (final e in byDay[day] ?? const <Map<String, dynamic>>[]) {
      final kind = e['kind'];
      final d = Map<String, dynamic>.from(e['data'] ?? {});
      if (kind == 'mission') {
        final x = ((d['xp'] ?? 0) as num).toInt();
        xp += x;
        if (x != 0) xpLog.add({'day': day.toIso8601String(), 'xp': x, 'why': e['summary'] ?? 'Quest'});
        coins += ((d['coins'] ?? 0) as num).toDouble();
        apBonus += ((d['ap'] ?? 0) as num).toInt();
        (d['gains'] as Map? ?? {}).forEach((s, g) {
          if (index.containsKey(s) && g is num) raw[s] = (raw[s] ?? 0) + clampD(g, -0.6, 0.6);
        });
      } else if (kind == 'assess') {
        final s = d['stat'];
        if (index.containsKey(s) && !assessed.contains(s) && d['value'] is num) {
          assessed.add(s);
          stats[s] = floor[s] = clampD(d['value'], 0, 20);
        }
      } else if (kind == 'ability') {
        final a = adefs[d['ability']];
        if (a != null && !unlocked.contains(a['id'])) {
          unlocked.add(a['id']);
          apSpent += ((a['cost_ap'] ?? 1) as num).toInt();
          final p = (a['grants'] as Map?)?['passive'];
          if (p != null && index.containsKey(p['stat'])) {
            passive[p['stat']] = math.min(10, (passive[p['stat']] ?? 0) + math.min(5, ((p['pct'] ?? 0) as num).toDouble()));
          }
        }
      } else if (kind == 'redeem') {
        coins -= ((d['cost'] ?? 0) as num).toDouble();
      } else if (kind == 'limit_break') {
        final s = d['stat'];
        if (caps.containsKey(s)) caps[s] = math.min(caps[s]! + 15, 145.0);
      } else {
        final m = data.modules[e['module']];
        if (m == null) continue;
        final deltas = feedDeltas(m, e);
        final pm = perMod[m['id']] ??= {};
        deltas.forEach((s, v) => pm[s] = (pm[s] ?? 0) + v);
        if (!earnsXp(m, e)) continue;
        xpCount[m['id']] = (xpCount[m['id']] ?? 0) + 1;
        if (!negative ||
            (e['at'] as num) < ((settings['negative_scoring_since'] ?? 0) as num) ||
            deltas.values.any((v) => v > 0)) {
          xpMod[m['id']] = (xpMod[m['id']] ?? 0) + moduleXp(m);
        } else if (deltas.values.any((v) => v < 0)) {
          xpMod[m['id']] = (xpMod[m['id']] ?? 0) - moduleXp(m);
        }
      }
    }
    perMod.forEach((mid, deltas) {
      final cap = math.min(moduleDailyCap, ((data.modules[mid]!['daily_cap'] ?? moduleDailyCap) as num).toDouble());
      final total = deltas.values.fold<double>(0, (a, v) => a + v.abs());
      final scale = total > cap ? cap / total : 1.0;
      deltas.forEach((s, d) {
        if (assessed.contains(s)) {
          raw[s] = (raw[s] ?? 0) + d * scale;
          if (d > 0 && s.startsWith('flesh.')) trained.add(s);
        }
      });
    });
    for (final mid in (xpMod.keys.toList()..sort())) {
      final gained = clampD(xpMod[mid]!, -moduleXpDay, moduleXpDay).toInt();
      if (gained != 0) {
        xp += gained;
        final n = xpCount[mid] ?? 0;
        xpLog.add({'day': day.toIso8601String(), 'xp': gained, 'why': '${data.modules[mid]!['name'] ?? mid}: $n log${n == 1 ? '' : 's'}'});
      }
    }
    for (final s in index.keys) {
      if (!assessed.contains(s)) continue;
      var d = raw[s] ?? 0.0;
      final v = stats[s]!, cap = caps[s]!;
      if (d > 0) {
        d *= clampD((cap - v) / 60, 0.05, 1) * (1 + (passive[s] ?? 0) / 100);
      } else if (d < 0) {
        d *= clampD(v / 60, 0.2, 1);
      }
      if (trained.contains(s)) {
        lastFed[s] = day;
      } else if (lastFed.containsKey(s) && day.difference(lastFed[s]!).inDays > 7) {
        d -= math.min(decay, math.max(0.0, v - floor[s]!));
      }
      final value = v + clampD(d, -dailyStatCap, dailyStatCap);
      stats[s] = ((negative ? math.min(value, cap) : clampD(value, 0, cap)) * 10000).round() / 10000;
    }
    day = DateTime(day.year, day.month, day.day + 1);
  }
  final (level, into, nxt) = levelFrom(xp, negative);
  final rounded = {for (final e in stats.entries) e.key: (e.value * 100).round() / 100};
  final ass = assessed.toList()..sort();
  return HesState(rounded, caps, ass, level, into, nxt, xp, apForLevel(level) + apBonus - apSpent, coins.floor(),
      power(stats, ass), overallRank(stats, ass), classify(data, stats, ass), unlocked, xpLog);
}

/// (current, best) streak of qualifying HES days for one module.
(int, int) streak(List<Map<String, dynamic>> events, String moduleId, {String kind = 'count'}) {
  final totals = <DateTime, (double, bool)>{};
  for (final e in events) {
    if (e['status'] != 'applied' || e['module'] != moduleId) continue;
    final d = dayOf(DateTime.fromMillisecondsSinceEpoch(((e['at'] as num) * 1000).toInt()));
    final q = ((e['quantity'] ?? 0) as num).toDouble();
    final (t, bad) = totals[d] ?? (0.0, false);
    totals[d] = (t + math.max(q, 0), bad || q <= 0);
  }
  final good = totals.entries
      .where((e) => e.value.$1 > 0 && !(kind == 'abstain_streak' && e.value.$2))
      .map((e) => e.key)
      .toList()
    ..sort();
  var best = 0, run = 0;
  DateTime? prev;
  for (final d in good) {
    run = (prev != null && d.difference(prev).inDays == 1) ? run + 1 : 1;
    best = math.max(best, run);
    prev = d;
  }
  final today = dayOf(DateTime.now());
  if (totals.containsKey(today) && !good.contains(today)) return (0, best);
  var cur = 0;
  var d = good.contains(today) ? today : DateTime(today.year, today.month, today.day - 1);
  while (good.contains(d)) {
    cur++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return (cur, best);
}
