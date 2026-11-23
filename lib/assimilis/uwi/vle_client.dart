import 'dart:convert';

import 'package:http/http.dart' as http;

import 'vle_store.dart';

class VleLoginError implements Exception {
  final String message;
  VleLoginError(this.message);
  @override
  String toString() => message;
}

/// Multi-user read-only Mona VLE (Moodle) scanner on the phone.
/// Keeps a separate cookie jar and session key per encrypted account id,
/// never submits, posts, or modifies anything on the VLE.
class VleClient {
  VleClient._();
  static final VleClient instance = VleClient._();

  final Map<String, Map<String, String>> _cookiesByAcc = {};
  final Map<String, String> _sesskeyByAcc = {};
  http.Client? _overrideClient;

  /// Allows tests to inject a mock HTTP client.
  void setClientForTest(http.Client? c) {
    _overrideClient = c;
    _cookiesByAcc.clear();
    _sesskeyByAcc.clear();
  }

  http.Client get _http => _overrideClient ?? _defaultClient;
  final http.Client _defaultClient = http.Client();

  Map<String, String> _jar(String accId) => _cookiesByAcc.putIfAbsent(accId, () => {});

  void _take(String accId, http.BaseResponse r) {
    final raw = r.headers['set-cookie'];
    if (raw == null) return;
    final jar = _jar(accId);
    for (final part in raw.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'))) {
      final kv = part.split(';').first.trim();
      final i = kv.indexOf('=');
      if (i > 0) jar[kv.substring(0, i)] = kv.substring(i + 1);
    }
  }

