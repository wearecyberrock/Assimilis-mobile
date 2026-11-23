import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../hub/brand.dart';
import '../../hub/hud.dart';
import '../hes/hes_store.dart';
import '../links/hermes_link.dart';
import 'hes_sync.dart';

/// QR Connect & Sync screen:
/// - My QR: show QR or copyable pairing key for Own Device (full two-way HES sync) or Other Player (Hunter Card + A2A).
/// - Scan / Key: scan a QR code with the camera or paste a pairing key / desktop URL+key.
/// - Connected: manage paired own devices, connected HES players, and Desktop / VPS sync.
class QrConnectView extends StatefulWidget {
  const QrConnectView({super.key});
  @override
  State<QrConnectView> createState() => _QrConnectViewState();
}

class _QrConnectViewState extends State<QrConnectView> {
  final _sync = HesSync.instance;
  String _mode = 'sync'; // 'sync' | 'friend'
  List<String> _ips = [];
  final _host = TextEditingController();
  String _qrData = '';
  String _pairingKey = '';
  final _paste = TextEditingController();
  final _deskUrl = TextEditingController();
  final _deskKey = TextEditingController();
  List<HesConnection> _conns = [];
  bool _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _host.dispose();
    _paste.dispose();
    _deskUrl.dispose();
    _deskKey.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final ips = await _sync.localAddresses();
    final conns = await _sync.connections();
    final hermesUrl = await HermesLink.instance.url;
    if (!mounted) return;
    _ips = ips;
    _host.text = ips.isNotEmpty ? ips.first : '127.0.0.1';
    _deskUrl.text = hermesUrl;
    _conns = conns;
    await _rebuildQr();
  }

  Future<void> _rebuildQr() async {
    final h = _host.text.trim().isEmpty ? '127.0.0.1' : _host.text.trim();
    final qr = await _sync.buildQrPayload(mode: _mode, host: h);
    final key = await _sync.buildPairingKey(mode: _mode, host: h);
    if (!mounted) return;
    setState(() {
      _qrData = qr;
      _pairingKey = key;
    });
  }

  Future<void> _connectPayload(String raw) async {
    if (raw.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _msg = 'Connecting…';
    });
    try {
      final res = await _sync.connectFromPayload(raw);
      final conns = await _sync.connections();
      if (!mounted) return;
      setState(() {
        _conns = conns;
        _msg = res;
        _paste.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _msg = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openScanner() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => Theme(data: AssimilisBrand.theme(), child: const _QrScannerPage()),
      ),
    );
    if (scanned != null && scanned.isNotEmpty) {
      await _connectPayload(scanned);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownDevices = _conns.where((c) => c.mode == 'sync').toList();
    final friends = _conns.where((c) => c.mode == 'friend').toList();

    return DefaultTabController(
      length: 3,
      child: HudScaffold(
        title: 'QR Connect & Sync',
        subtitle: 'HES DEVICES · PLAYERS · DESKTOP / VPS',
        bottom: const TabBar(
          labelColor: AssimilisBrand.violetSoft,
          unselectedLabelColor: AssimilisBrand.muted,
          indicatorColor: AssimilisBrand.violet,
          tabs: [
            Tab(text: 'My QR'),
            Tab(text: 'Scan / Key'),
            Tab(text: 'Connected'),
          ],
        ),
        body: TabBarView(children: [
          // ── Tab 1: My QR
          ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 40), children: [
            HudPanel(
              title: 'Share this HES instance',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'sync', icon: Icon(Icons.sync_lock_rounded, size: 16), label: Text('Own device')),
                    ButtonSegment(value: 'friend', icon: Icon(Icons.badge_outlined, size: 16), label: Text('Other player')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) async {
                    _mode = v.first;
                    await _rebuildQr();
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  _mode == 'sync'
                      ? 'Includes your encrypted sync key for full two-way HES sync. Show only to your own phone, laptop or desktop.'
                      : 'Shares your A2A address and public Hunter Card (rank, level, class, power). Private logs are never shared.',
                  style: AssimilisBrand.body(12, color: AssimilisBrand.muted),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: AssimilisBrand.violet.withValues(alpha: 0.3), blurRadius: 20)],
                    ),
                    child: _qrData.isEmpty
                        ? const SizedBox(width: 210, height: 210, child: Center(child: CircularProgressIndicator()))
                        : QrImageView(
                            data: _qrData,
                            version: QrVersions.auto,
                            size: 210,
                            backgroundColor: Colors.white,
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _host,
                  decoration: const InputDecoration(labelText: 'Advertised IP or Tailscale address'),
                  onChanged: (_) => _rebuildQr(),
                ),
                if (_ips.length > 1) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, children: [
                    for (final ip in _ips)
                      ActionChip(
                        label: Text(ip, style: AssimilisBrand.label(10)),
                        onPressed: () {
                          _host.text = ip;
                          _rebuildQr();
                        },
                      ),
                  ]),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: _pairingKey));
                        if (mounted) setState(() => _msg = 'Pairing key copied.');
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy key'),
                    ),
                  ),
                  if (_mode == 'sync') ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _sync.rotateSyncKey();
                        await _rebuildQr();
                        if (mounted) setState(() => _msg = 'Rotated sync key. Old own-device QRs will need re-scanning.');
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Rotate key'),
                    ),
                  ],
                ]),
              ]),
            ),
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!, style: AssimilisBrand.body(12, color: AssimilisBrand.mint))),
          ]),

          // ── Tab 2: Scan / Key
          ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 40), children: [
            HudPanel(
              title: 'Scan QR code',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  'Scan another phone\'s HES QR, another player\'s Hunter Card QR, or your desktop Assimilis sync QR.',
                  style: AssimilisBrand.body(12, color: AssimilisBrand.muted),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _openScanner,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Open QR scanner'),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            HudPanel(
              title: 'Or paste pairing key / QR text',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _paste,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'ASM1:... or assimilis://sync?... or JSON'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _connectPayload(_paste.text),
                  icon: const Icon(Icons.link_rounded),
                  label: Text(_busy ? 'Connecting…' : 'Connect'),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            HudPanel(
              title: 'Sync with Desktop or VPS',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _deskUrl,
                  decoration: const InputDecoration(labelText: 'Desktop / VPS URL (LAN or Tailscale)', hintText: 'http://100.64.0.7:8787'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _deskKey,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Sync key (stored encrypted)'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() {
                            _busy = true;
                            _msg = 'Syncing with desktop / VPS…';
                          });
                          try {
                            final r = await _sync.syncWithDesktop(url: _deskUrl.text, key: _deskKey.text);
                            final conns = await _sync.connections();
                            if (mounted) setState(() { _conns = conns; _msg = r; });
                          } catch (e) {
                            if (mounted) setState(() => _msg = '$e'.replaceFirst('Exception: ', ''));
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  icon: const Icon(Icons.cloud_sync_rounded),
                  label: const Text('Sync with desktop / VPS'),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () async {
                    await HesStore.instance.state();
                    final raw = const JsonEncoder.withIndent('  ').convert(HesStore.instance.export());
                    await Clipboard.setData(ClipboardData(text: raw));
                    if (mounted) setState(() => _msg = 'Copied full HES JSON backup to clipboard.');
                  },
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Copy HES JSON backup'),
                ),
              ]),
            ),
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!, style: AssimilisBrand.body(12, color: AssimilisBrand.mint))),
          ]),

          // ── Tab 3: Connected
          ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 40), children: [
            const HudHeader('My paired devices (two-way HES sync)'),
            for (final c in ownDevices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: HudPanel(
                  accent: AssimilisBrand.mint,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.devices_rounded, color: AssimilisBrand.mint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.name, style: AssimilisBrand.body(14, w: FontWeight.w600)),
                        Text(c.lastSynced == null ? c.url : 'Synced ${c.lastSynced!.substring(0, 16).replaceAll('T', ' ')}',
                            style: AssimilisBrand.label(10)),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Sync now',
                      icon: const Icon(Icons.sync_rounded, color: AssimilisBrand.mint),
                      onPressed: () async {
                        setState(() => _msg = 'Syncing with ${c.name}…');
                        try {
                          final r = await _sync.syncPeer(c.id);
                          final all = await _sync.connections();
                          if (mounted) setState(() { _conns = all; _msg = r; });
                        } catch (e) {
                          if (mounted) setState(() => _msg = '$e'.replaceFirst('Exception: ', ''));
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close_rounded, size: 18, color: AssimilisBrand.faint),
                      onPressed: () async {
                        await _sync.removeConnection(c.id);
                        final all = await _sync.connections();
                        if (mounted) setState(() => _conns = all);
                      },
                    ),
                  ]),
                ),
              ),
            if (ownDevices.isEmpty) const HudNote('No paired devices yet. Scan your own device QR to keep HES in sync.'),

            const HudHeader('Connected HES players'),
            for (final c in friends)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: HudPanel(
                  accent: AssimilisBrand.violet,
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    RankBadge('${c.card?['rank'] ?? 'E'}', size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${c.card?['player'] ?? c.name}', style: AssimilisBrand.body(14, w: FontWeight.w700)),
                        Text(
                          'Lv.${c.card?['level'] ?? 1} · ${c.card?['className'] ?? 'Hunter'} · Power ${c.card?['power'] ?? 0}',
                          style: AssimilisBrand.label(10, color: AssimilisBrand.violetSoft),
                        ),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Refresh Hunter Card',
                      icon: const Icon(Icons.refresh_rounded, color: AssimilisBrand.violetSoft),
                      onPressed: () async {
                        try {
                          final r = await _sync.refreshFriend(c.id);
                          final all = await _sync.connections();
                          if (mounted) setState(() { _conns = all; _msg = r; });
                        } catch (e) {
                          if (mounted) setState(() => _msg = '$e'.replaceFirst('Exception: ', ''));
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close_rounded, size: 18, color: AssimilisBrand.faint),
                      onPressed: () async {
                        await _sync.removeConnection(c.id);
                        final all = await _sync.connections();
                        if (mounted) setState(() => _conns = all);
                      },
                    ),
                  ]),
                ),
              ),
            if (friends.isEmpty) const HudNote('No connected players yet. Scan another person\'s Hunter Card QR.'),
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!, style: AssimilisBrand.body(12, color: AssimilisBrand.mint))),
          ]),
        ]),
      ),
    );
  }
}

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();
  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  bool _popped = false;

  @override
  Widget build(BuildContext context) {
    return HudScaffold(
      title: 'Scan QR',
      body: MobileScanner(
        onDetect: (capture) {
          if (_popped) return;
          final raw = capture.barcodes.firstOrNull?.rawValue;
          if (raw != null && raw.isNotEmpty) {
            _popped = true;
            Navigator.pop(context, raw);
          }
        },
      ),
    );
  }
}
