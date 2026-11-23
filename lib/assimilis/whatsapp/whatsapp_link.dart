import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../links/hermes_link.dart';
import '../settings.dart';

class WhatsAppPairResult {
  final String code; // formatted XXXX-XXXX
  final String status;
  final String message;
  const WhatsAppPairResult({required this.code, required this.status, required this.message});
}

class WhatsAppStatus {
  final bool connected;
  final String state;
  final String agentNumber;
  final String receiverNumber;
  final String? note;
  const WhatsAppStatus({
    required this.connected,
    required this.state,
    required this.agentNumber,
    required this.receiverNumber,
    this.note,
  });
}

/// WhatsApp agent link:
/// - **Agent number**: a spare WhatsApp number you link with an 8-character pairing code (no QR camera needed).
/// - **Receiver number**: your main WhatsApp number that A & HES message and accept commands from.
/// Talks to your Hermes server's WhatsApp/Baileys bridge (or a custom bridge URL with encrypted bearer token).
class WhatsAppLink {
  WhatsAppLink._();
  static final WhatsAppLink instance = WhatsAppLink._();

  static const _secure = FlutterSecureStorage();
  static const _tokenKey = 'asm_wa_bridge_token';

  http.Client? _overrideClient;
  void setClientForTest(http.Client? c) => _overrideClient = c;
  http.Client get _http => _overrideClient ?? _defaultClient;
  final http.Client _defaultClient = http.Client();

