import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One model folder for the whole app: <app documents>/models (PrivateLM's folder).
/// Chat & Models, the Workstation and A all read and download here, so a model is downloaded once.
class SharedModelLibrary {
  static String? dir;

  static Future<void> init() async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/models');
    if (!d.existsSync()) d.createSync(recursive: true);
    dir = d.path;
  }

  static final _ext = RegExp(r'\.(gguf|litertlm|safetensors)$', caseSensitive: false);

  /// Model files currently in the shared folder.
  static List<File> files() {
    if (dir == null) return const [];
    final d = Directory(dir!);
    if (!d.existsSync()) return const [];
    return d.listSync().whereType<File>().where((f) => _ext.hasMatch(f.path) && !f.path.endsWith('.part')).toList();
  }

  /// Where a model named [fileName] lives (or will be downloaded to).
  static String pathFor(String fileName) => '${dir ?? '/storage/emulated/0/Download'}/$fileName';
}
