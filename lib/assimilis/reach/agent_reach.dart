import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Agent Reach on the phone (read-only), following components/agent-reach:
/// web search via Exa's free hosted MCP, page reading via Jina Reader, plus GitHub, Reddit,
/// YouTube captions and RSS. Never logs in, never posts, never bypasses CAPTCHAs.
class AgentReach {
  static const _ua = 'Mozilla/5.0 (Linux; Android 14) AssimilisMobile AgentReach';
  static const _max = 12000; // characters returned to the model

  static String _cut(String s) => s.length > _max ? '${s.substring(0, _max)}\n…[truncated]' : s;

  static Future<String> _get(String url, {Map<String, String>? headers}) async {
    final r = await http
        .get(Uri.parse(url), headers: {'User-Agent': _ua, ...?headers})
        .timeout(const Duration(seconds: 30));
    if (r.statusCode >= 400) throw Exception('HTTP ${r.statusCode} from ${Uri.parse(url).host}');
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  /// Web search (Exa semantic search, no key).
  static Future<String> search(String query, {int limit = 5}) async {
    try {
      final r = await http
          .post(Uri.parse('https://mcp.exa.ai/mcp'),
              headers: {'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream'},
              body: jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'method': 'tools/call',
                'params': {
                  'name': 'web_search_exa',
                  'arguments': {'query': query, 'numResults': limit}
                }
              }))
          .timeout(const Duration(seconds: 30));
      final raw = utf8.decode(r.bodyBytes, allowMalformed: true);
      final lines = raw.split('\n').where((l) => l.startsWith('data:')).map((l) => l.substring(5).trim()).toList();
      final msg = jsonDecode(lines.isNotEmpty ? lines.last : raw);
      if (msg['error'] != null) throw Exception(msg['error']['message']);
      final text = ((msg['result']?['content'] as List?) ?? const [])
          .where((c) => c['type'] == 'text')
          .map((c) => c['text'])
          .join('\n');
      if (text.trim().isNotEmpty) return _cut(text);
    } catch (_) {}
    // Fallback: DuckDuckGo HTML results.
    final html = await _get('https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(query)}');
    final hits = RegExp(r'class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>[\s\S]*?class="result__snippet"[^>]*>(.*?)</a>')
        .allMatches(html)
        .take(limit)
        .map((m) {
      var url = m.group(1)!;
      final u = Uri.tryParse(url.startsWith('//') ? 'https:$url' : url);
      url = u?.queryParameters['uddg'] ?? url;
      String strip(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&amp;', '&').replaceAll('&#x27;', "'");
      return 'Title: ${strip(m.group(2)!)}\nURL: $url\n${strip(m.group(3)!)}';
    });
    return hits.isEmpty ? 'No results for "$query".' : hits.join('\n\n');
  }

  /// Read any public page as clean text (Jina Reader).
  static Future<String> read(String url) async {
    final target = url.startsWith('http') ? url : 'https://$url';
    final host = Uri.parse(target).host;
    if (host.contains('youtube.com') || host == 'youtu.be') return youtube(target);
    if (host.contains('reddit.com')) return reddit(target);
    if (host == 'github.com') {
      final parts = Uri.parse(target).pathSegments;
      if (parts.length >= 2) return github('${parts[0]}/${parts[1]}');
    }
    final body = await _get('https://r.jina.ai/$target', headers: {'Accept': 'text/plain'});
    final content = body.contains('Markdown Content:') ? body.split('Markdown Content:').last : body;
    return _cut(content.trim());
  }

  /// A GitHub repo (owner/name): description, stars, README. Or a search if no slash.
  static Future<String> github(String q) async {
    const h = {'Accept': 'application/vnd.github+json'};
    if (!q.contains('/')) {
      final d = jsonDecode(await _get('https://api.github.com/search/repositories?q=${Uri.encodeQueryComponent(q)}&per_page=5', headers: h));
      return (d['items'] as List)
          .map((r) => '${r['full_name']} ★${r['stargazers_count']}: ${r['description'] ?? ''}\n${r['html_url']}')
          .join('\n\n');
    }
    final repo = jsonDecode(await _get('https://api.github.com/repos/$q', headers: h));
    String readme = '';
    try {
      readme = await _get('https://api.github.com/repos/$q/readme', headers: {'Accept': 'application/vnd.github.raw'});
    } catch (_) {}
    return _cut('${repo['full_name']} ★${repo['stargazers_count']} · ${repo['language'] ?? ''} · '
        'licence ${repo['license']?['spdx_id'] ?? 'none'}\n${repo['description'] ?? ''}\n\n$readme');
  }

  /// Reddit: a subreddit ("r/flutterdev") or a post URL.
  static Future<String> reddit(String target) async {
    var url = target.trim();
    if (!url.startsWith('http')) url = 'https://www.reddit.com/${url.startsWith('r/') ? url : 'r/$url'}/hot';
    url = url.replaceAll(RegExp(r'/$'), '');
    final d = jsonDecode(await _get('$url.json?limit=10&raw_json=1'));
    final listing = d is List ? d : [d];
    final out = StringBuffer();
    for (final l in listing) {
      for (final c in (l['data']?['children'] as List? ?? const [])) {
        final p = c['data'];
        if (p['title'] != null) {
          out.writeln('• ${p['title']} (${p['score']}↑, ${p['num_comments']} comments) https://reddit.com${p['permalink']}');
          if ('${p['selftext'] ?? ''}'.isNotEmpty) out.writeln('  ${'${p['selftext']}'.replaceAll('\n', ' ')}');
        } else if (p['body'] != null) {
          out.writeln('  ↳ ${p['author']}: ${'${p['body']}'.replaceAll('\n', ' ')}');
        }
      }
    }
    return _cut(out.toString());
  }

  /// YouTube: title, channel and captions (English if available).
  static Future<String> youtube(String url) async {
    final page = await _get(url, headers: {'Accept-Language': 'en-US,en;q=0.9'});
    final title = RegExp(r'<title>(.*?)</title>').firstMatch(page)?.group(1)?.replaceAll(' - YouTube', '') ?? 'Video';
    final channel = RegExp(r'"ownerChannelName":"([^"]+)"').firstMatch(page)?.group(1) ?? '';
    final tracksJson = RegExp(r'"captionTracks":(\[.*?\])').firstMatch(page)?.group(1);
    if (tracksJson == null) return '$title by $channel\n(No captions available.)';
    final tracks = jsonDecode(tracksJson.replaceAll(r'&', '&')) as List;
    final track = tracks.firstWhere((t) => '${t['languageCode']}'.startsWith('en'), orElse: () => tracks.first);
    final xml = XmlDocument.parse(await _get('${track['baseUrl']}'));
    final text = xml.findAllElements('text').map((e) => e.innerText).join(' ').replaceAll('&#39;', "'").replaceAll('&quot;', '"');
    return _cut('$title by $channel\n\n$text');
  }

  /// RSS or Atom feed: latest items.
  static Future<String> rss(String url) async {
    final doc = XmlDocument.parse(await _get(url));
    final items = [...doc.findAllElements('item'), ...doc.findAllElements('entry')].take(15);
    return _cut(items.map((i) {
      String f(String n) => i.findElements(n).isEmpty ? '' : i.findElements(n).first.innerText.trim();
      final link = f('link').isNotEmpty ? f('link') : (i.findElements('link').isEmpty ? '' : i.findElements('link').first.getAttribute('href') ?? '');
      return '• ${f('title')} ${f('pubDate').isNotEmpty ? '(${f('pubDate')})' : f('updated')}\n  $link';
    }).join('\n'));
  }
}
