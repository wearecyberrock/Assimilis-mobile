import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../hub/brand.dart';
import '../../hub/hud.dart';
import '../settings.dart';
import 'chatgpt_auth.dart';
import 'hermes_link.dart';
import 'shared_providers.dart';

/// Models & Links: which brain A uses, your Hermes on laptop/VPS, ChatGPT sign-in,
/// one shared key list, and the shared model folder.
class LinksView extends StatefulWidget {
  const LinksView({super.key});
  @override
  State<LinksView> createState() => _LinksViewState();
}

class _LinksViewState extends State<LinksView> {
  String _brain = 'auto';
  final _hUrl = TextEditingController();
  final _hPw = TextEditingController();
  String _hModel = '';
  List<String> _hModels = [];
  String? _hMsg;
  bool _gptIn = false;
  String? _gptEmail;
  String _gptModel = ChatGptAuth.models.first;
  String? _gptMsg;
  final _keys = <String, TextEditingController>{};
  final _models = <String, TextEditingController>{};
  String _default = 'openrouter';
  String? _keysMsg;
  String _folder = '';
  int _modelCount = 0;

  @override
  void initState() {
    super.initState();
    for (final p in SharedProviders.all) {
      _keys[p.id] = TextEditingController();
      _models[p.id] = TextEditingController();
    }
    _load();
  }

