import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../a2a/a2a.dart';
import '../hes/hes_store.dart';
import '../links/hermes_link.dart';
import '../settings.dart';

/// A connected HES instance: either one of your own devices (two-way sync)
/// or another player's HES (read-only Hunter Card + A2A).
class HesConnection {
  final String id;
  final String name;
  final String url;
  final String mode; // 'sync' | 'friend' | 'desktop'
  Map<String, dynamic>? card;
  String? lastSynced;

  HesConnection({
    required this.id,
    required this.name,
    required this.url,
    required this.mode,
    this.card,
    this.lastSynced,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'mode': mode,
        if (card != null) 'card': card,
        if (lastSynced != null) 'lastSynced': lastSynced,
      };

  factory HesConnection.fromJson(Map<String, dynamic> m) => HesConnection(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        url: '${m['url'] ?? ''}',
        mode: '${m['mode'] ?? 'friend'}',
        card: m['card'] is Map ? Map<String, dynamic>.from(m['card'] as Map) : null,
        lastSynced: m['lastSynced']?.toString(),
      );
}

/// QR connect & sync for HES:
/// - Connect your own devices by QR or pairing key for authenticated two-way HES sync.
/// - Connect other people's HES instances by QR to view Hunter Cards (rank, level, class, power)
///   and link over A2A without sharing private logs.
/// - Sync with the desktop or VPS by QR, key, or configured Hermes link.
class HesSync {
  HesSync._();
  static final HesSync instance = HesSync._();

  static const _secure = FlutterSecureStorage();
  static const _ownKeyName = 'asm_hes_sync_key';
  static const _peerKeysName = 'asm_hes_peer_keys';

  http.Client? _overrideClient;
  void setClientForTest(http.Client? c) => _overrideClient = c;
  http.Client get _http => _overrideClient ?? _defaultClient;
  final http.Client _defaultClient = http.Client();

  /// Wires `/hes/card` and `/hes/sync` onto the running A2A HTTP server.
  static void install() {
    A2a.hesCardHandler = () => instance.localHunterCard();
    A2a.hesSyncHandler = (key, incoming) => instance.handleIncomingSync(key, incoming);
  }

  /// This device's sync secret (kept in keystore; shared only when you show the "Own device" QR or key).
  Future<String> syncKey() async {
    var k = await _secure.read(key: _ownKeyName);
    if (k == null || k.isEmpty) {
      k = _randomKey();
      await _secure.write(key: _ownKeyName, value: k);
    }
    return k;
  }

  Future<String> rotateSyncKey() async {
    final k = _randomKey();
    await _secure.write(key: _ownKeyName, value: k);
    return k;
  }

