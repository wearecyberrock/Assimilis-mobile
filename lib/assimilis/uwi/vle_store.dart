import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../settings.dart';

/// One UWI Mona VLE (Moodle) account stored encrypted in the device keystore.
class VleAccount {
  final String id;
  final String label;
  final String username;
  final String password;
  final String baseUrl;

  const VleAccount({
    required this.id,
    required this.label,
    required this.username,
    required this.password,
    this.baseUrl = defaultBaseUrl,
  });

  static const defaultBaseUrl = 'https://vle.mona.uwi.edu';

  /// Safe metadata without password (for logs, tools, and UI labels).
  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'label': label,
        'baseUrl': baseUrl,
      };

  Map<String, dynamic> toSecureJson() => {
        'id': id,
        'label': label,
        'username': username,
        'password': password,
        'baseUrl': baseUrl,
      };

  factory VleAccount.fromJson(Map<String, dynamic> m) => VleAccount(
        id: '${m['id'] ?? ''}',
        label: '${m['label'] ?? ''}',
        username: '${m['username'] ?? ''}',
        password: '${m['password'] ?? ''}',
        baseUrl: '${m['baseUrl'] ?? defaultBaseUrl}'.replaceAll(RegExp(r'/+$'), ''),
      );
}

/// Multi-user encrypted store for UWI Mona VLE credentials.
/// Every account's username and password live exclusively inside [FlutterSecureStorage]
/// (Android Keystore / EncryptedSharedPreferences), never in plain SharedPreferences.
class VleStore {
  VleStore._();
  static final VleStore instance = VleStore._();

  static const _secure = FlutterSecureStorage();
  static const _accountsKey = 'asm_vle_accounts_v1';

  static String _newId() {
    final r = Random.secure();
    return 'vle-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 16).toRadixString(36)}';
  }

  Future<List<VleAccount>> listAccounts() async {
    final raw = await _secure.read(key: _accountsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return [for (final m in list) VleAccount.fromJson(Map<String, dynamic>.from(m as Map))];
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAccounts(List<VleAccount> accounts) async {
    await _secure.write(
      key: _accountsKey,
      value: jsonEncode([for (final a in accounts) a.toSecureJson()]),
    );
  }

  Future<String?> activeAccountId() async {
    final id = (await AssimilisSettings.get()).blob('vle_active_id');
    final list = await listAccounts();
    if (list.isEmpty) return null;
    if (id != null && list.any((a) => a.id == id)) return id;
    return list.first.id;
  }

  Future<void> setActiveAccount(String id) async {
    await (await AssimilisSettings.get()).setBlob('vle_active_id', id);
  }

  Future<VleAccount?> activeAccount() async {
    final id = await activeAccountId();
    if (id == null) return null;
    final list = await listAccounts();
    return list.cast<VleAccount?>().firstWhere((a) => a!.id == id, orElse: () => null);
  }

  Future<VleAccount?> findAccount(String? idOrLabel) async {
    final list = await listAccounts();
    if (list.isEmpty) return null;
    if (idOrLabel == null || idOrLabel.trim().isEmpty) return activeAccount();
    final q = idOrLabel.trim().toLowerCase();
    for (final a in list) {
      if (a.id.toLowerCase() == q || a.label.toLowerCase() == q) return a;
    }
    for (final a in list) {
      if (a.label.toLowerCase().contains(q)) return a;
    }
    return null;
  }

  /// Adds a new encrypted account or updates an existing one (preserving its password if [password] is empty on edit).
  Future<VleAccount> saveAccount({
    String? id,
    required String label,
    required String username,
    required String password,
    String baseUrl = VleAccount.defaultBaseUrl,
  }) async {
    final list = await listAccounts();
    final cleanUrl = baseUrl.trim().isEmpty ? VleAccount.defaultBaseUrl : baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final idx = id == null ? -1 : list.indexWhere((a) => a.id == id);
    final acc = VleAccount(
      id: idx >= 0 ? list[idx].id : (id ?? _newId()),
      label: label.trim().isEmpty ? 'Student ${list.length + 1}' : label.trim(),
      username: username.trim(),
      password: (password.isEmpty && idx >= 0) ? list[idx].password : password,
      baseUrl: cleanUrl,
    );
    if (idx >= 0) {
      list[idx] = acc;
    } else {
      list.add(acc);
    }
    await _saveAccounts(list);
    await setActiveAccount(acc.id);
    return acc;
  }

  Future<void> removeAccount(String id) async {
    final list = await listAccounts()..removeWhere((a) => a.id == id);
    await _saveAccounts(list);
    await (await AssimilisSettings.get()).setBlob('vle_cache_$id', '');
    final active = (await AssimilisSettings.get()).blob('vle_active_id');
    if (active == id) {
      await (await AssimilisSettings.get()).setBlob('vle_active_id', list.isEmpty ? '' : list.first.id);
    }
  }

  Future<void> saveSnapshot(String accountId, Map<String, dynamic> snap) async {
    await (await AssimilisSettings.get()).setBlob('vle_cache_$accountId', jsonEncode(snap));
  }

  Future<Map<String, dynamic>?> snapshot(String accountId) async {
    final raw = (await AssimilisSettings.get()).blob('vle_cache_$accountId');
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }
}
