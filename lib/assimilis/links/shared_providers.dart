import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../services/hive_service.dart';
import '../../workstation/core/models/chat_models.dart';
import '../../workstation/features/providers/application/providers_controller.dart';
import '../../workstation/features/providers/domain/provider_types.dart';
import '../settings.dart';

/// One API key list for the whole app. Saving writes each key into every agent's own settings:
/// Chat & Models (PrivateLM, Hive), the Workstation (PocketStrike, as a "· shared" provider),
/// the Phone Agent (its OpenAI-compatible brain) and A (Assimilis brain).
class SharedProvider {
  final String id; // openrouter | openai | anthropic | gemini | deepseek | groq
  final String label;
  final String baseUrl;
  final String defaultModel;
  const SharedProvider(this.id, this.label, this.baseUrl, this.defaultModel);
}

class SharedProviders {
  static const all = [
    SharedProvider('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1', 'openai/gpt-oss-120b:free'),
    SharedProvider('openai', 'OpenAI', 'https://api.openai.com/v1', 'gpt-5.6-sol'),
    SharedProvider('anthropic', 'Anthropic (API key)', 'https://api.anthropic.com/v1', 'claude-sonnet-5-5'),
    SharedProvider('gemini', 'Google Gemini', 'https://generativelanguage.googleapis.com/v1beta/openai', 'gemini-3-flash'),
    SharedProvider('deepseek', 'DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
    SharedProvider('groq', 'Groq', 'https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile'),
  ];

  static const _secure = FlutterSecureStorage();
  static const _k = 'asm_shared_keys';

  /// id -> {key, model}
  static Future<Map<String, Map<String, String>>> load() async {
    final raw = await _secure.read(key: _k);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', Map<String, String>.from(v as Map)));
  }

  /// Which provider the Phone Agent and A use when no Hermes / ChatGPT link is active.
  static Future<String> agentDefault() async => (await AssimilisSettings.get()).blob('shared_default') ?? 'openrouter';

  /// Save the keys and push them into all three agents and A.
  static Future<String> save(Map<String, Map<String, String>> keys, String defaultId, ProviderContainer? container) async {
    await _secure.write(key: _k, value: jsonEncode(keys));
    final s = await AssimilisSettings.get();
    await s.setBlob('shared_default', defaultId);
    final done = <String>[];

    // 1. Chat & Models (PrivateLM)
    if (Get.isRegistered<HiveService>()) {
      final hive = Get.find<HiveService>();
      const map = {
        'openai': AppConstants.keyOpenaiKey,
        'anthropic': AppConstants.keyAnthropicKey,
        'gemini': AppConstants.keyGoogleKey,
        'openrouter': AppConstants.keyOpenRouterKey,
        'deepseek': AppConstants.keyDeepSeekKey,
      };
      for (final e in map.entries) {
        final key = keys[e.key]?['key'] ?? '';
        if (key.isNotEmpty) await hive.setSetting(e.value, key);
      }
      done.add('Chat & Models');
    }

    // 2. Workstation (PocketStrike): one "· shared" provider per key
    if (container != null) {
      final actions = container.read(providerActionsProvider);
      for (final p in all) {
        final key = keys[p.id]?['key'] ?? '';
        if (key.isEmpty) continue;
        final type = switch (p.id) {
          'openai' => ProviderType.openai,
          'anthropic' => ProviderType.anthropic,
          'gemini' => ProviderType.gemini,
          'groq' => ProviderType.groq,
          'openrouter' => ProviderType.openrouter,
          _ => ProviderType.custom,
        };
        await actions.saveProvider(
          id: 'shared-${p.id}',
          type: type,
          name: '${p.label} · shared',
          baseUrl: p.baseUrl,
          defaultModel: keys[p.id]?['model']?.isNotEmpty == true ? keys[p.id]!['model']! : p.defaultModel,
          params: const GenerationParams(),
          apiKey: key,
          makeDefault: p.id == defaultId,
        );
      }
      done.add('Workstation');
    }

    // 3. Phone Agent + 4. A: the default provider
    final def = all.firstWhere((p) => p.id == defaultId, orElse: () => all.first);
    final key = keys[def.id]?['key'] ?? '';
    if (key.isNotEmpty) {
      final model = keys[def.id]?['model']?.isNotEmpty == true ? keys[def.id]!['model']! : def.defaultModel;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_key', key);
      await prefs.setString('api_base_url', def.baseUrl);
      await prefs.setString('api_model', model);
      done.add('Phone Agent');
      s.baseUrl = def.baseUrl;
      s.model = model;
      await s.setApiKey(key);
      done.add('A');
    }
    return done.isEmpty ? 'Saved.' : 'Saved and shared with ${done.join(', ')}.';
  }
}
