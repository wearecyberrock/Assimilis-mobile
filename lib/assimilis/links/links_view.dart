import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../hub/brand.dart';
import '../../hub/hud.dart';
import '../settings.dart';
import '../../core/constants.dart';
import '../../services/hive_service.dart';
import '../../services/inference_service.dart';
import '../models/shared_library.dart';
import 'agent_models.dart';
import 'chatgpt_auth.dart';
import 'chatgpt_sign_in.dart';
import 'model_gateway.dart';
import 'hermes_link.dart';
import 'shared_providers.dart';

/// Models & keys: every agent's models and keys in one place. Each agent shows what it is using and can keep its own
/// setting or use any model here (local, ChatGPT, Hermes, a shared key) through the model gateway.
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
  List<File> _files = [];
  List<AgentStatus> _agents = [];
  String? _agentMsg;
  String? _loading;

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
    try {
      if (SharedModelLibrary.dir == null) await SharedModelLibrary.init();
      _folder = SharedModelLibrary.dir ?? '${(await getApplicationDocumentsDirectory()).path}/models';
      _files = SharedModelLibrary.files();
    } catch (_) {}
    await _status();
  }

  ProviderContainer? get _container {
    try {
      return ProviderScope.containerOf(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> _status() async {
    try {
      _agents = await AgentModels.status(_container);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  /// Picks what an agent uses: its own models and keys, or any model in Settings.
  Future<void> _pick(AgentStatus a) async {
    final models = await ModelGateway.instance.models();
    if (!mounted) return;
    String group(String id) => switch (id.split('/').first) {
          'local' => 'Downloaded on this phone',
          'chatgpt' => 'ChatGPT subscription',
          'hermes' => 'My Hermes (laptop / VPS)',
          _ => 'Shared API keys',
        };
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AssimilisBrand.panel,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
            Text('${a.name} uses…', style: AssimilisBrand.display(14, w: FontWeight.w700)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Its own models & keys'),
              subtitle: const Text("Whatever is set inside the agent's own settings"),
              onTap: () => Navigator.pop(ctx, AgentModels.own),
            ),
            if (models.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Nothing to share yet: load a local model, sign in to ChatGPT, link Hermes or add a key below.',
                    style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
              ),
            for (final g in models.map(group).toSet()) ...[
              HudHeader(g),
              for (final m in models.where((m) => group(m) == g))
                ListTile(
                  dense: true,
                  title: Text(m.substring(m.indexOf('/') + 1), overflow: TextOverflow.ellipsis),
                  subtitle: Text(m.split('/').first),
                  onTap: () => Navigator.pop(ctx, m),
                ),
            ],
          ]),
        ),
      ),
    );
    if (picked == null) return;
    try {
      _agentMsg = await AgentModels.assign(a.id, picked, _container);
    } catch (e) {
      _agentMsg = '$e';
    }
    await _status();
  }

  Future<void> _loadLocal(File f) async {
    if (!Get.isRegistered<InferenceService>()) return;
    final name = f.uri.pathSegments.last;
    setState(() => _loading = name);
    final r = await Get.find<InferenceService>().loadModel(f.path, modelName: name);
    if (!r.startsWith('ERROR') && Get.isRegistered<HiveService>()) {
      final hive = Get.find<HiveService>();
      await hive.setSetting(AppConstants.keyLocalModelPath, f.path);
      await hive.setSetting(AppConstants.keyLocalModelName, name);
    }
    _agentMsg = r.startsWith('ERROR') ? r.replaceFirst('ERROR: ', '') : 'Loaded $name. Any agent can use it as local/$name.';
    _loading = null;
    await _status();
  }

  Widget _agentRow(AgentStatus a) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () => _pick(a),
          child: Row(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: a.ready ? AssimilisBrand.mint : AssimilisBrand.red,
                boxShadow: [BoxShadow(color: (a.ready ? AssimilisBrand.mint : AssimilisBrand.red).withValues(alpha: 0.6), blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.name, style: AssimilisBrand.body(14, w: FontWeight.w600)),
                Text(a.using, maxLines: 1, overflow: TextOverflow.ellipsis, style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
              ]),
            ),
            Text((a.note ?? '').toUpperCase(), style: AssimilisBrand.label(9, color: a.note == 'shared' ? AssimilisBrand.violetSoft : AssimilisBrand.faint)),
            const Icon(Icons.chevron_right_rounded, color: AssimilisBrand.faint),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return HudScaffold(
      title: 'Models & keys',
      subtitle: 'EVERY AGENT · EVERY MODEL · ONE PLACE',
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 40), children: [
        HudPanel(
          title: 'Agents',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Tap an agent to keep its own model and keys, or give it any model below.',
                style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
            const SizedBox(height: 10),
            if (_agents.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
            for (final a in _agents) _agentRow(a),
            if (_agentMsg != null) Text(_agentMsg!, style: AssimilisBrand.label(11, color: AssimilisBrand.mint)),
          ]),
        ),
        const HudHeader('Downloaded models'),
        HudPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('One folder for every agent. Load a model here and any agent can use it, even offline.',
                style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
            const SizedBox(height: 8),
            if (_files.isEmpty) Text('No models downloaded yet. Download them in Chat & Models.', style: AssimilisBrand.body(13)),
            for (final f in _files)
              Builder(builder: (_) {
                final name = f.uri.pathSegments.last;
                final inf = Get.isRegistered<InferenceService>() ? Get.find<InferenceService>() : null;
                final loaded = inf != null && inf.isModelLoaded.value && inf.loadedModelName.value == name;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(loaded ? Icons.memory_rounded : Icons.download_done_rounded,
                      color: loaded ? AssimilisBrand.mint : AssimilisBrand.muted),
                  title: Text(name, overflow: TextOverflow.ellipsis, style: AssimilisBrand.body(13)),
                  subtitle: Text('${(f.lengthSync() / 1e9).toStringAsFixed(2)} GB${loaded ? ' · loaded' : ''}',
                      style: AssimilisBrand.body(11, color: AssimilisBrand.muted)),
                  trailing: _loading == name
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : loaded
                          ? null
                          : TextButton(onPressed: _loading == null ? () => _loadLocal(f) : null, child: const Text('Load')),
                );
              }),
            const SizedBox(height: 4),
            Text(_folder, style: AssimilisBrand.label(10)),
          ]),
        ),
        const HudHeader("A's brain"),
        HudPanel(
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
                _gptIn ? 'Signed in${_gptEmail == null ? '' : ' as $_gptEmail'}.' : 'Sign in with your ChatGPT account: you get a link and a code to type there (the Codex sign-in Hermes uses).',
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
                    _gptMsg = await signInWithChatGpt(context) ?? _gptMsg;
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
              child: Text('Every agent can use it: tap the agent above and pick a chatgpt/ model. Claude and Antigravity subscriptions: use them through My Hermes.',
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
                await _status();
              },
              child: const Text('Save & share with all agents'),
            ),
            if (_keysMsg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_keysMsg!, style: AssimilisBrand.label(11, color: AssimilisBrand.mint))),
          ]),
        ),
      ]),
    );
  }
}
