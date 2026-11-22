import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../assimilis/core_graph.dart';
import 'core_orb.dart' show CoreMood;

/// A still frame of the real web Core (rendered from assets/core), shown while the live one loads
/// and wherever a WebView cannot run.
Widget coreStill(double size) => Image.asset('assets/core/core_still.png', width: size, height: size, fit: BoxFit.cover);

/// The real Assimilis Core from the web UI (assets/core: assimilis-core.js + assimilis-eye.js, unchanged),
/// running in a small transparent WebView. Off Android/iOS (tests, screenshots) it shows a still of the same core.
class CoreView extends StatefulWidget {
  final double size;
  final CoreMood mood;
  final double level;
  const CoreView({super.key, this.size = 240, this.mood = CoreMood.idle, this.level = 0});

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  State<CoreView> createState() => CoreViewState();
}

class CoreViewState extends State<CoreView> {
  WebViewController? _c;
  bool _ready = false;

  static String _state(CoreMood m) => switch (m) {
        CoreMood.listening => 'listening',
        CoreMood.thinking => 'thinking',
        CoreMood.speaking => 'speaking',
        CoreMood.idle => 'idle',
      };

  @override
  void initState() {
    super.initState();
    if (!CoreView.supported) return;
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) => r.url.startsWith('file:') || r.url.startsWith('about:')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ))
      ..addJavaScriptChannel('AsmBridge', onMessageReceived: (m) {
        try {
          final d = jsonDecode(m.message);
          if (d['ready'] == true) {
            _ready = true;
            if (mounted) setState(() {});
            _push();
            refreshGraph();
          }
        } catch (_) {}
      })
      ..loadFlutterAsset('assets/core/core.html');
  }

  /// Rebuild the orbits from the phone's current data.
  Future<void> refreshGraph() async {
    if (_c == null || !_ready) return;
    try {
      final g = await CoreGraph.build();
      await _c!.runJavaScript('asm.setGraph(${jsonEncode(g)})');
    } catch (_) {}
  }

  void pause() => _ready ? _c?.runJavaScript('asm.pause()') : null;
  void resume() => _ready ? _c?.runJavaScript('asm.resume()') : null;

  void _push() {
    if (_c == null || !_ready) return;
    _c!.runJavaScript("asm.setState('${_state(widget.mood)}')");
  }

  @override
  void didUpdateWidget(covariant CoreView old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _push();
    if (widget.mood == CoreMood.listening && widget.level != old.level && _ready) {
      _c?.runJavaScript('asm.level(${widget.level.toStringAsFixed(2)})');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_c == null) return ClipOval(child: coreStill(widget.size));
    // Taps go to the Flutter screen (tap the core to talk); the core itself is shown, not dragged.
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(fit: StackFit.expand, children: [
        ClipOval(child: coreStill(widget.size)),
        AnimatedOpacity(
          opacity: _ready ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: IgnorePointer(child: WebViewWidget(controller: _c!)),
        ),
      ]),
    );
  }
}
