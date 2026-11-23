import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/settings_controller.dart';
import '../../services/inference_service.dart';
import '../../workstation/core/db/app_database.dart';
import '../../workstation/core/models/chat_models.dart';
import '../../workstation/features/mcp/application/mcp_controller.dart';
import '../../workstation/features/providers/application/providers_controller.dart';
import '../../workstation/features/providers/domain/provider_types.dart';
import '../agent_loop.dart';
import '../settings.dart';
import 'chatgpt_auth.dart';
import 'hermes_link.dart';
import 'shared_providers.dart';
import 'model_gateway.dart';

/// What one agent is using right now, for the status list in Settings.
class AgentStatus {
  final String id, name, using;
  final bool ready;
  final String? note;
  const AgentStatus(this.id, this.name, this.using, this.ready, [this.note]);
}

/// Every agent keeps its own models and keys ("own"), or uses any model from Settings through the model gateway.
/// Assigning a shared model never deletes the agent's own setting: it is backed up and comes back with "own".
class AgentModels {
  static const agents = [
    ('a', 'A (Assimilis)'),
    ('hes', 'HES System'),
    ('chat', 'Chat & Models'),
    ('workstation', 'Workstation'),
    ('phone', 'Phone Agent'),
  ];

  static const own = 'own';
  static const _gatewayProviderId = 'assimilis-gateway';

