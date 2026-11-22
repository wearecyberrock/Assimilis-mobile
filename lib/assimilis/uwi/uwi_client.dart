import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings.dart';

class UwiLoginError implements Exception {
  final String message;
  UwiLoginError(this.message);
  @override
  String toString() => message;
}

/// Mona VLE (Moodle) client on the phone, ported from components/uwi-academic (session.py, client.py).
/// Signs in with your UWI username/password (kept in the Android keystore), then uses Moodle's own
/// AJAX services. Read-only: it never submits, posts or changes anything on the VLE.
class UwiClient {
  UwiClient._();
  static final UwiClient instance = UwiClient._();
  static const base = 'https://vle.mona.uwi.edu';

  final _cookies = <String, String>{};
  String? _sesskey;
  final _c = http.Client();

  String get _cookieHeader => _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  void _take(http.BaseResponse r) {
    final raw = r.headers['set-cookie'];
    if (raw == null) return;
    // Several cookies are folded into one header separated by commas (dates contain commas too).
    for (final part in raw.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'))) {
      final kv = part.split(';').first.trim();
      final i = kv.indexOf('=');
      if (i > 0) _cookies[kv.substring(0, i)] = kv.substring(i + 1);
    }
  }

  /// GET/POST following redirects by hand so every Set-Cookie is kept.
  Future<(String body, String url)> _send(String method, String url, {Object? body, Map<String, String>? headers}) async {
    var current = Uri.parse(url);
    var m = method;
    Object? b = body;
    for (var hop = 0; hop < 8; hop++) {
      final req = http.Request(m, current)
        ..followRedirects = false
        ..headers.addAll({
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AssimilisMobile',
          if (_cookies.isNotEmpty) 'Cookie': _cookieHeader,
          ...?headers,
        });
      if (b is Map<String, String>) req.bodyFields = b;
      if (b is String) req.body = b;
      final res = await http.Response.fromStream(await _c.send(req).timeout(const Duration(seconds: 25)));
      _take(res);
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
    throw UwiLoginError('Too many redirects from the VLE.');
  }

  static String? _sess(String html) =>
      RegExp(r'"sesskey":\s*"([^"]+)"').firstMatch(html)?.group(1) ??
      RegExp(r'name="sesskey"\s+value="([^"]+)"').firstMatch(html)?.group(1);

  Future<void> login({bool force = false}) async {
    if (!force && _sesskey != null) return;
    final s = await AssimilisSettings.get();
    final user = s.uwiUser;
    final pw = await s.uwiPassword();
    if (user.isEmpty || pw.isEmpty) throw UwiLoginError('Add your UWI username and password in the UWI screen first.');
    _cookies.clear();
    final (page, _) = await _send('GET', '$base/login/index.php');
    final token = RegExp(r'name="logintoken"\s+value="([^"]+)"').firstMatch(page)?.group(1) ?? '';
    final (after, url) = await _send('POST', '$base/login/index.php',
        body: {'username': user, 'password': pw, 'logintoken': token});
    final lower = after.toLowerCase();
    if (lower.contains('captcha') || lower.contains('multi-factor') || lower.contains('forced password change')) {
      throw UwiLoginError('The VLE wants you to finish signing in yourself (CAPTCHA, MFA or a password change).');
    }
    if (url.contains('/login/index.php')) {
      final err = RegExp(r'class="alert alert-danger[^>]*>(.*?)</div>', dotAll: true).firstMatch(after)?.group(1);
      throw UwiLoginError(err == null ? 'Invalid UWI login.' : err.replaceAll(RegExp(r'<[^>]+>'), ' ').trim());
    }
    _sesskey = _sess(after) ?? _sess((await _send('GET', '$base/my/courses.php')).$1);
    if (_sesskey == null) throw UwiLoginError('Signed in, but the VLE session key was missing.');
  }

  Future<dynamic> _ajax(String method, Map<String, dynamic> args) async {
    await login();
    for (var attempt = 0; attempt < 2; attempt++) {
      final (body, _) = await _send('POST', '$base/lib/ajax/service.php?sesskey=$_sesskey&info=$method',
          body: jsonEncode([
            {'index': 0, 'methodname': method, 'args': args}
          ]),
          headers: {'Content-Type': 'application/json'});
      final data = jsonDecode(body) as List;
      if (data.isNotEmpty && data[0]['error'] == true) {
        if (attempt == 0) {
          await login(force: true); // session expired
          continue;
        }
        throw UwiLoginError('${data[0]['exception']?['message'] ?? 'VLE error'}');
      }
      return data[0]['data'];
    }
  }

  Future<List<Map<String, dynamic>>> courses() async {
    final d = await _ajax('core_course_get_enrolled_courses_by_timeline_classification',
        {'offset': 0, 'limit': 0, 'classification': 'inprogress', 'sort': 'fullname'});
    return [
      for (final c in (d['courses'] as List))
        {
          'id': c['id'],
          'code': c['shortname'] ?? 'Course-${c['id']}',
          'name': c['fullname'] ?? c['shortname'],
          'url': c['viewurl'] ?? '$base/course/view.php?id=${c['id']}',
          'progress': c['progress'],
        }
    ];
  }

  /// Upcoming assignments, quizzes and other dated activities.
  Future<List<Map<String, dynamic>>> deadlines({int limit = 50}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final d = await _ajax('core_calendar_get_action_events_by_timesort',
        {'timesortfrom': now - 86400, 'limitnum': limit.clamp(1, 50)});
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

  /// Announcements from each course's news forum.
  Future<List<Map<String, dynamic>>> announcements(Map<String, dynamic> course) async {
    await login();
    final (html, _) = await _send('GET', '${course['url']}');
    final forum = RegExp(r'href="(https://vle\.mona\.uwi\.edu/mod/forum/view\.php\?id=\d+)"').firstMatch(html)?.group(1);
    if (forum == null) return [];
    final (page, _) = await _send('GET', forum);
    final rows = RegExp(
      r'<tr[^>]*class="discussion[^>]*>.*?<th[^>]*class="topic[^>]*>.*?<a[^>]*href="([^"]+)"[^>]*>([^<]+)</a>.*?<td[^>]*class="author[^>]*>.*?<a[^>]*>([^<]+)</a>',
      dotAll: true,
    ).allMatches(page);
    return [
      for (final m in rows.take(10))
        {'course': course['code'], 'title': m.group(2)!.trim(), 'author': m.group(3)!.trim(), 'url': m.group(1)}
    ];
  }

  /// Fetch everything and keep a copy on the phone for offline use and for Jarvis.
  Future<Map<String, dynamic>> sync() async {
    final c = await courses();
    final d = await deadlines();
    final a = <Map<String, dynamic>>[];
    for (final course in c) {
      try {
        a.addAll(await announcements(course));
      } catch (_) {}
    }
    final snap = {'synced': DateTime.now().toIso8601String(), 'courses': c, 'deadlines': d, 'announcements': a};
    await (await AssimilisSettings.get()).setBlob('uwi', jsonEncode(snap));
    return snap;
  }

  static Future<Map<String, dynamic>?> cached() async {
    final raw = (await AssimilisSettings.get()).blob('uwi');
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw));
  }
}
