import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../hub/brand.dart';
import '../../hub/hud.dart';
import 'a2a.dart';

/// Nearby A's: other Assimilis devices this phone can talk to and pass jobs to (A2A).
class DevicesView extends StatefulWidget {
  const DevicesView({super.key});
  @override
  State<DevicesView> createState() => _DevicesViewState();
}

class _DevicesViewState extends State<DevicesView> {
  final a2a = A2a.instance;
  String _policy = 'ask';
  String? _msg;
  final _addr = TextEditingController();

  @override
  void initState() {
    super.initState();
    a2a.policy().then((p) => mounted ? setState(() => _policy = p) : null);
    a2a.scan();
  }

  Future<void> _talk(A2aPeer p) async {
    final c = TextEditingController();
    var skill = 'ask';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Send to ${p.name}', style: AssimilisBrand.body(16, w: FontWeight.w600)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ask', label: Text('Ask A')),
                ButtonSegment(value: 'generate', label: Text('Model')),
                ButtonSegment(value: 'phone_task', label: Text('Use it')),
              ],
              selected: {skill},
              onSelectionChanged: (v) => set(() => skill = v.first),
            ),
            const SizedBox(height: 10),
            TextField(controller: c, autofocus: true, maxLines: 3, decoration: const InputDecoration(hintText: 'Message or task')),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send'))],
        ),
      ),
    );
    if (go != true || c.text.trim().isEmpty) return;
    setState(() => _msg = 'Waiting for ${p.name}…');
    try {
      final r = await a2a.send(p, c.text.trim(), skill: skill);
      setState(() => _msg = '${p.name}: $r');
    } catch (e) {
      setState(() => _msg = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return HudScaffold(
      title: 'Nearby A\'s',
      subtitle: 'AGENT TO AGENT · A2A',
      actions: [IconButton(onPressed: a2a.scan, icon: const Icon(Icons.radar_rounded), tooltip: 'Scan')],
      body: Obx(() {
        final peers = a2a.peers.values.toList()..sort((a, b) => b.score.compareTo(a.score));
        return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 40), children: [
          HudPanel(
            title: 'This device',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(a2a.deviceName, style: AssimilisBrand.body(15, w: FontWeight.w600))),
                TextButton(
                  onPressed: () async {
                    final c = TextEditingController(text: a2a.deviceName);
                    final n = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Device name'),
                        content: TextField(controller: c, autofocus: true),
                        actions: [FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save'))],
                      ),
                    );
                    if (n != null) {
                      await a2a.rename(n);
                      setState(() {});
                    }
                  },
                  child: const Text('Rename'),
                ),
              ]),
              const SizedBox(height: 6),
              Text('Requests from other devices', style: AssimilisBrand.label(10)),
              for (final p in const [
                ('ask', 'Ask me', 'Allow once / Always / Deny for each device'),
                ('allow', 'Allow all', 'Any Assimilis nearby can ask A, use the model and use this phone'),
                ('off', 'Off', 'This device is hidden and accepts nothing'),
              ])
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: p.$1,
                  groupValue: _policy,
                  title: Text(p.$2, style: AssimilisBrand.body(14, w: FontWeight.w600)),
                  subtitle: Text(p.$3, style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
                  onChanged: (v) async {
                    await a2a.setPolicy(v!);
                    await a2a.stop();
                    await a2a.start();
                    setState(() => _policy = v);
                  },
                ),
            ]),
          ),
          HudHeader('Devices', trailing: Text('${peers.length}', style: AssimilisBrand.label(12, color: AssimilisBrand.violetSoft))),
          for (final p in peers)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HudPanel(
                accent: p.card == null ? AssimilisBrand.line : (p.hasBrain ? AssimilisBrand.violet : AssimilisBrand.green),
                padding: const EdgeInsets.all(12),
                onTap: p.card == null ? null : () => _talk(p),
                child: Row(children: [
                  Icon(p.stats['platform'] == 'android' ? Icons.phone_android_rounded : Icons.laptop_rounded,
                      color: p.card == null ? AssimilisBrand.faint : AssimilisBrand.violetSoft),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, style: AssimilisBrand.body(14, w: FontWeight.w600)),
                      Text(
                          p.card == null
                              ? 'Not answering · ${p.url}'
                              : '${p.hasBrain ? 'Brain ready' : 'No brain'} · ${p.hasModel ? 'model ${p.stats['model']}' : 'no local model'} · ${p.ramGb.toStringAsFixed(0)} GB',
                          style: AssimilisBrand.label(10)),
                    ]),
                  ),
                  if (p.manual)
                    IconButton(icon: const Icon(Icons.close_rounded, color: AssimilisBrand.faint, size: 18), onPressed: () => a2a.remove(p)),
                ]),
              ),
            ),
          if (peers.isEmpty)
            const HudNote('No other Assimilis found yet. Open the app on another device on this Wi-Fi, or add one by its Tailscale address below.'),
          const HudHeader('Add by address (Tailscale / LAN)'),
          Row(children: [
            Expanded(child: TextField(controller: _addr, decoration: const InputDecoration(hintText: 'e.g. 100.64.0.7 or laptop.tail1234.ts.net'))),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                final r = await a2a.addManual(_addr.text);
                setState(() => _msg = r);
              },
              child: const Text('Add'),
            ),
          ]),
          if (_msg != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_msg!, style: AssimilisBrand.body(13, color: AssimilisBrand.mint))),
          const HudHeader('Activity'),
          for (final l in a2a.log.take(20)) Text(l, style: AssimilisBrand.label(10)),
          if (a2a.log.isEmpty) const HudNote('Nothing yet.'),
        ]);
      }),
    );
  }
}