  static String _randomKey() {
    final r = Random.secure();
    return 'hsk_${List.generate(20, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  Future<Map<String, String>> _peerKeys() async {
    final raw = await _secure.read(key: _peerKeysName);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _savePeerKey(String id, String key) async {
    final m = await _peerKeys();
    m[id] = key;
    await _secure.write(key: _peerKeysName, value: jsonEncode(m));
  }

  /// Safe public Hunter Card for other players (no private logs, location, or secrets).
  Future<Map<String, dynamic>> localHunterCard() async {
    final s = await AssimilisSettings.get();
    final st = await HesStore.instance.state();
    final title = await HesStore.instance.title();
    final achievements = (HesStore.instance.get('system_achievements') as List? ?? const []).length;
    final quests = (HesStore.instance.get('system_quests') as List? ?? const [])
        .where((q) => q is Map && q['status'] == 'active')
        .length;
    final devId = s.blob('device_id') ?? 'dev-local';
    final devName = s.blob('device_name') ?? (s.userName.isNotEmpty ? "${s.userName}'s phone" : 'Assimilis phone');
    return {
      'id': devId,
      'deviceName': devName,
      'player': s.userName.isNotEmpty ? s.userName : 'Hunter',
      'rank': st.rankName,
      'level': st.level,
      'className': st.className,
      'title': title,
      'power': st.powerValue,
      'activeQuests': quests,
      'achievements': achievements,
      'updated': DateTime.now().toIso8601String(),
    };
  }

  /// Server-side handler for `POST /hes/sync` from one of your own paired devices.
  Future<Map<String, dynamic>> handleIncomingSync(String providedKey, Map<String, dynamic> incoming) async {
    final expected = await syncKey();
    if (providedKey.isEmpty || providedKey != expected) {
      return {'unauthorized': true};
    }
    final doc = incoming['doc'];
    String summary = 'No document sent.';
    if (doc is Map) {
      summary = await HesStore.instance.importMerge(Map<String, dynamic>.from(doc));
    }
    return {
      'ok': true,
      'summary': summary,
      'doc': HesStore.instance.export(),
      'card': await localHunterCard(),
    };
  }

  /// Detects local IPv4 addresses so the QR code advertises a reachable LAN / Tailscale URL.
  Future<List<String>> localAddresses() async {
    final out = <String>[];
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) out.add(addr.address);
        }
      }
    } catch (_) {}
    // Prefer Tailscale 100.x, then private LAN ranges.
    out.sort((a, b) {
      int score(String ip) => ip.startsWith('100.') ? 0 : (ip.startsWith('192.168.') ? 1 : (ip.startsWith('10.') ? 2 : 3));
      return score(a).compareTo(score(b));
    });
    return out;
  }

  /// Builds a QR JSON payload for either `'sync'` (own device, includes sync key) or `'friend'` (Hunter Card only).
  Future<String> buildQrPayload({required String mode, required String host, int port = A2a.port}) async {
    final s = await AssimilisSettings.get();
    final devId = s.blob('device_id') ?? 'dev-local';
    final devName = s.blob('device_name') ?? (s.userName.isNotEmpty ? "${s.userName}'s phone" : 'Assimilis phone');
    final cleanHost = host.trim().replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/+$'), '');
    final url = cleanHost.contains(':') ? 'http://$cleanHost' : 'http://$cleanHost:$port';
    final payload = <String, dynamic>{
      'v': 1,
      'type': 'assimilis_hes',
      'mode': mode == 'sync' ? 'sync' : 'friend',
      'id': devId,
      'name': devName,
      'player': s.userName.isNotEmpty ? s.userName : 'Hunter',
      'url': url,
      if (mode == 'sync') 'key': await syncKey(),
    };
    return jsonEncode(payload);
  }

  /// Compact copyable pairing key string (`ASM1:<base64url>`).
  Future<String> buildPairingKey({required String mode, required String host, int port = A2a.port}) async {
    final raw = await buildQrPayload(mode: mode, host: host, port: port);
    return 'ASM1:${base64Url.encode(utf8.encode(raw))}';
  }

  /// Parses a scanned QR string, `ASM1:...` pairing key, or `assimilis://sync?...` URI.
  static Map<String, dynamic> parsePayload(String input) {
    final s = input.trim();
    if (s.isEmpty) throw FormatException('Empty QR or pairing key.');
    if (s.startsWith('ASM1:')) {
      final decoded = utf8.decode(base64Url.decode(s.substring(5).trim()));
      return Map<String, dynamic>.from(jsonDecode(decoded) as Map);
    }
    if (s.startsWith('{')) {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    }
    if (s.startsWith('assimilis://')) {
      final u = Uri.parse(s);
      return {
        'v': 1,
        'type': 'assimilis_hes',
        'mode': u.queryParameters['mode'] ?? (u.host == 'sync' ? 'sync' : 'desktop'),
        'id': u.queryParameters['id'] ?? 'peer-${DateTime.now().millisecondsSinceEpoch}',
        'name': u.queryParameters['name'] ?? u.queryParameters['url'] ?? 'Assimilis',
        'url': u.queryParameters['url'] ?? '',
        if (u.queryParameters['key'] != null) 'key': u.queryParameters['key'],
      };
    }
    throw FormatException('Unrecognized QR code or pairing key.');
  }

  Future<List<HesConnection>> connections() async {
    final raw = (await AssimilisSettings.get()).blob('hes_connections');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return [for (final m in list) HesConnection.fromJson(Map<String, dynamic>.from(m as Map))];
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveConnection(HesConnection conn) async {
    final list = await connections();
    list.removeWhere((c) => c.id == conn.id);
    list.insert(0, conn);
    await (await AssimilisSettings.get()).setBlob('hes_connections', jsonEncode(list.map((c) => c.toJson()).toList()));
  }

  Future<void> removeConnection(String id) async {
    final list = await connections()..removeWhere((c) => c.id == id);
    await (await AssimilisSettings.get()).setBlob('hes_connections', jsonEncode(list.map((c) => c.toJson()).toList()));
    final keys = await _peerKeys()..remove(id);
    await _secure.write(key: _peerKeysName, value: jsonEncode(keys));
  }

  /// Connects using a scanned QR code or pasted pairing key:
  /// - `sync`: pairs an own device, stores its sync key encrypted, and runs a two-way HES merge.
  /// - `friend`: links another player's HES instance and fetches their public Hunter Card.
  /// - `desktop`: saves desktop/VPS endpoint & encrypted key and runs HES sync.
  Future<String> connectFromPayload(String raw) async {
    final m = parsePayload(raw);
    final mode = '${m['mode'] ?? 'friend'}';
    final url = '${m['url'] ?? ''}'.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) throw Exception('QR payload has no URL.');
    final id = '${m['id'] ?? 'peer-${url.hashCode.abs()}'}';
    final name = '${m['name'] ?? m['player'] ?? Uri.parse(url).host}';
    final key = '${m['key'] ?? ''}'.trim();

    if (mode == 'sync') {
      if (key.isEmpty) throw Exception('Own-device sync QR is missing its sync key.');
      await _savePeerKey(id, key);
      final conn = HesConnection(id: id, name: name, url: url, mode: 'sync');
      await _saveConnection(conn);
      try {
        await A2a.instance.addManual(url);
      } catch (_) {}
      return syncPeer(id);
    }

    if (mode == 'desktop') {
      if (key.isNotEmpty) await _savePeerKey(id, key);
      final conn = HesConnection(id: id, name: name, url: url, mode: 'desktop');
      await _saveConnection(conn);
      return syncWithDesktop(url: url, key: key, connectionId: id);
    }

    // Friend / other player HES instance (read-only Hunter Card + A2A).
    final conn = HesConnection(id: id, name: name, url: url, mode: 'friend');
    await _saveConnection(conn);
    try {
      await A2a.instance.addManual(url);
    } catch (_) {}
    return refreshFriend(id);
  }

  /// Performs authenticated two-way HES sync with a paired own device.
  Future<String> syncPeer(String id) async {
    final list = await connections();
    final conn = list.cast<HesConnection?>().firstWhere((c) => c!.id == id, orElse: () => null);
    if (conn == null) return 'Device not found.';
    final key = (await _peerKeys())[id] ?? '';
    if (key.isEmpty) return 'Missing sync key for ${conn.name}. Re-scan its QR.';

    await HesStore.instance.state();
    final res = await _http
        .post(
          Uri.parse('${conn.url}/hes/sync'),
          headers: {'Content-Type': 'application/json', 'X-Assimilis-Sync-Key': key},
          body: jsonEncode({'doc': HesStore.instance.export()}),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode == 401) throw Exception('${conn.name} rejected the sync key. Re-scan its QR.');
    if (res.statusCode >= 400) throw Exception('${conn.name} returned ${res.statusCode}.');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    var mergeMsg = 'Up to date.';
    if (data['doc'] is Map) {
      mergeMsg = await HesStore.instance.importMerge(Map<String, dynamic>.from(data['doc'] as Map));
    }
    if (data['card'] is Map) conn.card = Map<String, dynamic>.from(data['card'] as Map);
    conn.lastSynced = DateTime.now().toIso8601String();
    await _saveConnection(conn);
    return 'Synced with ${conn.name}. $mergeMsg';
  }

  /// Refreshes a connected player's public HES Hunter Card.
  Future<String> refreshFriend(String id) async {
    final list = await connections();
    final conn = list.cast<HesConnection?>().firstWhere((c) => c!.id == id, orElse: () => null);
    if (conn == null) return 'Player not found.';
    final res = await _http.get(Uri.parse('${conn.url}/hes/card')).timeout(const Duration(seconds: 12));
    if (res.statusCode >= 400) throw Exception('${conn.name} returned ${res.statusCode}.');
    conn.card = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    conn.lastSynced = DateTime.now().toIso8601String();
    await _saveConnection(conn);
    return 'Connected to ${conn.card?['player'] ?? conn.name} (Rank ${conn.card?['rank'] ?? '?'} · Lv.${conn.card?['level'] ?? 1}).';
  }

  /// Syncs HES with a desktop or VPS Assimilis/Hermes server by URL + key (or configured HermesLink).
  Future<String> syncWithDesktop({String? url, String? key, String? connectionId}) async {
    var base = (url ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) base = await HermesLink.instance.url;
    if (base.isEmpty) return 'Configure My Hermes in Settings or enter a desktop/VPS address.';
    final syncToken = (key ?? '').trim();
    if (connectionId != null && syncToken.isNotEmpty) {
      await _savePeerKey(connectionId, syncToken);
    }
    await HesStore.instance.state();
    final res = await _http
        .post(
          Uri.parse('$base/api/hes/sync'),
          headers: {
            'Content-Type': 'application/json',
            'Origin': base,
            if (syncToken.isNotEmpty) 'X-Assimilis-Sync-Key': syncToken,
            if (syncToken.isNotEmpty) 'Authorization': 'Bearer $syncToken',
          },
          body: jsonEncode({'doc': HesStore.instance.export(), 'card': await localHunterCard()}),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('Desktop/VPS rejected the sync key.');
    }
    if (res.statusCode == 404) {
      throw Exception('Reached $base, but it has no /api/hes/sync endpoint yet. Use Export JSON or update the desktop server.');
    }
    if (res.statusCode >= 400) {
      throw Exception('Desktop/VPS returned ${res.statusCode}.');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    var mergeMsg = 'Pushed to desktop/VPS.';
    if (data['doc'] is Map) {
      mergeMsg = await HesStore.instance.importMerge(Map<String, dynamic>.from(data['doc'] as Map));
    }
    final id = connectionId ?? 'desktop-${Uri.parse(base).host}';
    await _saveConnection(HesConnection(
      id: id,
      name: Uri.parse(base).host,
      url: base,
      mode: 'desktop',
      lastSynced: DateTime.now().toIso8601String(),
    ));
    return 'Desktop/VPS synced ($base). $mergeMsg';
  }
}