  static String normalizePhone(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

  static String formatPairingCode(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (clean.length == 8) return '${clean.substring(0, 4)}-${clean.substring(4)}';
    return clean;
  }

  Future<String> get agentNumber async => (await AssimilisSettings.get()).blob('wa_agent_number') ?? '';
  Future<String> get receiverNumber async => (await AssimilisSettings.get()).blob('wa_receiver_number') ?? '';
  Future<String> get customBridgeUrl async =>
      ((await AssimilisSettings.get()).blob('wa_bridge_url') ?? '').replaceAll(RegExp(r'/+$'), '');
  Future<bool> get hesForward async => (await AssimilisSettings.get()).blob('wa_hes_forward') == 'true';
  Future<String> get bridgeToken async => await _secure.read(key: _tokenKey) ?? '';

  Future<String> resolvedBridgeUrl() async {
    final custom = await customBridgeUrl;
    if (custom.isNotEmpty) return custom;
    return HermesLink.instance.url;
  }

  Future<void> saveConfig({
    required String agent,
    required String receiver,
    String? bridgeUrl,
    String? token,
    bool? forwardHes,
  }) async {
    final s = await AssimilisSettings.get();
    await s.setBlob('wa_agent_number', normalizePhone(agent));
    await s.setBlob('wa_receiver_number', normalizePhone(receiver));
    if (bridgeUrl != null) {
      await s.setBlob('wa_bridge_url', bridgeUrl.trim().replaceAll(RegExp(r'/+$'), ''));
    }
    if (token != null && token.trim().isNotEmpty) {
      await _secure.write(key: _tokenKey, value: token.trim());
    }
    if (forwardHes != null) {
      await s.setBlob('wa_hes_forward', forwardHes ? 'true' : 'false');
    }
  }

  Future<Map<String, String>> _headers(String base) async {
    final tok = await bridgeToken;
    return {
      'Content-Type': 'application/json',
      'Origin': base,
      if (tok.isNotEmpty) 'Authorization': 'Bearer $tok',
    };
  }

  /// Requests an 8-character WhatsApp Linked Devices pairing code for [agent] and binds [receiver].
  Future<WhatsAppPairResult> requestPairingCode({
    required String agent,
    required String receiver,
    String? bridgeUrl,
    String? token,
  }) async {
    final cleanAgent = normalizePhone(agent);
    final cleanReceiver = normalizePhone(receiver);
    if (cleanAgent.length < 8 || cleanAgent.length > 15) {
      throw Exception('Enter the spare agent number with country code (8–15 digits, e.g. 18765550123).');
    }
    if (cleanReceiver.isNotEmpty && (cleanReceiver.length < 8 || cleanReceiver.length > 15)) {
      throw Exception('Enter the receiver number with country code (8–15 digits).');
    }
    await saveConfig(agent: cleanAgent, receiver: cleanReceiver, bridgeUrl: bridgeUrl, token: token);

    final base = await resolvedBridgeUrl();
    if (base.isEmpty) {
      throw Exception(
        'Numbers saved. To generate a live WhatsApp pairing code, connect My Hermes in Settings or enter a WhatsApp bridge URL below.',
      );
    }

    final payload = jsonEncode({
      'phone': cleanAgent,
      'agent_number': cleanAgent,
      'receiver': cleanReceiver,
      'receiver_number': cleanReceiver,
    });
    final hdrs = await _headers(base);

    http.Response? lastRes;
    for (final path in const ['/api/whatsapp/pair', '/api/channels/whatsapp/pair', '/pair']) {
      final res = await _http
          .post(Uri.parse('$base$path'), headers: hdrs, body: payload)
          .timeout(const Duration(seconds: 25));
      lastRes = res;
      if (res.statusCode == 404) continue;
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw Exception('WhatsApp bridge rejected the credentials (${res.statusCode}).');
      }
      if (res.statusCode >= 400) {
        throw Exception('WhatsApp pairing failed (${res.statusCode}): ${_snippet(res.body)}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final rawCode = '${data['pairing_code'] ?? data['pairingCode'] ?? data['code'] ?? ''}'.trim();
      if (rawCode.isEmpty) {
        throw Exception('Bridge replied without a pairing code: ${_snippet(res.body)}');
      }
      final code = formatPairingCode(rawCode);
      await (await AssimilisSettings.get()).setBlob('wa_last_code', code);
      return WhatsAppPairResult(
        code: code,
        status: '${data['status'] ?? 'pairing'}',
        message: 'Open WhatsApp on the spare phone → Linked Devices → Link a device → Link with phone number instead, and enter $code.',
      );
    }

    throw Exception(
      'Reached $base, but no WhatsApp pairing endpoint was found (${lastRes?.statusCode ?? 'no response'}). '
      'Enable the WhatsApp Baileys bridge on Hermes or set a bridge URL.',
    );
  }

  /// Checks whether the agent number is currently linked on the bridge.
  Future<WhatsAppStatus> status() async {
    final ag = await agentNumber;
    final rx = await receiverNumber;
    final base = await resolvedBridgeUrl();
    if (base.isEmpty) {
      return WhatsAppStatus(
        connected: false,
        state: 'no_bridge',
        agentNumber: ag,
        receiverNumber: rx,
        note: 'Connect My Hermes or a WhatsApp bridge URL to link.',
      );
    }
    final hdrs = await _headers(base);
    for (final path in const ['/api/whatsapp/status', '/api/channels/whatsapp/status', '/status']) {
      try {
        final res = await _http.get(Uri.parse('$base$path'), headers: hdrs).timeout(const Duration(seconds: 10));
        if (res.statusCode == 404) continue;
        if (res.statusCode >= 400) {
          return WhatsAppStatus(connected: false, state: 'error', agentNumber: ag, receiverNumber: rx, note: 'HTTP ${res.statusCode}');
        }
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final connected = d['connected'] == true || d['status'] == 'connected' || d['state'] == 'open';
        return WhatsAppStatus(
          connected: connected,
          state: '${d['status'] ?? d['state'] ?? (connected ? 'connected' : 'disconnected')}',
          agentNumber: ag,
          receiverNumber: rx,
          note: d['message']?.toString(),
        );
      } catch (e) {
        return WhatsAppStatus(connected: false, state: 'offline', agentNumber: ag, receiverNumber: rx, note: '$e');
      }
    }
    return WhatsAppStatus(
      connected: false,
      state: 'not_enabled',
      agentNumber: ag,
      receiverNumber: rx,
      note: 'WhatsApp bridge endpoint not found on $base.',
    );
  }

  /// Sends a WhatsApp message from the linked agent number to [to] (defaults to the configured receiver number).
  Future<String> sendMessage(String text, {String? to}) async {
    final msg = text.trim();
    if (msg.isEmpty) return 'Nothing to send.';
    final target = normalizePhone(to ?? await receiverNumber);
    if (target.isEmpty) return 'Set a receiver WhatsApp number in Settings → WhatsApp first.';
    final base = await resolvedBridgeUrl();
    if (base.isEmpty) return 'No WhatsApp bridge configured. Set up Hermes or a bridge URL in Settings → WhatsApp.';

    final hdrs = await _headers(base);
    final body = jsonEncode({'to': target, 'text': msg, 'message': msg});
    for (final path in const ['/api/whatsapp/send', '/api/channels/whatsapp/send', '/send']) {
      final res = await _http.post(Uri.parse('$base$path'), headers: hdrs, body: body).timeout(const Duration(seconds: 20));
      if (res.statusCode == 404) continue;
      if (res.statusCode >= 400) {
        throw Exception('WhatsApp send failed (${res.statusCode}): ${_snippet(res.body)}');
      }
      return 'Sent WhatsApp message to +$target.';
    }
    throw Exception('WhatsApp send endpoint not found on $base.');
  }

  Future<String> disconnect() async {
    final base = await resolvedBridgeUrl();
    if (base.isNotEmpty) {
      try {
        await _http
            .post(Uri.parse('$base/api/whatsapp/logout'), headers: await _headers(base))
            .timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    await (await AssimilisSettings.get()).setBlob('wa_last_code', '');
    return 'Disconnected WhatsApp agent link.';
  }

  /// Tool schema exposed to A, HES System, Workstation (MCP), Phone Agent, and Team.
  static final schemas = [
    {
      'type': 'function',
      'function': {
        'name': 'whatsapp_send',
        'description': 'Send a WhatsApp message from the linked agent number to the configured receiver number (or a specified E.164 number).',
        'parameters': {
          'type': 'object',
          'properties': {
            'message': {'type': 'string', 'description': 'Text message to send.'},
            'to': {'type': 'string', 'description': 'Optional recipient number with country code; defaults to the configured receiver number.'},
          },
          'required': ['message'],
        },
      },
    },
  ];

  static bool handles(String name) => name == 'whatsapp_send';

  static Future<String> runTool(String name, Map<String, dynamic> a) async {
    if (name == 'whatsapp_send') {
      return instance.sendMessage('${a['message'] ?? ''}', to: a['to']?.toString());
    }
    return 'Unknown WhatsApp tool $name.';
  }

  static String _snippet(String s) => s.length > 180 ? '${s.substring(0, 180)}…' : s;
}
