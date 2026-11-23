// Renders the Assimilis screens and the app icon to PNGs (test/goldens/*.png).
// Run:  flutter test test/screenshots_test.dart --update-goldens
import 'dart:convert';
import 'dart:io';

import 'package:assimilis_mobile/assimilis/canvas/canvas_view.dart';
import 'package:assimilis_mobile/assimilis/canvas/notes_store.dart';
import 'package:assimilis_mobile/assimilis/canvas/page_editor.dart';
import 'package:assimilis_mobile/assimilis/hes/hes_store.dart';
import 'package:assimilis_mobile/assimilis/hes/hes_view.dart';
import 'package:assimilis_mobile/assimilis/hes/hes_system.dart';
import 'package:assimilis_mobile/assimilis/hes/hes_questionnaire_view.dart';
import 'package:assimilis_mobile/assimilis/links/links_view.dart';
import 'package:assimilis_mobile/assimilis/reach/reach_view.dart';
import 'package:assimilis_mobile/assimilis/reminders_view.dart';
import 'package:assimilis_mobile/assimilis/sync/qr_connect_view.dart';
import 'package:assimilis_mobile/assimilis/uwi/vle_view.dart';
import 'package:assimilis_mobile/assimilis/whatsapp/whatsapp_view.dart';
import 'package:assimilis_mobile/hub/permissions_view.dart';
import 'package:assimilis_mobile/hub/welcome_view.dart';
import 'package:assimilis_mobile/assimilis/voice/voice_mode_view.dart';
import 'package:assimilis_mobile/hub/brand.dart';
import 'package:assimilis_mobile/hub/core_orb.dart';
import 'package:assimilis_mobile/hub/hub_view.dart';
import 'package:assimilis_mobile/hub/shell_view.dart';
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
  final envRoot = Platform.environment['FLUTTER_ROOT'];
  final root = envRoot != null && envRoot.isNotEmpty
      ? envRoot
      : (Directory('/opt/flutter').existsSync() ? '/opt/flutter' : 'C:/Users/shaki/flutter');
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
  // permission_handler: report every permission as granted (1) so the Safety page renders.
  m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), (c) async => c.method == 'checkPermissionStatus' ? 1 : null);
  m.setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (c) async => 'America/Jamaica');
  for (final ch in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers.global/events', 'xyz.luan/audioplayers']) {
    m.setMockMethodCallHandler(MethodChannel(ch), (c) async => null);
  }
}

Map<String, Object> _prefs() {
  final now = DateTime.now();
  String at(int h) => now.add(Duration(hours: h)).toIso8601String();
  return {
    'asm_onboarded': true,
    'asm_user_name': 'Sam',
    'asm_blob_reminders': jsonEncode([
      {'id': 7, 'title': 'Submit the lab report', 'at': at(3), 'repeat': 'none', 'source': 'you'},
      {'id': 8, 'title': 'Gym', 'at': at(20), 'repeat': 'weekdays', 'source': 'you'},
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
      final sys = HesSystem.instance;
      if ((await sys.quests()).isEmpty) {
        final now = DateTime.now();
        await sys.setAnswers({'name': 'Sam', 'wake_time': '06:30'});
        await sys.issue(title: 'Wake before 6:30', type: 'daily', due: now.add(const Duration(hours: 9)), repeat: 'daily', silent: true);
        await sys.issue(title: 'Pushups: 40', module: 'pushups', target: 40, unit: 'reps', type: 'daily', due: now.add(const Duration(hours: 6)), silent: true);
        await sys.issue(title: 'Revise Organic Chemistry for 45 min', detail: 'Exam on Friday. Chapters 4 and 5.', type: 'urgent', due: now.add(const Duration(hours: 3)), silent: true);
        final first = await sys.issue(title: 'Drink 2 L of water', type: 'side', silent: true);
        await sys.complete(first['id']);
        await sys.post('Your sleep was 5.2 h. Recovery is part of training. Lights out by 23:00 tonight.', kind: 'tip', silent: true);
        await sys.askUser('Your calendar shows an exam on Friday. How ready do you feel?', options: ['Ready', 'Halfway', 'Not at all']);
        await sys.addChapter('Chapter 1: The Awakening', 'Before dawn, a window opened in front of Sam. The System had chosen. Thirty push-ups later, the first quest was cleared.');
      }
    });
  });

  testWidgets('hub', (t) => _shot(t, const HubView(), '01_hub'));
  testWidgets('shell hes', (t) => _shot(t, const AppShell(), '10_shell_hes'));
  testWidgets('shell agents', (t) => _shot(t, const AppShell(initial: 2), '11_shell_agents'));
  testWidgets('shell team', (t) => _shot(t, const AppShell(initial: 3), '12_shell_team'));
  testWidgets('shell settings', (t) => _shot(t, const AppShell(initial: 4), '13_shell_settings'));
  testWidgets('hes', (t) => _shot(t, const HesView(initialTab: 'status'), '02_hes_status'));
  testWidgets('hes system', (t) => _shot(t, const HesView(), '14_hes_system'));
  testWidgets('hes quests', (t) => _shot(t, const HesView(initialTab: 'quests'), '15_hes_quests'));
  testWidgets('hes story', (t) => _shot(t, const HesView(initialTab: 'story'), '16_hes_story'));
  testWidgets('hes data', (t) => _shot(t, const HesView(initialTab: 'data'), '17_hes_data', settle: const Duration(seconds: 9)));
  testWidgets('hes awakening', (t) => _shot(t, const HesQuestionnaireView(), '18_hes_awakening'));
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
  testWidgets('reminders', (t) => _shot(t, const RemindersView(), '06_reminders'));
  testWidgets('reach', (t) => _shot(t, const ReachView(), '08_reach'));
  testWidgets('safety', (t) => _shot(t, const PermissionsView(), '09_safety'));
  testWidgets('welcome', (t) => _shot(t, const WelcomeView(), '00_welcome'));
  testWidgets('links', (t) => _shot(t, const LinksView(), '07_models_links'));
  testWidgets('vle', (t) => _shot(t, const VleView(), '19_vle'));
  testWidgets('qr connect', (t) => _shot(t, const QrConnectView(), '20_qr_connect'));
  testWidgets('whatsapp', (t) => _shot(t, const WhatsAppView(), '21_whatsapp'));

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
