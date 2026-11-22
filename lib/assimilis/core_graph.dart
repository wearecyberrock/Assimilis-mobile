import 'dart:io';

import 'canvas/notes_store.dart';
import 'hes/hes_store.dart';
import 'links/chatgpt_auth.dart';
import 'links/hermes_link.dart';
import 'links/shared_providers.dart';
import 'models/shared_library.dart';
import 'reminders.dart';
import 'tools.dart';

/// Builds the graph the web Core draws (assimilis-core.js `setGraph`) from what is on this phone:
/// promises = reminders and HES quests, AI brains = linked brains and local models, memory = HES stats,
/// tools = A's tools, records = HES trackers, canvas = Canvas pages, server = Hermes and nodes.
class CoreGraph {
  static Future<Map<String, dynamic>> build() async {
    final rings = <String, List<Map<String, String>>>{
      'promises': [],
      'brains': [],
      'memory': [],
      'tools': [],
      'records': [],
      'canvas': [],
      'server': [],
    };
    final memories = <Map<String, Object>>[];
    void add(String ring, String id, String label, [String sub = '']) =>
        rings[ring]!.add({'id': id, 'label': label, if (sub.isNotEmpty) 'sub': sub});

    try {
      for (final r in await Reminders.instance.list()) {
        add('promises', 'rem-${r.id}', r.title, 'Reminders');
      }
    } catch (_) {}
    try {
      final hes = HesStore.instance;
      for (final q in await hes.quests()) {
        add('promises', 'quest-${q['key']}', '${q['title']}', 'HES quests');
      }
      for (final id in hes.activeModules) {
        add('records', 'mod-$id', '${hes.data?.modules[id]?['name'] ?? id}', 'Trackers');
      }
    } catch (_) {}

    try {
      if (await HermesLink.instance.configured) add('brains', 'brain-hermes', 'My Hermes', 'Linked');
      if (await ChatGptAuth.instance.signedIn) add('brains', 'brain-chatgpt', 'ChatGPT', 'Linked');
      final keys = await SharedProviders.load();
      for (final p in SharedProviders.all) {
        if ((keys[p.id]?['key'] ?? '').isNotEmpty) add('brains', 'brain-${p.id}', p.label, 'API keys');
      }
      for (final f in SharedModelLibrary.files()) {
        add('brains', 'model-${f.path.hashCode}', f.path.split(Platform.pathSeparator).last.split('/').last, 'Local models');
      }
    } catch (_) {}

    try {
      final hes = HesStore.instance;
      final s = await hes.state();
      for (final b in hes.data!.branches) {
        for (final st in (b['stats'] as List)) {
          if (s.assessed.contains(st['id'])) add('memory', 'stat-${st['id']}', '${st['name']} ${s.stats[st['id']]?.toStringAsFixed(1)}', '${b['name']}');
        }
      }
      memories.add({'store': 'hes', 'count': hes.events.length + 1});
    } catch (_) {}

    for (final t in AssimilisTools.schemas) {
      final name = '${(t['function'] as Map)['name']}';
      final group = name.startsWith('hes')
          ? 'HES'
          : RegExp(r'note|calc|deriv|integ').hasMatch(name)
                  ? 'Canvas'
                  : RegExp(r'alarm|timer|remind').hasMatch(name)
                      ? 'Time'
                      : name == 'phone_task'
                          ? 'Phone'
                          : 'Reach';
      add('tools', 'tool-$name', name, group);
    }

    try {
      final notes = NotesStore.instance;
      await notes.load();
      var count = 0;
      for (final e in notes.allPages()) {
        add('canvas', '${e.page['id']}', '${e.page['title']}', '${e.book['name']}');
        count += 1 + ('${e.page['text']}'.length ~/ 400);
      }
      memories.add({'store': 'notes', 'count': count});
    } catch (_) {}

    try {
      if (await HermesLink.instance.configured) {
        add('server', 'srv-hermes', Uri.tryParse(await HermesLink.instance.url)?.host ?? 'Hermes', 'Hermes');
      }
    } catch (_) {}
    add('server', 'srv-phone', 'This phone', 'Devices');

    return {'rings': rings, 'memories': memories, 'links': const []};
  }
}