  static Future<Map<String, String>> assignments() async {
    final raw = (await AssimilisSettings.get()).blob('agent_models');
    if (raw == null || raw.isEmpty) return {};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  static Future<void> _remember(String agent, String model) async {
    final a = await assignments();
    a[agent] = model;
    await (await AssimilisSettings.get()).setBlob('agent_models', jsonEncode(a));
  }

  /// Points [agent] at [model] (`own` or a gateway id such as `chatgpt/gpt-6-sol`). Returns a message for the UI.
  static Future<String> assign(String agent, String model, ProviderContainer? container) async {
    final s = await AssimilisSettings.get();
    final prev = (await assignments())[agent] ?? own;
    final gw = ModelGateway.baseUrl;
    final token = await ModelGateway.instance.token();
    await ModelGateway.instance.start();
    final name = agents.firstWhere((x) => x.$1 == agent).$2;

    switch (agent) {
      case 'hes':
        break; // the System reads its assignment through endpointFor('hes')
      case 'a':
        if (model == own) {
          await s.setBlob('brain', 'auto');
        } else if (model.startsWith('chatgpt/')) {
          await s.setBlob('brain', 'chatgpt');
          await s.setBlob('chatgpt_model', model.substring(8));
        } else if (model.startsWith('hermes/')) {
          await s.setBlob('brain', 'hermes');
          final m = model.substring(7);
          if (m != 'default') await s.setBlob('hermes_model', m);
        } else if (model.startsWith('local/')) {
          await s.setBlob('brain', 'local');
        } else {
          await s.setBlob('brain', 'api');
          s.baseUrl = gw;
          s.model = model;
          await s.setApiKey(token);
        }

      case 'chat':
        if (!Get.isRegistered<SettingsController>()) return 'Chat & Models is not running.';
        final c = Get.find<SettingsController>();
        if (prev == own && model != own) {
          await s.setBlob('own_chat', jsonEncode({'mode': c.inferenceMode.value, 'provider': c.cloudProvider.value}));
        }
        if (model == own) {
          final b = jsonDecode(s.blob('own_chat') ?? '{}') as Map;
          await c.setCloudProvider('${b['provider'] ?? c.cloudProvider.value}');
          await c.setInferenceMode('${b['mode'] ?? 'local'}');
        } else if (model.startsWith('local/')) {
          await c.setInferenceMode('local');
        } else {
          final i = c.customCloudProfiles.indexWhere((p) => p['baseUrl'] == gw);
          c.customCloudProfileIndex.value = i;
          await c.setCustomCloudConfig(name: 'Assimilis (shared)', baseUrl: gw, apiKey: token, model: model);
          await c.setCloudProvider('custom');
          await c.setInferenceMode('cloud');
        }

      case 'workstation':
        if (container == null) return 'Open Settings from inside the app to change the Workstation.';
        final dao = container.read(appDatabaseProvider).providerConfigsDao;
        final actions = container.read(providerActionsProvider);
        final current = await dao.getDefault();
        if (prev == own && model != own && current != null && current.id != _gatewayProviderId) {
          await s.setBlob('own_workstation', current.id);
        }
        if (model == own) {
          final back = s.blob('own_workstation');
          final all = await dao.getAll();
          if (back != null && all.any((c) => c.id == back)) await actions.setDefault(back);
        } else {
          await actions.saveProvider(
            id: _gatewayProviderId,
            type: ProviderType.custom,
            name: 'Assimilis · $model',
            baseUrl: gw,
            defaultModel: model,
            params: const GenerationParams(),
            apiKey: token,
            makeDefault: true,
          );
        }

      case 'phone':
        final p = await SharedPreferences.getInstance();
        if (prev == own && model != own && p.getString('api_base_url') != gw) {
          await s.setBlob('own_phone', jsonEncode({
            'key': p.getString('api_key') ?? '',
            'url': p.getString('api_base_url') ?? '',
            'model': p.getString('api_model') ?? '',
          }));
        }
        if (model == own) {
          final b = jsonDecode(s.blob('own_phone') ?? '{}') as Map;
          for (final e in {'api_key': b['key'], 'api_base_url': b['url'], 'api_model': b['model']}.entries) {
            final v = '${e.value ?? ''}';
            v.isEmpty ? await p.remove(e.key) : await p.setString(e.key, v);
          }
        } else {
          await p.setString('api_key', token);
          await p.setString('api_base_url', gw);
          await p.setString('api_model', model);
        }
    }
    await _remember(agent, model);
    return model == own ? '$name is back on its own model and keys.' : '$name now uses $model.';
  }

  /// Gives the Workstation every Assimilis tool (HES, phone data, calendar, reminders, notes, reach, devices) as an
  /// MCP server on the model gateway. Safe to call often.
  static Future<void> ensureWorkstationTools(ProviderContainer container) async {
    try {
      await ModelGateway.instance.start();
      final token = await ModelGateway.instance.token();
      final servers = await container.read(appDatabaseProvider).mcpServersDao.watchAll().first;
      if (servers.any((x) => x.id == 'assimilis-tools' && x.url == ModelGateway.mcpUrl)) return;
      await container.read(mcpActionsProvider).saveServer(
            id: 'assimilis-tools',
            name: 'Assimilis (HES, phone, calendar)',
            url: ModelGateway.mcpUrl,
            transport: 'streamableHttp',
            headers: {'Authorization': 'Bearer $token'},
          );
    } catch (_) {}
  }

  /// The endpoint an in-app brain (A's helpers, the HES System, team roles) should call for [agent].
  /// An agent on "own" follows A's brain; "auto" picks the first source that is ready. Null when nothing is.
  static Future<Endpoint?> endpointFor(String agent) async {
    final s = await AssimilisSettings.get();
    final gw = ModelGateway.baseUrl;
    await ModelGateway.instance.start();
    final token = await ModelGateway.instance.token();
    final assigned = (await assignments())[agent] ?? own;
    if (assigned != own) return (base: gw, model: assigned, key: token);
    final inf = Get.isRegistered<InferenceService>() ? Get.find<InferenceService>() : null;
    final local = inf != null && inf.isModelLoaded.value ? 'local/${inf.loadedModelName.value}' : null;
    final chatgpt = 'chatgpt/${s.blob('chatgpt_model') ?? ChatGptAuth.models.first}';
    final hm = await HermesLink.instance.model;
    final hermes = 'hermes/${hm.isEmpty ? 'default' : hm}';
    final key = await s.apiKey();
    switch (s.blob('brain') ?? 'auto') {
      case 'chatgpt':
        return (base: gw, model: chatgpt, key: token);
      case 'hermes':
        return (base: gw, model: hermes, key: token);
      case 'local':
        return local == null ? null : (base: gw, model: local, key: token);
      case 'api':
        return key.isEmpty ? null : (base: s.baseUrl, model: s.model, key: key);
    }
    if (await ChatGptAuth.instance.signedIn) return (base: gw, model: chatgpt, key: token);
    if (key.isNotEmpty) return (base: s.baseUrl, model: s.model, key: key);
    final shared = await SharedProviders.load();
    for (final p in SharedProviders.all) {
      final k = shared[p.id];
      if ((k?['key'] ?? '').isNotEmpty) return (base: gw, model: '${p.id}/${(k?['model'] ?? '').isNotEmpty ? k!['model'] : p.defaultModel}', key: token);
    }
    if (await HermesLink.instance.configured) return (base: gw, model: hermes, key: token);
    if (local != null) return (base: gw, model: local, key: token);
    return null;
  }

  /// What each agent is using, and whether it can answer.
  static Future<List<AgentStatus>> status(ProviderContainer? container) async {
    final a = await assignments();
    final s = await AssimilisSettings.get();
    final inf = Get.isRegistered<InferenceService>() ? Get.find<InferenceService>() : null;
    final localName = inf != null && inf.isModelLoaded.value ? inf.loadedModelName.value : '';
    String tag(String id) => (a[id] ?? own) == own ? 'own' : 'shared';
    final out = <AgentStatus>[];

    // A
    final brain = s.blob('brain') ?? 'auto';
    final aUsing = switch (brain) {
      'chatgpt' => 'ChatGPT · ${s.blob('chatgpt_model') ?? ChatGptAuth.models.first}',
      'hermes' => 'My Hermes${(await HermesLink.instance.model).isEmpty ? '' : ' · ${await HermesLink.instance.model}'}',
      'local' => localName.isEmpty ? 'Local model (none loaded)' : 'Local · $localName',
      'api' => s.model,
      _ => 'Auto: Hermes, then ChatGPT, key, local',
    };
    final aReady = switch (brain) {
      'chatgpt' => await ChatGptAuth.instance.signedIn,
      'hermes' => await HermesLink.instance.configured,
      'local' => localName.isNotEmpty,
      'api' => (await s.apiKey()).isNotEmpty,
      _ => true,
    };
    out.add(AgentStatus('a', 'A (Assimilis)', aUsing, aReady, tag('a')));

    // HES System
    Endpoint? hesEp;
    try {
      hesEp = await endpointFor('hes');
    } catch (_) {}
    out.add(AgentStatus('hes', 'HES System', hesEp == null ? 'No brain yet' : ((a['hes'] ?? own) == own ? 'Same as A · ${hesEp.model}' : hesEp.model),
        hesEp != null, tag('hes')));

    // Chat & Models
    if (Get.isRegistered<SettingsController>()) {
      final c = Get.find<SettingsController>();
      final cloud = c.inferenceMode.value == 'cloud';
      final using = cloud
          ? (c.cloudProvider.value == 'custom' ? '${c.customCloudName.value} · ${c.customCloudModel.value}' : 'Cloud · ${c.cloudProvider.value}')
          : (localName.isEmpty ? 'Local model (none loaded)' : 'Local · $localName');
      out.add(AgentStatus('chat', 'Chat & Models', using, cloud || localName.isNotEmpty, tag('chat')));
    } else {
      out.add(AgentStatus('chat', 'Chat & Models', 'Not started', false, tag('chat')));
    }

    // Workstation
    if (container != null) {
      try {
        final d = await container.read(appDatabaseProvider).providerConfigsDao.getDefault();
        out.add(AgentStatus('workstation', 'Workstation', d == null ? 'No provider yet' : '${d.name} · ${d.defaultModel}', d != null, tag('workstation')));
      } catch (_) {
        out.add(AgentStatus('workstation', 'Workstation', 'Not started', false, tag('workstation')));
      }
    } else {
      out.add(AgentStatus('workstation', 'Workstation', 'Unknown', false, tag('workstation')));
    }

    // Phone Agent
    final p = await SharedPreferences.getInstance();
    final pm = p.getString('api_model') ?? '';
    out.add(AgentStatus('phone', 'Phone Agent', pm.isEmpty ? 'No model yet' : pm, (p.getString('api_key') ?? '').isNotEmpty, tag('phone')));
    return out;
  }
}