  Future<void> _load() async {
    final s = await AssimilisSettings.get();
    _brain = s.blob('brain') ?? 'auto';
    _hUrl.text = await HermesLink.instance.url;
    _hModel = await HermesLink.instance.model;
    _gptIn = await ChatGptAuth.instance.signedIn;
    _gptEmail = await ChatGptAuth.instance.email;
    _gptModel = s.blob('chatgpt_model') ?? ChatGptAuth.models.first;
    final keys = await SharedProviders.load();
    for (final p in SharedProviders.all) {
      _keys[p.id]!.text = keys[p.id]?['key'] ?? '';
      _models[p.id]!.text = keys[p.id]?['model'] ?? '';
    }
    _default = await SharedProviders.agentDefault();
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/models');
    _folder = dir.path;
    _modelCount = dir.existsSync() ? dir.listSync().where((f) => RegExp(r'\.(gguf|litertlm|safetensors)$').hasMatch(f.path)).length : 0;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return HudScaffold(
      title: 'Models & Links',
      subtitle: 'ONE BRAIN · ONE KEY LIST · ONE MODEL LIBRARY',
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 40), children: [
        HudPanel(
          title: "A's brain",
          child: Column(children: [
            for (final b in const [
              ('auto', 'Auto', 'Hermes if reachable, then ChatGPT, then API key, then local model'),
              ('hermes', 'My Hermes (laptop / VPS)', 'Uses every model and subscription Hermes has'),
              ('chatgpt', 'ChatGPT subscription', 'Signed in below'),
              ('api', 'API key', 'The default key from the shared list'),
              ('local', 'Local model', 'The GGUF loaded in Chat & Models (offline)'),
            ])
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: b.$1,
                groupValue: _brain,
                title: Text(b.$2, style: AssimilisBrand.body(14, w: FontWeight.w600)),
                subtitle: Text(b.$3, style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
                onChanged: (v) async {
                  setState(() => _brain = v!);
                  await (await AssimilisSettings.get()).setBlob('brain', v!);
                },
              ),
          ]),
        ),
        const HudHeader('My Hermes'),
        HudPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Your laptop or VPS running Assimilis. Use its LAN or Tailscale address, e.g. http://100.x.y.z:8787.',
                style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
            const SizedBox(height: 10),
            TextField(controller: _hUrl, decoration: const InputDecoration(labelText: 'Address')),
            const SizedBox(height: 8),
            TextField(controller: _hPw, obscureText: true, decoration: const InputDecoration(labelText: 'Assimilis password (kept in the keystore)')),
            const SizedBox(height: 8),
            if (_hModels.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _hModels.contains(_hModel) ? _hModel : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Model on Hermes'),
                items: [for (final m in _hModels) DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))],
                onChanged: (v) async {
                  _hModel = v ?? '';
                  await (await AssimilisSettings.get()).setBlob('hermes_model', _hModel);
                },
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    setState(() => _hMsg = 'Connecting…');
                    try {
                      await HermesLink.instance.configure(_hUrl.text, _hPw.text);
                      _hMsg = await HermesLink.instance.test();
                      _hModels = await HermesLink.instance.models();
                    } catch (e) {
                      _hMsg = '$e';
                    }
                    setState(() {});
                  },
                  child: const Text('Connect & test'),
                ),
              ),
            ]),
            if (_hMsg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_hMsg!, style: AssimilisBrand.label(11, color: AssimilisBrand.mint))),
          ]),
        ),
        const HudHeader('ChatGPT subscription'),
        HudPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                _gptIn ? 'Signed in${_gptEmail == null ? '' : ' as $_gptEmail'}.' : 'Sign in with your ChatGPT account (the Codex sign-in Hermes uses).',
                style: AssimilisBrand.body(13)),
            const SizedBox(height: 4),
            Text('Outside OpenAI\'s intended use for other apps; your choice, your account.',
                style: AssimilisBrand.body(11, color: AssimilisBrand.faint)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _gptModel,
              decoration: const InputDecoration(labelText: 'Model'),
              items: [for (final m in ChatGptAuth.models) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) async {
                _gptModel = v!;
                await (await AssimilisSettings.get()).setBlob('chatgpt_model', v);
              },
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    try {
                      _gptMsg = await ChatGptAuth.instance.signIn();
                    } catch (e) {
                      _gptMsg = '$e';
                    }
                    await _load();
                  },
                  child: Text(_gptIn ? 'Sign in again' : 'Sign in with ChatGPT'),
                ),
              ),
              if (_gptIn) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    await ChatGptAuth.instance.signOut();
                    _gptMsg = 'Signed out.';
                    await _load();
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ]),
            if (_gptMsg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_gptMsg!, style: AssimilisBrand.label(11, color: AssimilisBrand.mint))),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Claude and Antigravity subscriptions: use them through My Hermes above.',
                  style: AssimilisBrand.body(11, color: AssimilisBrand.muted)),
            ),
          ]),
        ),
        const HudHeader('Shared API keys'),
        HudPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Enter a key once: Chat & Models, the Workstation, the Phone Agent and A all get it.',
                style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
            for (final p in SharedProviders.all) ...[
              const SizedBox(height: 12),
              Row(children: [
                Radio<String>(value: p.id, groupValue: _default, onChanged: (v) => setState(() => _default = v!)),
                Text(p.label, style: AssimilisBrand.body(14, w: FontWeight.w600)),
                if (_default == p.id) ...[const SizedBox(width: 6), Text('DEFAULT', style: AssimilisBrand.label(9, color: AssimilisBrand.violetSoft))],
              ]),
              TextField(controller: _keys[p.id], obscureText: true, decoration: const InputDecoration(labelText: 'API key')),
              const SizedBox(height: 6),
              TextField(controller: _models[p.id], decoration: InputDecoration(labelText: 'Model (default ${p.defaultModel})')),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final keys = {
                  for (final p in SharedProviders.all)
                    if (_keys[p.id]!.text.trim().isNotEmpty) p.id: {'key': _keys[p.id]!.text.trim(), 'model': _models[p.id]!.text.trim()}
                };
                ProviderContainer? container;
                try {
                  container = ProviderScope.containerOf(context, listen: false);
                } catch (_) {}
                final m = await SharedProviders.save(keys, _default, container);
                setState(() => _keysMsg = m);
              },
              child: const Text('Save & share with all agents'),
            ),
            if (_keysMsg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_keysMsg!, style: AssimilisBrand.label(11, color: AssimilisBrand.mint))),
          ]),
        ),
        const HudHeader('Shared model library'),
        HudPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$_modelCount local model${_modelCount == 1 ? '' : 's'} in one folder, used by Chat & Models, the Workstation and A.',
                style: AssimilisBrand.body(13)),
            const SizedBox(height: 6),
            Text(_folder, style: AssimilisBrand.label(10)),
          ]),
        ),
      ]),
    );
  }
}
