import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../hub/brand.dart';
import '../../hub/hud.dart';
import '../links/hermes_link.dart';
import '../settings.dart';
import 'whatsapp_link.dart';

/// WhatsApp screen:
/// - Type your spare Agent number and get an 8-character WhatsApp Linked Devices pairing code.
/// - Set the Receiver number that A & HES message and accept commands from.
class WhatsAppView extends StatefulWidget {
  const WhatsAppView({super.key});
  @override
  State<WhatsAppView> createState() => _WhatsAppViewState();
}

class _WhatsAppViewState extends State<WhatsAppView> {
  final _wa = WhatsAppLink.instance;
  final _agent = TextEditingController();
  final _receiver = TextEditingController();
  final _bridge = TextEditingController();
  final _token = TextEditingController();
  final _testMsg = TextEditingController(text: 'Hello from Assimilis.');
  bool _hesForward = false;
  bool _busy = false;
  String? _pairingCode;
  String? _statusMsg;
  WhatsAppStatus? _status;
  String _hermesUrl = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _agent.dispose();
    _receiver.dispose();
    _bridge.dispose();
    _token.dispose();
    _testMsg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await AssimilisSettings.get();
    _agent.text = await _wa.agentNumber;
    _receiver.text = await _wa.receiverNumber;
    _bridge.text = await _wa.customBridgeUrl;
    _hesForward = await _wa.hesForward;
    _pairingCode = s.blob('wa_last_code');
    if (_pairingCode != null && _pairingCode!.isEmpty) _pairingCode = null;
    _hermesUrl = await HermesLink.instance.url;
    if (mounted) setState(() {});
    await _checkStatus();
  }

  Future<void> _checkStatus() async {
    final st = await _wa.status();
    if (mounted) setState(() => _status = st);
  }

  Future<void> _pair() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusMsg = 'Requesting WhatsApp pairing code…';
    });
    try {
      final res = await _wa.requestPairingCode(
        agent: _agent.text,
        receiver: _receiver.text,
        bridgeUrl: _bridge.text,
        token: _token.text,
      );
      if (!mounted) return;
      setState(() {
        _pairingCode = res.code;
        _statusMsg = res.message;
      });
    } catch (e) {
      if (mounted) setState(() => _statusMsg = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final linked = _status?.connected == true;
    return HudScaffold(
      title: 'WhatsApp',
      subtitle: linked ? 'AGENT LINKED' : 'PAIRING CODE · AGENT & RECEIVER',
      actions: [
        IconButton(
          tooltip: 'Refresh status',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _checkStatus,
        ),
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 48), children: [
        HudPanel(
          title: 'Numbers',
          accent: linked ? AssimilisBrand.mint : AssimilisBrand.violet,
          trailing: Text(
            linked ? 'LINKED' : (_status?.state.toUpperCase() ?? 'NOT LINKED'),
            style: AssimilisBrand.label(10, color: linked ? AssimilisBrand.mint : AssimilisBrand.muted),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _agent,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Agent number (spare, +code)',
                hintText: 'e.g. +1 876 555 0123',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _receiver,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Receiver number (+code)',
                hintText: 'e.g. +1 876 555 0999',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Forward HES alerts to receiver', style: AssimilisBrand.body(13)),
              subtitle: Text('Send System check-ins and urgent quests via WhatsApp when linked',
                  style: AssimilisBrand.body(11, color: AssimilisBrand.muted)),
              value: _hesForward,
              onChanged: (v) async {
                setState(() => _hesForward = v);
                await _wa.saveConfig(agent: _agent.text, receiver: _receiver.text, forwardHes: v);
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _pair,
                  icon: const Icon(Icons.pin_outlined),
                  label: Text(_busy ? 'Requesting…' : 'Get pairing code'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  await _wa.saveConfig(
                    agent: _agent.text,
                    receiver: _receiver.text,
                    bridgeUrl: _bridge.text,
                    token: _token.text,
                    forwardHes: _hesForward,
                  );
                  if (mounted) setState(() => _statusMsg = 'Saved agent and receiver numbers.');
                },
                child: const Text('Save'),
              ),
            ]),
          ]),
        ),

        if (_pairingCode != null) ...[
          const SizedBox(height: 12),
          HudPanel(
            title: 'Pairing code',
            accent: AssimilisBrand.magenta,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  color: AssimilisBrand.graphite,
                  border: Border.all(color: AssimilisBrand.magenta),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: SelectableText(
                  _pairingCode!,
                  style: AssimilisBrand.display(28, color: AssimilisBrand.text, w: FontWeight.w800).copyWith(letterSpacing: 6),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '1. Open WhatsApp on the spare phone (Agent number).\n'
                '2. Tap Linked Devices → Link a device → Link with phone number instead.\n'
                '3. Type the 8-character code above.',
                style: AssimilisBrand.body(12, color: AssimilisBrand.muted),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _pairingCode!));
                      if (mounted) setState(() => _statusMsg = 'Pairing code copied.');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy code'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _checkStatus,
                    icon: const Icon(Icons.verified_outlined, size: 16),
                    label: const Text('Check link'),
                  ),
                ),
              ]),
            ]),
          ),
        ],

        if (_statusMsg != null) ...[
          const SizedBox(height: 10),
          Text(_statusMsg!, style: AssimilisBrand.body(12, color: AssimilisBrand.mint)),
        ],

        const HudHeader('Send test message'),
        HudPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _testMsg,
              decoration: const InputDecoration(labelText: 'Message to receiver number'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    setState(() => _statusMsg = 'Sending…');
                    try {
                      final r = await _wa.sendMessage(_testMsg.text);
                      if (mounted) setState(() => _statusMsg = r);
                    } catch (e) {
                      if (mounted) setState(() => _statusMsg = '$e'.replaceFirst('Exception: ', ''));
                    }
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Send via agent'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final rx = WhatsAppLink.normalizePhone(_receiver.text);
                  if (rx.isEmpty) {
                    setState(() => _statusMsg = 'Enter a receiver number first.');
                    return;
                  }
                  final u = Uri.parse('https://wa.me/$rx?text=${Uri.encodeComponent(_testMsg.text)}');
                  await launchUrl(u, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('wa.me'),
              ),
            ]),
          ]),
        ),

        const HudHeader('Bridge connection'),
        HudPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              _hermesUrl.isEmpty
                  ? 'Leave blank to use My Hermes once configured in Models & keys, or enter a dedicated WhatsApp bridge URL.'
                  : 'Default bridge: My Hermes ($_hermesUrl). Override below if your WhatsApp bridge runs elsewhere.',
              style: AssimilisBrand.body(12, color: AssimilisBrand.muted),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bridge,
              decoration: const InputDecoration(labelText: 'Custom bridge URL (optional)', hintText: 'http://100.64.0.7:8787'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _token,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Bridge token (encrypted)'),
            ),
            if (linked) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () async {
                  final r = await _wa.disconnect();
                  await _checkStatus();
                  if (mounted) setState(() { _pairingCode = null; _statusMsg = r; });
                },
                icon: const Icon(Icons.link_off_rounded, color: AssimilisBrand.red, size: 16),
                label: const Text('Disconnect WhatsApp agent', style: TextStyle(color: AssimilisBrand.red)),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