  Future<(String body, String url)> _send(
    String accId,
    String method,
    String url, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    var current = Uri.parse(url);
    var m = method;
    Object? b = body;
    final jar = _jar(accId);
    for (var hop = 0; hop < 8; hop++) {
      final req = http.Request(m, current)
        ..followRedirects = false
        ..headers.addAll({
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AssimilisMobile',
          if (jar.isNotEmpty) 'Cookie': jar.entries.map((e) => '${e.key}=${e.value}').join('; '),
          ...?headers,
        });
      if (b is Map<String, String>) req.bodyFields = b;
      if (b is String) req.body = b;
      final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 25)));
      _take(accId, res);
      if (res.isRedirect || (res.statusCode >= 300 && res.statusCode < 400)) {
        final loc = res.headers['location'];
        if (loc == null) return (res.body, current.toString());
        current = current.resolve(loc);
        m = 'GET';
        b = null;
        continue;
      }
      return (res.body, current.toString());
    }
    throw VleLoginError('Too many redirects from the VLE.');
  }

  static String? _sess(String html) =>
      RegExp(r'"sesskey"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1) ??
      RegExp(r'name="sesskey"\s+value="([^"]+)"').firstMatch(html)?.group(1);

  Future<void> login(VleAccount account, {bool force = false}) async {
    if (!force && _sesskeyByAcc[account.id] != null) return;
    if (account.username.isEmpty || account.password.isEmpty) {
      throw VleLoginError('Account "${account.label}" is missing a username or password.');
    }
    _jar(account.id).clear();
    _sesskeyByAcc.remove(account.id);
    final base = account.baseUrl;
    final (page, _) = await _send(account.id, 'GET', '$base/login/index.php');
    final token = RegExp(r'name="logintoken"\s+value="([^"]+)"').firstMatch(page)?.group(1) ?? '';
    final (after, url) = await _send(
      account.id,
      'POST',
      '$base/login/index.php',
      body: {'username': account.username, 'password': account.password, 'logintoken': token},
    );
    final lower = after.toLowerCase();
    if (lower.contains('captcha') || lower.contains('multi-factor') || lower.contains('forced password change')) {
      throw VleLoginError('The VLE requires manual sign-in (CAPTCHA, MFA, or password change).');
    }
    if (url.contains('/login/index.php')) {
      final err = RegExp(r'class="alert alert-danger[^>]*>(.*?)</div>', dotAll: true).firstMatch(after)?.group(1);
      throw VleLoginError(err == null ? 'Invalid VLE login for ${account.label}.' : err.replaceAll(RegExp(r'<[^>]+>'), ' ').trim());
    }
    final sk = _sess(after) ?? _sess((await _send(account.id, 'GET', '$base/my/courses.php')).$1);
    if (sk == null) throw VleLoginError('Signed in, but the VLE session key was missing.');
    _sesskeyByAcc[account.id] = sk;
  }

  Future<dynamic> _ajax(VleAccount account, String method, Map<String, dynamic> args) async {
    await login(account);
    final base = account.baseUrl;
    for (var attempt = 0; attempt < 2; attempt++) {
      final sk = _sesskeyByAcc[account.id];
      final (body, _) = await _send(
        account.id,
        'POST',
        '$base/lib/ajax/service.php?sesskey=$sk&info=$method',
        body: jsonEncode([
          {'index': 0, 'methodname': method, 'args': args}
        ]),
        headers: {'Content-Type': 'application/json'},
      );
      final data = jsonDecode(body) as List;
      if (data.isNotEmpty && data[0]['error'] == true) {
        if (attempt == 0) {
          await login(account, force: true);
          continue;
        }
        throw VleLoginError('${data[0]['exception']?['message'] ?? 'VLE error'}');
      }
      return data[0]['data'];
    }
  }

  Future<List<Map<String, dynamic>>> courses(VleAccount account) async {
    final d = await _ajax(
      account,
      'core_course_get_enrolled_courses_by_timeline_classification',
      {'offset': 0, 'limit': 0, 'classification': 'inprogress', 'sort': 'fullname'},
    );
    return [
      for (final c in (d['courses'] as List))
        {
          'id': c['id'],
          'code': c['shortname'] ?? 'Course-${c['id']}',
          'name': c['fullname'] ?? c['shortname'],
          'url': c['viewurl'] ?? '${account.baseUrl}/course/view.php?id=${c['id']}',
          'progress': c['progress'],
        }
    ];
  }

  Future<List<Map<String, dynamic>>> deadlines(VleAccount account, {int limit = 50}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final d = await _ajax(
      account,
      'core_calendar_get_action_events_by_timesort',
      {'timesortfrom': now - 86400, 'limitnum': limit.clamp(1, 50)},
    );
    return [
      for (final e in (d['events'] as List))
        {
          'id': e['id'],
          'name': e['name'],
          'type': e['modulename'],
          'course': e['course']?['shortname'],
          'courseName': e['course']?['fullname'],
          'at': DateTime.fromMillisecondsSinceEpoch(((e['timesort'] ?? 0) as num).toInt() * 1000).toIso8601String(),
          'url': e['url'],
        }
    ];
  }

  /// Scans a course page for both announcements (news forum) and posted course resources (files, quizzes, assignments, URLs).
  Future<({List<Map<String, dynamic>> announcements, List<Map<String, dynamic>> resources})> scanCoursePage(
    VleAccount account,
    Map<String, dynamic> course,
  ) async {
    await login(account);
    final (html, _) = await _send(account.id, 'GET', '${course['url']}');
    final resources = <Map<String, dynamic>>[];
    final seenUrls = <String>{};
    final modRx = RegExp(
      r'href="([^"]*/mod/(resource|assign|quiz|url|folder|page|forum)/view\.php\?id=\d+)"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    for (final m in modRx.allMatches(html)) {
      final url = m.group(1)!;
      if (!seenUrls.add(url)) continue;
      final kind = m.group(2)!;
      final title = m.group(3)!.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (title.isEmpty) continue;
      resources.add({'course': course['code'], 'kind': kind, 'title': title, 'url': url});
    }

    final ann = <Map<String, dynamic>>[];
    final forum = resources.cast<Map<String, dynamic>?>().firstWhere(
          (r) => r!['kind'] == 'forum',
          orElse: () => null,
        )?['url'] as String?;
    if (forum != null) {
      final (page, _) = await _send(account.id, 'GET', forum);
      final rows = RegExp(
        r'<tr[^>]*class="discussion[^>]*>.*?<th[^>]*class="topic[^>]*>.*?<a[^>]*href="([^"]+)"[^>]*>([^<]+)</a>.*?<td[^>]*class="author[^>]*>.*?<a[^>]*>([^<]+)</a>',
        dotAll: true,
      ).allMatches(page);
      for (final m in rows.take(10)) {
        ann.add({
          'course': course['code'],
          'title': m.group(2)!.trim(),
          'author': m.group(3)!.trim(),
          'url': m.group(1),
        });
      }
    }
    return (announcements: ann, resources: resources.take(40).toList());
  }

  /// Full read-only scan for [account]: courses, deadlines, announcements, and course resources.
  Future<Map<String, dynamic>> scan(VleAccount account) async {
    final c = await courses(account);
    final d = await deadlines(account);
    final a = <Map<String, dynamic>>[];
    final r = <Map<String, dynamic>>[];
    for (final course in c) {
      try {
        final scanned = await scanCoursePage(account, course);
        a.addAll(scanned.announcements);
        r.addAll(scanned.resources);
      } catch (_) {}
    }
    final snap = {
      'accountId': account.id,
      'accountLabel': account.label,
      'synced': DateTime.now().toIso8601String(),
      'courses': c,
      'deadlines': d,
      'announcements': a,
      'resources': r,
    };
    await VleStore.instance.saveSnapshot(account.id, snap);
    return snap;
  }

  /// Tool schemas exposed to A, HES System, Workstation (MCP), Phone Agent, and Team.
  static final schemas = [
    {
      'type': 'function',
      'function': {
        'name': 'vle_accounts',
        'description': 'List the UWI Mona VLE accounts saved (encrypted) on this phone. Never exposes passwords.',
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}, 'required': <String>[]},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'vle_scan',
        'description': 'Scan or read cached UWI Mona VLE courses, upcoming deadlines, announcements, and posted resources for a saved account.',
        'parameters': {
          'type': 'object',
          'properties': {
            'account': {'type': 'string', 'description': 'Optional account label or id; defaults to active account.'},
            'refresh': {'type': 'boolean', 'description': 'Set true to perform a live scan from the VLE; false uses cached scan if available.'},
            'course': {'type': 'string', 'description': 'Optional course code filter, e.g. COMP2201.'},
          },
          'required': <String>[],
        },
      },
    },
  ];

  static bool handles(String name) => name == 'vle_accounts' || name == 'vle_scan';

  static Future<String> runTool(String name, Map<String, dynamic> a) async {
    final store = VleStore.instance;
    if (name == 'vle_accounts') {
      final list = await store.listAccounts();
      if (list.isEmpty) return 'No UWI Mona VLE accounts saved yet. Add one in Settings → UWI Mona VLE.';
      final active = await store.activeAccountId();
      final lines = <String>[];
      for (final acc in list) {
        final snap = await store.snapshot(acc.id);
        final synced = snap?['synced']?.toString().substring(0, 16).replaceAll('T', ' ') ?? 'never scanned';
        lines.add('- ${acc.label} (${acc.id})${acc.id == active ? ' [active]' : ''} · ${acc.baseUrl} · last scan: $synced');
      }
      return lines.join('\n');
    }

    if (name == 'vle_scan') {
      final acc = await store.findAccount(a['account']?.toString());
      if (acc == null) {
        return 'No matching UWI Mona VLE account found. Add an account in Settings → UWI Mona VLE first.';
      }
      final refresh = a['refresh'] == true || '${a['refresh']}'.toLowerCase() == 'true';
      Map<String, dynamic>? snap = refresh ? null : await store.snapshot(acc.id);
      snap ??= await instance.scan(acc);
      return formatSnapshot(snap, courseFilter: a['course']?.toString());
    }
    return 'Unknown VLE tool $name.';
  }

  static String formatSnapshot(Map<String, dynamic> snap, {String? courseFilter}) {
    final filter = courseFilter?.trim().toLowerCase() ?? '';
    bool matches(dynamic code) => filter.isEmpty || '$code'.toLowerCase().contains(filter);

    final courses = List<Map>.from(snap['courses'] ?? const []).where((c) => matches(c['code']) || matches(c['name'])).toList();
    final deadlines = List<Map>.from(snap['deadlines'] ?? const []).where((d) => matches(d['course']) || matches(d['name'])).toList();
    final ann = List<Map>.from(snap['announcements'] ?? const []).where((x) => matches(x['course'])).toList();
    final res = List<Map>.from(snap['resources'] ?? const []).where((x) => matches(x['course'])).toList();

    final buf = StringBuffer()
      ..writeln('UWI Mona VLE (${snap['accountLabel']}) · synced ${snap['synced']}')
      ..writeln('Courses (${courses.length}): ${courses.map((c) => '${c['code']} (${c['name']})').join('; ')}');
    if (deadlines.isNotEmpty) {
      buf.writeln('Upcoming deadlines (${deadlines.length}):');
      for (final d in deadlines.take(15)) {
        buf.writeln('- [${d['course'] ?? ''}] ${d['name']} (${d['type']}) due ${d['at']}');
      }
    } else {
      buf.writeln('Upcoming deadlines: none.');
    }
    if (ann.isNotEmpty) {
      buf.writeln('Announcements (${ann.length}):');
      for (final x in ann.take(8)) {
        buf.writeln('- [${x['course']}] ${x['title']} (by ${x['author']})');
      }
    }
    if (res.isNotEmpty) {
      buf.writeln('Course resources (${res.length}):');
      for (final x in res.take(15)) {
        buf.writeln('- [${x['course']}] (${x['kind']}) ${x['title']}');
      }
    }
    return buf.toString().trim();
  }
}
