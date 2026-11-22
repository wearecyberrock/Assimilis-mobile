import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:nsd/nsd.dart' as nsd;

import '../../hub/brand.dart';
import '../../services/device_info_service.dart';
import '../../services/inference_service.dart';
import '../settings.dart';

/// A device running Assimilis that this phone can talk to.
class A2aPeer {
  final String id;
  String name;
  String url; // base, e.g. http://192.168.1.20:47800
  Map<String, dynamic>? card;
  bool manual;
  DateTime? seen;
  A2aPeer({required this.id, required this.name, required this.url, this.card, this.manual = false, this.seen});

  Map<String, dynamic> get stats => Map<String, dynamic>.from(card?['x-assimilis'] ?? const {});
  bool get hasBrain => stats['brain'] == true;
  bool get hasModel => (stats['model'] ?? '').toString().isNotEmpty;
  double get ramGb => ((stats['ramGb'] ?? 0) as num).toDouble();

  /// Higher is better for taking a job: a ready brain, then a loaded model, then RAM.
  double get score => (hasBrain ? 100 : 0) + (hasModel ? 50 : 0) + ramGb;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url, 'manual': manual};
}

/// Agent-to-agent between Assimilis devices, using the open A2A protocol (agent card + JSON-RPC
/// `message/send`). Devices on the same Wi-Fi find each other by mDNS (_assimilis-a2a._tcp); over Tailscale
/// you add a device by its Tailscale name or IP. Each device offers three skills:
///   ask         its A answers with its own brain
///   generate    raw text from the model loaded on that device (heavy jobs go to the strongest device)
///   phone_task  its A operates that device's screen (its own safety gate still applies)
/// Incoming requests follow the owner's policy: ask (Allow once / Always / Deny), allow all, or off.
class A2a {
  A2a._();
  static final A2a instance = A2a._();

  static const port = 47800;
  static const serviceType = '_assimilis-a2a._tcp';

  HttpServer? _server;
  nsd.Registration? _reg;
  nsd.Discovery? _disc;
  final peers = <String, A2aPeer>{}.obs;
  final log = <String>[].obs;
  late String deviceId;
  String deviceName = 'Assimilis device';

  /// Set by the brain so `ask` can answer without importing it here (avoids a cycle).
  static Future<String> Function(String text, {bool allowOffload})? askHandler;
  static Future<String> Function(String task)? phoneTaskHandler;

  Future<String> policy() async => (await AssimilisSettings.get()).blob('a2a_policy') ?? 'ask';
  Future<void> setPolicy(String p) async => (await AssimilisSettings.get()).setBlob('a2a_policy', p);
  Future<Set<String>> _trusted() async =>
      Set<String>.from(jsonDecode((await AssimilisSettings.get()).blob('a2a_trusted') ?? '[]') as List);

