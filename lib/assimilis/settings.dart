import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings for the Assimilis core (Jarvis, voice mode, Canvas, HES, UWI, Agent Reach).
/// API keys and the UWI password live in the Android keystore (flutter_secure_storage);
/// everything else in shared preferences.
class AssimilisSettings {
  AssimilisSettings._(this._prefs);
  static AssimilisSettings? _i;
  static const _secure = FlutterSecureStorage();
  final SharedPreferences _prefs;

  static Future<AssimilisSettings> get() async =>
      _i ??= AssimilisSettings._(await SharedPreferences.getInstance());

  // ---- Brain (any OpenAI-compatible endpoint: OpenRouter, OpenAI, DeepSeek, Groq, Ollama, LM Studio ...)
  static const presets = <String, String>{
    'OpenRouter': 'https://openrouter.ai/api/v1',
    'OpenAI': 'https://api.openai.com/v1',
    'DeepSeek': 'https://api.deepseek.com/v1',
    'Groq': 'https://api.groq.com/openai/v1',
    'Gemini': 'https://generativelanguage.googleapis.com/v1beta/openai',
    'Ollama (LAN)': 'http://192.168.1.10:11434/v1',
  };

  String get baseUrl => _prefs.getString('asm_base_url') ?? presets['OpenRouter']!;
  set baseUrl(String v) => _prefs.setString('asm_base_url', v.trim());
  String get model => _prefs.getString('asm_model') ?? 'openai/gpt-oss-120b:free';
  set model(String v) => _prefs.setString('asm_model', v.trim());
  Future<String> apiKey() async => await _secure.read(key: 'asm_api_key') ?? '';
  Future<void> setApiKey(String v) => _secure.write(key: 'asm_api_key', value: v.trim());

  // ---- Voice
  /// 'jarvis' (en-GB-RyanNeural, rate -6%, pitch -3Hz) or 'roamie' (en-US-AndrewMultilingualNeural).
  String get persona => _prefs.getString('asm_persona') ?? 'jarvis';
  set persona(String v) => _prefs.setString('asm_persona', v);
  /// Use Microsoft Edge neural voices (online). Off = phone's own TTS only.
  bool get edgeVoice => _prefs.getBool('asm_edge_voice') ?? true;
  set edgeVoice(bool v) => _prefs.setBool('asm_edge_voice', v);
  /// Short spoken acknowledgements ("On it.") before a slow answer.
  bool get beats => _prefs.getBool('asm_beats') ?? true;
  set beats(bool v) => _prefs.setBool('asm_beats', v);
  /// Keep listening after each answer (hands-free conversation).
  bool get continuous => _prefs.getBool('asm_continuous') ?? true;
  set continuous(bool v) => _prefs.setBool('asm_continuous', v);

  // ---- UWI
  String get uwiUser => _prefs.getString('asm_uwi_user') ?? '';
  set uwiUser(String v) => _prefs.setString('asm_uwi_user', v.trim());
  Future<String> uwiPassword() async => await _secure.read(key: 'asm_uwi_pw') ?? '';
  Future<void> setUwiPassword(String v) => _secure.write(key: 'asm_uwi_pw', value: v);

  // ---- Generic JSON blobs for the on-device stores
  String? blob(String key) => _prefs.getString('asm_blob_$key');
  Future<void> setBlob(String key, String json) => _prefs.setString('asm_blob_$key', json);
}
