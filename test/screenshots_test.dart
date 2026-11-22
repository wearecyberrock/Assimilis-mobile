// Renders the Assimilis screens and the app icon to PNGs (test/goldens/*.png).
// Run:  flutter test test/screenshots_test.dart --update-goldens
import 'dart:convert';
import 'dart:io';

import 'package:assimilis_mobile/assimilis/canvas/canvas_view.dart';
import 'package:assimilis_mobile/assimilis/canvas/notes_store.dart';
import 'package:assimilis_mobile/assimilis/canvas/page_editor.dart';
import 'package:assimilis_mobile/assimilis/hes/hes_store.dart';
import 'package:assimilis_mobile/assimilis/hes/hes_view.dart';
import 'package:assimilis_mobile/assimilis/links/links_view.dart';
import 'package:assimilis_mobile/assimilis/uwi/uwi_view.dart';
import 'package:assimilis_mobile/assimilis/voice/voice_mode_view.dart';
import 'package:assimilis_mobile/hub/brand.dart';
import 'package:assimilis_mobile/hub/core_orb.dart';
import 'package:assimilis_mobile/hub/hub_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _docs = Directory.systemTemp.createTempSync('asm_shots');

Future<void> _fonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await l.load();
  }

  await load('Orbitron', ['assets/fonts/Orbitron-500.ttf', 'assets/fonts/Orbitron-700.ttf', 'assets/fonts/Orbitron-800.ttf']);
  await load('JetBrainsMono', ['assets/fonts/JetBrainsMono-400.ttf', 'assets/fonts/JetBrainsMono-600.ttf', 'assets/fonts/JetBrainsMono-700.ttf']);
  await load('Inter', ['assets/fonts/Inter-400.ttf', 'assets/fonts/Inter-600.ttf', 'assets/fonts/Inter-700.ttf']);
  await load('Roboto', ['assets/fonts/Inter-400.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/Users/shaki/flutter';
  await load('MaterialIcons', ['$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

void _mockChannels() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => _docs.path);
  final secure = <String, String>{'asm_uwi_pw': 'x'};
  m.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = Map<String, dynamic>.from(c.arguments as Map? ?? {});
    switch (c.method) {
      case 'read':
        return secure[a['key']];
      case 'write':
        secure['${a['key']}'] = '${a['value']}';
        return null;
      case 'readAll':
        return secure;
      default:
        return null;
    }
  });
  m.setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (c) async => 'America/Jamaica');
  for (final ch in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers.global/events', 'xyz.luan/audioplayers']) {
    m.setMockMethodCallHandler(MethodChannel(ch), (c) async => null);
  }
}

Map<String, Object> _prefs() {
  final now = DateTime.now();
  String at(int h) => now.add(Duration(hours: h)).toIso8601String();
  return {
    'asm_uwi_user': '620150000',
    'asm_blob_uwi': jsonEncode({
      'synced': now.toIso8601String(),
      'courses': [
        {'id': 1, 'code': 'COMP2201', 'name': 'Discrete Mathematics for Computer Science', 'url': 'https://vle.mona.uwi.edu'},
        {'id': 2, 'code': 'COMP2140', 'name': 'Software Engineering', 'url': 'https://vle.mona.uwi.edu'},
        {'id': 3, 'code': 'MATH2401', 'name': 'Elements of Mathematical Analysis', 'url': 'https://vle.mona.uwi.edu'},
      ],
      'deadlines': [
        {'id': 1, 'name': 'Assignment 2: Graph proofs', 'type': 'assign', 'course': 'COMP2201', 'at': at(20)},
        {'id': 2, 'name': 'Quiz 4', 'type': 'quiz', 'course': 'MATH2401', 'at': at(52)},
        {'id': 3, 'name': 'Sprint 3 report', 'type': 'assign', 'course': 'COMP2140', 'at': at(130)},
      ],
      'announcements': [
        {'course': 'COMP2201', 'title': 'Tutorial moved to Thursday', 'author': 'Dr. Brown', 'url': 'https://vle.mona.uwi.edu'},
      ],
    }),
    'asm_blob_reminders': jsonEncode([
      {'id': 7, 'title': 'COMP2201: Assignment 2 is due', 'at': at(3), 'repeat': 'none', 'source': 'uwi'},
    ]),
    'asm_blob_hermes_url': 'http://100.64.0.7:8787',
  };
}

Future<void> _shot(WidgetTester t, Widget w, String name, {Duration settle = const Duration(milliseconds: 900)}) async {
  await t.runAsync(() async {
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: AssimilisBrand.theme(), home: w));
    await Future<void>.delayed(const Duration(milliseconds: 600));
  });
  await t.pump(settle);
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await t.pump(const Duration(milliseconds: 100));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _mockChannels();
    SharedPreferences.setMockInitialValues(_prefs());
    await _fonts();
  });

  setUp(() {
    final b = TestWidgetsFlutterBinding.instance;
    b.platformDispatcher.views.first.physicalSize = const Size(1080, 2340);
    b.platformDispatcher.views.first.devicePixelRatio = 3;
  });

  testWidgets('seed data', (t) async {
    await t.runAsync(() async {
      final h = HesStore.instance;
      await h.state();
      if (h.events.isEmpty) {
        await h.quickLog('30 pushups');
        await h.quickLog('25 situps');
        await h.quickLog('studied 45 min');
        await h.quickLog('slept 7 h');
        final q = await h.quests();
        for (final x in q) {
          if ((x['done'] as double) >= (x['target'] as double)) await h.claim(x);
        }
      }
      await NotesStore.instance.load();
    });
  });

  testWidgets('hub', (t) => _shot(t, const HubView(), '01_hub'));
  testWidgets('hes', (t) => _shot(t, const HesView(), '02_hes_status'));
  testWidgets('voice', (t) => _shot(t, const VoiceModeView(introduce: false), '03_voice_A'));
  testWidgets('canvas', (t) => _shot(t, const CanvasView(), '04_canvas'));
  testWidgets('page', (t) async {
    late Map page;
    await t.runAsync(() async {
      await NotesStore.instance.load();
      page = NotesStore.instance.allPages().first.page;
    });
    await _shot(t, Theme(data: AssimilisBrand.theme(), child: PageEditor(page: page)), '05_canvas_page');
  });
  testWidgets('uwi', (t) => _shot(t, const UwiView(), '06_uwi'));
  testWidgets('links', (t) => _shot(t, const LinksView(), '07_models_links'));

  testWidgets('app icon', (t) async {
    final b = TestWidgetsFlutterBinding.instance;
    b.platformDispatcher.views.first.physicalSize = const Size(512, 512);
    b.platformDispatcher.views.first.devicePixelRatio = 1;
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        child: Container(
          width: 512,
          height: 512,
          decoration: BoxDecoration(
            color: AssimilisBrand.graphite,
            borderRadius: BorderRadius.circular(112),
            gradient: const RadialGradient(colors: [Color(0xFF2A1F3D), AssimilisBrand.graphite], radius: 0.8),
          ),
          alignment: Alignment.center,
          child: CustomPaint(size: const Size(470, 470), painter: CorePainter(4.1)),
        ),
      ),
    ));
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/icon_core_512.png'));
  });
}