  Future<void> start() async {
    final s = await AssimilisSettings.get();
    deviceId = s.blob('device_id') ?? 'dev-${Random.secure().nextInt(1 << 32).toRadixString(36)}';
    await s.setBlob('device_id', deviceId);
    deviceName = s.blob('device_name') ?? (s.userName.isNotEmpty ? "${s.userName}'s phone" : 'Assimilis phone');
    for (final m in (jsonDecode(s.blob('a2a_manual') ?? '[]') as List)) {
      final p = A2aPeer(id: m['id'], name: m['name'], url: m['url'], manual: true);
      peers[p.id] = p;
    }
    if (await policy() == 'off') return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      _server!.listen(_handle);
    } catch (e) {
      _note('Could not open port $port: $e');
      return;
    }
    try {
      _reg = await nsd.register(nsd.Service(
        name: deviceName,
        type: serviceType,
        port: port,
        txt: {'id': Uint8List.fromList(utf8.encode(deviceId)), 'v': Uint8List.fromList(utf8.encode('1'))},
      ));
    } catch (_) {}
    await scan();
  }

  Future<void> stop() async {
    try {
      if (_reg != null) await nsd.unregister(_reg!);
      if (_disc != null) await nsd.stopDiscovery(_disc!);
    } catch (_) {}
    await _server?.close(force: true);
    _server = null;
    _reg = null;
    _disc = null;
  }

  Future<void> rename(String name) async {
    deviceName = name.trim().isEmpty ? deviceName : name.trim();
    await (await AssimilisSettings.get()).setBlob('device_name', deviceName);
    await stop();
    await start();
  }

  void _note(String s) {
    log.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)}  $s');
    if (log.length > 50) log.removeLast();
  }

  // ---------------- What this device can do (its agent card)
  Future<Map<String, dynamic>> card(String host) async {
    final s = await AssimilisSettings.get();
    final hasBrain = (await s.apiKey()).isNotEmpty || (s.blob('hermes_url') ?? '').isNotEmpty;
    String model = '';
    double ram = 0;
    try {
      if (Get.isRegistered<InferenceService>()) {
        final inf = Get.find<InferenceService>();
        if (inf.isModelLoaded.value) model = inf.loadedModelName.value;
      }
      if (Get.isRegistered<DeviceInfoService>()) ram = Get.find<DeviceInfoService>().totalRamGB.value;
    } catch (_) {}
    return {
      'protocolVersion': '0.3.0',
      'name': deviceName,
      'description': 'Assimilis (A) on ${Platform.operatingSystem}: ask it questions, give it jobs, or have it use this device.',
      'url': 'http://$host:$port/a2a',
      'preferredTransport': 'JSONRPC',
      'version': '1.0.0',
      'capabilities': {'streaming': false, 'pushNotifications': false},
      'defaultInputModes': ['text/plain'],
      'defaultOutputModes': ['text/plain'],
      'skills': [
        {'id': 'ask', 'name': 'Ask A', 'description': 'Answer with this device\'s brain and tools.', 'tags': ['chat', 'assistant']},
        {'id': 'generate', 'name': 'Generate', 'description': 'Raw text from the model loaded on this device.', 'tags': ['llm', 'compute']},
        {'id': 'phone_task', 'name': 'Use this device', 'description': 'Operate this device\'s screen to do a task.', 'tags': ['automation']},
      ],
      'x-assimilis': {'id': deviceId, 'brain': hasBrain, 'model': model, 'ramGb': ram, 'platform': Platform.operatingSystem},
    };
  }

  // ---------------- Server
  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.set('Access-Control-Allow-Origin', '*');
    try {
      final host = req.requestedUri.host;
      if (req.method == 'GET' &&
          (req.uri.path == '/.well-known/agent-card.json' || req.uri.path == '/.well-known/agent.json')) {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode(await card(host)));
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/a2a') {
        if (await policy() == 'off') return _rpcError(res, null, -32001, 'This device is not accepting requests.');
        final body = await utf8.decoder.bind(req).take(1 << 20).join();
        final rpc = jsonDecode(body) as Map<String, dynamic>;
        if (rpc['method'] != 'message/send') return _rpcError(res, rpc['id'], -32601, 'Only message/send is supported.');
        final msg = Map<String, dynamic>.from(rpc['params']?['message'] ?? {});
        final text = (msg['parts'] as List? ?? const [])
            .where((p) => p['kind'] == 'text' || p['type'] == 'text')
            .map((p) => '${p['text']}')
            .join('\n')
            .trim();
        final meta = Map<String, dynamic>.from(msg['metadata'] ?? {});
        final skill = '${meta['skill'] ?? 'ask'}';
        final from = '${meta['from'] ?? req.connectionInfo?.remoteAddress.address ?? 'unknown'}';
        final fromId = '${meta['fromId'] ?? from}';
        final hops = ((meta['hops'] ?? 0) as num).toInt();
        if (text.isEmpty) return _rpcError(res, rpc['id'], -32602, 'Send some text.');
        if (!await _allow(fromId, from, skill, text)) {
          _note('Denied $skill from $from');
          return _rpcError(res, rpc['id'], -32003, 'The owner of this device declined.');
        }
        _note('$skill from $from');
        final answer = await _run(skill, text, hops);
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({
          'jsonrpc': '2.0',
          'id': rpc['id'],
          'result': {
            'kind': 'message',
            'role': 'agent',
            'messageId': 'msg-${DateTime.now().microsecondsSinceEpoch}',
            'parts': [
              {'kind': 'text', 'text': answer}
            ],
          },
        }));
        return;
      }
      res.statusCode = 404;
    } catch (e) {
      try {
        _rpcError(res, null, -32603, '$e');
      } catch (_) {}
    } finally {
      await res.close();
    }
  }

  void _rpcError(HttpResponse res, dynamic id, int code, String message) {
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode({'jsonrpc': '2.0', 'id': id, 'error': {'code': code, 'message': message}}));
  }

  Future<String> _run(String skill, String text, int hops) async {
    switch (skill) {
      case 'generate':
        if (!Get.isRegistered<InferenceService>() || !Get.find<InferenceService>().isModelLoaded.value) {
          return 'ERROR: no model is loaded on $deviceName.';
        }
        return Get.find<InferenceService>().generate(prompt: text, source: 'a2a', maxTokens: 1024);
      case 'phone_task':
        if (phoneTaskHandler == null) return 'Phone control is not available on $deviceName.';
        return phoneTaskHandler!(text);
      default:
        if (askHandler == null) return 'A is not ready on $deviceName.';
        // A request that already hopped once is answered here, never passed on again (no loops).
        return askHandler!(text, allowOffload: hops < 1);
    }
  }

  /// The owner's choice for incoming requests.
  Future<bool> _allow(String fromId, String from, String skill, String text) async {
    final p = await policy();
    if (p == 'allow') return true;
    if (p == 'off') return false;
    if ((await _trusted()).contains(fromId)) return true;
    final what = switch (skill) { 'phone_task' => 'use this phone to', 'generate' => 'run on your model:', _ => 'ask A:' };
    final r = await Get.dialog<String>(
      AlertDialog(
        backgroundColor: AssimilisBrand.panel,
        title: Text('$from wants to $what', style: AssimilisBrand.body(16, w: FontWeight.w600)),
        content: Text(text.length > 300 ? '${text.substring(0, 300)}…' : text, style: AssimilisBrand.body(13, color: AssimilisBrand.muted)),
        actions: [
          TextButton(onPressed: () => Get.back(result: 'deny'), child: const Text('Deny')),
          TextButton(onPressed: () => Get.back(result: 'always'), child: const Text('Always')),
          FilledButton(onPressed: () => Get.back(result: 'once'), child: const Text('Allow')),
        ],
      ),
      barrierDismissible: false,
    ).timeout(const Duration(seconds: 60), onTimeout: () {
      if (Get.isDialogOpen == true) Get.back();
      return 'deny';
    });
    if (r == 'always') {
      final t = await _trusted()..add(fromId);
      await (await AssimilisSettings.get()).setBlob('a2a_trusted', jsonEncode(t.toList()));
    }
    return r == 'once' || r == 'always';
  }

  // ---------------- Finding devices
  Future<void> scan() async {
    try {
      if (_disc != null) await nsd.stopDiscovery(_disc!);
      _disc = await nsd.startDiscovery(serviceType, ipLookupType: nsd.IpLookupType.v4);
      _disc!.addServiceListener((svc, status) async {
        final id = svc.txt?['id'] == null ? svc.name ?? '' : utf8.decode(svc.txt!['id']!);
        if (id.isEmpty || id == deviceId) return;
        if (status == nsd.ServiceStatus.lost) {
          if (peers[id]?.manual != true) peers.remove(id);
          return;
        }
        final ip = svc.addresses?.firstOrNull?.address ?? svc.host;
        if (ip == null) return;
        final p = peers[id] ?? A2aPeer(id: id, name: svc.name ?? id, url: 'http://$ip:${svc.port ?? port}');
        p.url = 'http://$ip:${svc.port ?? port}';
        p.seen = DateTime.now();
        peers[id] = p;
        await refresh(p);
      });
    } catch (e) {
      _note('Scan failed: $e');
    }
  }

  /// Add a device by address (Tailscale name/IP or LAN IP), e.g. "100.64.0.7" or "laptop.tailnet.ts.net:47800".
  Future<String> addManual(String address) async {
    var a = address.trim().replaceAll(RegExp(r'/+$'), '');
    if (!a.startsWith('http')) a = 'http://$a';
    final u = Uri.parse(a);
    final base = 'http://${u.host}:${u.hasPort ? u.port : port}';
    final p = A2aPeer(id: 'manual-${u.host}', name: u.host, url: base, manual: true);
    final ok = await refresh(p);
    if (!ok) return 'No Assimilis answered at $base.';
    peers.remove(p.id);
    final id = p.stats['id'] as String? ?? p.id;
    final real = A2aPeer(id: id, name: p.name, url: base, card: p.card, manual: true, seen: DateTime.now());
    peers[id] = real;
    await _saveManual();
    return 'Added ${real.name}.';
  }

  Future<void> remove(A2aPeer p) async {
    peers.remove(p.id);
    await _saveManual();
  }

  Future<void> _saveManual() async => (await AssimilisSettings.get())
      .setBlob('a2a_manual', jsonEncode(peers.values.where((p) => p.manual).map((p) => p.toJson()).toList()));

  /// Fetch a device's agent card. Returns false if it does not answer.
  Future<bool> refresh(A2aPeer p) async {
    try {
      final r = await http.get(Uri.parse('${p.url}/.well-known/agent-card.json')).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return false;
      p.card = Map<String, dynamic>.from(jsonDecode(r.body));
      p.name = '${p.card!['name'] ?? p.name}';
      p.seen = DateTime.now();
      peers.refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------- Client
  Future<String> send(A2aPeer p, String text, {String skill = 'ask', int hops = 0}) async {
    final r = await http
        .post(Uri.parse('${p.url}/a2a'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': DateTime.now().millisecondsSinceEpoch,
              'method': 'message/send',
              'params': {
                'message': {
                  'role': 'user',
                  'messageId': 'msg-${DateTime.now().microsecondsSinceEpoch}',
                  'parts': [
                    {'kind': 'text', 'text': text}
                  ],
                  'metadata': {'skill': skill, 'from': deviceName, 'fromId': deviceId, 'hops': hops + 1},
                },
              },
            }))
        .timeout(const Duration(minutes: 5));
    final d = jsonDecode(r.body);
    if (d['error'] != null) throw Exception('${p.name}: ${d['error']['message']}');
    final parts = (d['result']?['parts'] as List?) ?? (d['result']?['status']?['message']?['parts'] as List?) ?? const [];
    _note('$skill → ${p.name}');
    return parts.where((x) => x['kind'] == 'text').map((x) => '${x['text']}').join('\n').trim();
  }

  A2aPeer? find(String nameOrId) {
    final q = nameOrId.toLowerCase().trim();
    for (final p in peers.values) {
      if (p.id == nameOrId || p.name.toLowerCase() == q) return p;
    }
    for (final p in peers.values) {
      if (p.name.toLowerCase().contains(q)) return p;
    }
    return null;
  }

  /// The strongest reachable device for a job (refreshes cards first).
  Future<A2aPeer?> best({bool needModel = false}) async {
    final list = peers.values.toList();
    await Future.wait(list.map(refresh));
    final ok = list.where((p) => p.card != null && (!needModel || p.hasModel)).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return ok.firstOrNull;
  }
}
