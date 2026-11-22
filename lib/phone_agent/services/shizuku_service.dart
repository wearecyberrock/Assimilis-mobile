import 'package:shizuku_api/shizuku_api.dart';
import 'screen_automation_service.dart';

class ShizukuService {
  final ShizukuApi _shizuku = ShizukuApi();
  bool _isAvailable = false;
  bool _hasPermission = false;

  bool get isAvailable => _isAvailable;
  bool get hasPermission => _hasPermission;

  /// Check if Shizuku is installed and running
  Future<bool> checkAvailability() async {
    try {
      _isAvailable = await _shizuku.pingBinder() ?? false;
      if (_isAvailable) {
        _hasPermission = await _shizuku.checkPermission() ?? false;
      }
      return _isAvailable;
    } catch (e) {
      _isAvailable = false;
      _hasPermission = false;
      return false;
    }
  }

  /// Request Shizuku permission
  Future<bool> requestPermission() async {
    if (!_isAvailable) return false;
    try {
      _hasPermission = await _shizuku.requestPermission() ?? false;
      return _hasPermission;
    } catch (e) {
      return false;
    }
  }

  /// Run an ADB shell command via Shizuku
  Future<String> runCommand(String command) async {
    if (!_isAvailable) {
      return 'Shizuku is not running. Please start Shizuku first.';
    }
    if (!_hasPermission) {
      final granted = await requestPermission();
      if (!granted) {
        return 'Shizuku permission denied.';
      }
    }

    // Assimilis Mobile safety gate: shell commands can do anything (pm clear, am, settings,
    // input keyevent ...). In "Ask me" mode only a plain swipe runs unasked; everything else
    // needs Allow on screen. In "Full allow" mode the native side approves at once.
    final isPlainSwipe = RegExp(r'^input swipe( \d+){4,5}$').hasMatch(command.trim());
    final shown = command.length > 80 ? command.substring(0, 80) : command;
    if (!isPlainSwipe &&
        !await ScreenAutomationService.confirmOnDevice(
            'run the shell command "$shown"',
            'Shell commands can change settings, clear app data or act in other apps.')) {
      return 'Error: the person denied this command.';
    }

    try {
      final result = await _shizuku.runCommand(command);
      return result ?? 'Command executed (no output)';
    } catch (e) {
      return 'Error running command: $e';
    }
  }

  /// Toggle WiFi via Shizuku
  Future<String> toggleWifi(bool enable) async {
    return runCommand('svc wifi ${enable ? 'enable' : 'disable'}');
  }

  /// Toggle Bluetooth via Shizuku
  Future<String> toggleBluetooth(bool enable) async {
    return runCommand(
      'cmd bluetooth_manager ${enable ? 'enable' : 'disable'}',
    );
  }

  /// Force stop an app
  Future<String> forceStopApp(String packageName) async {
    return runCommand('am force-stop $packageName');
  }

  /// Clear app data
  Future<String> clearAppData(String packageName) async {
    return runCommand('pm clear $packageName');
  }
}
