import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../hub/brand.dart';
import '../../hub/core_orb.dart';
import '../../hub/core_view.dart';
import '../brain.dart';
import '../settings.dart';
import 'jarvis_voice.dart';

/// Jarvis voice mode: tap the reactor (or say nothing and type), it listens, thinks, and answers aloud
/// in the Jarvis voice. In continuous mode it keeps the conversation going hands-free.
class VoiceModeView extends StatefulWidget {
  const VoiceModeView({super.key, this.introduce = true});
  final bool introduce;
  @override
  State<VoiceModeView> createState() => _VoiceModeViewState();
}

enum _Phase { idle, listening, thinking, speaking }

class _VoiceModeViewState extends State<VoiceModeView> with SingleTickerProviderStateMixin {
  final _speech = stt.SpeechToText();
  final _voice = JarvisVoice.instance;
  final _brain = AssimilisBrain.instance;
  final _msgs = <BrainMessage>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 8));
  _Phase _phase = _Phase.idle;
  String _partial = '';
  String? _status;
  double _level = 0;
  bool _active = false; // conversation loop running
  StreamSubscription<bool>? _speakSub;

  @override
  void initState() {
    super.initState();
    _speakSub = _voice.speakingStream.stream.listen((on) {
      if (mounted && on) setState(() => _phase = _Phase.speaking);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!MediaQuery.of(context).disableAnimations) _spin.repeat();
      _intro();
    });
  }

  @override
  void dispose() {
    _active = false;
    _speech.stop();
    _voice.stop();
    _speakSub?.cancel();
    _spin.dispose();
    super.dispose();
  }

  static bool _introduced = false;

  /// A introduces itself the first time voice mode opens in a session.
  Future<void> _intro() async {
    if (_introduced || !widget.introduce) return;
    _introduced = true;
    const hello = "Hi, I am Assimilis. You can call me A for short.";
    setState(() => _msgs.add(BrainMessage('assistant', hello)));
    await _voice.speak(hello);
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  Future<void> _listen() async {
    if (!await _speech.initialize(onError: (_) => _afterListen(''))) {
      setState(() => _status = 'Speech recognition is not available. Allow the microphone in Safety & Permissions.');
      return;
    }
    await _voice.stop();
    setState(() { _phase = _Phase.listening; _partial = ''; _status = null; });
    await _speech.listen(
      onResult: (r) {
        setState(() => _partial = r.recognizedWords);
        if (r.finalResult) _afterListen(r.recognizedWords);
      },
      onSoundLevelChange: (l) => setState(() => _level = ((l + 2) / 12).clamp(0, 1)),
      listenOptions: stt.SpeechListenOptions(partialResults: true, listenMode: stt.ListenMode.dictation),
      pauseFor: const Duration(seconds: 2),
      listenFor: const Duration(seconds: 45),
    );
  }

  bool _handled = false;
  Future<void> _afterListen(String words) async {
    if (_handled) return;
    _handled = true;
    Future.delayed(const Duration(milliseconds: 300), () => _handled = false);
    final text = words.trim();
    if (text.isEmpty) {
      setState(() { _phase = _Phase.idle; _active = false; });
      return;
    }
    final l = text.toLowerCase();
    if (RegExp(r'^(stop|goodbye|bye|that.s all|thank you a|thanks a|thank you assimilis|thanks assimilis|thanks jarvis)\b').hasMatch(l)) {
      _active = false;
      setState(() => _msgs.add(BrainMessage('user', text)));
      await _voice.speak('Very good.');
      setState(() => _phase = _Phase.idle);
      return;
    }
    await _send(text);
  }

  Future<void> _send(String text) async {
    final s = await AssimilisSettings.get();
    setState(() {
      _msgs.add(BrainMessage('user', text));
      _phase = _Phase.thinking;
      _partial = '';
    });
    _jump();
    final answer = _brain.ask(text, onStatus: (st) => mounted ? setState(() => _status = st) : null);
    if (s.beats) {
      // Speak a short beat while the brain works (like the desktop Jarvis).
      final beat = await Future.any([answer.then((_) => false), Future.delayed(const Duration(milliseconds: 900), () => true)]);
      if (beat) await _voice.speak(_voice.randomBeat());
    }
    final reply = await answer;
    if (!mounted) return;
    setState(() { _msgs.add(reply); _status = null; });
    _jump();
    await _voice.speak(reply.content);
    if (!mounted) return;
    setState(() => _phase = _Phase.idle);
    if (_active && s.continuous) _listen();
  }

  void _jump() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  void _tapReactor() {
    if (_phase == _Phase.listening) {
      _speech.stop();
    } else if (_phase == _Phase.speaking || _phase == _Phase.thinking) {
      _voice.stop();
      _active = false;
      setState(() => _phase = _Phase.idle);
    } else {
      _active = true;
      _listen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_phase) {
      _Phase.idle => 'Tap the core to talk to A',
      _Phase.listening => _partial.isEmpty ? 'Listening…' : _partial,
      _Phase.thinking => _status ?? 'Thinking…',
      _Phase.speaking => 'Speaking · tap to stop',
    };
    return Scaffold(
      backgroundColor: AssimilisBrand.graphite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text('ASSIMILIS', style: AssimilisBrand.display(16, color: AssimilisBrand.violetSoft).copyWith(letterSpacing: 6, shadows: [const Shadow(color: AssimilisBrand.violet, blurRadius: 14)])),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'New conversation', onPressed: () {
            _brain.reset();
            setState(_msgs.clear);
          }),
          IconButton(icon: const Icon(Icons.tune_rounded), tooltip: 'A settings', onPressed: () => showJarvisSettings(context)),
        ],
      ),
      body: Column(children: [
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _tapReactor,
          child: CoreView(
            size: 300,
            level: _level,
            mood: switch (_phase) {
              _Phase.listening => CoreMood.listening,
              _Phase.thinking => CoreMood.thinking,
              _Phase.speaking => CoreMood.speaking,
              _Phase.idle => CoreMood.idle,
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(label, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 15)),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            itemCount: _msgs.length,
            itemBuilder: (_, i) {
              final m = _msgs[i];
              final me = m.role == 'user';
              return Align(
                alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                  decoration: BoxDecoration(
                    color: me ? AssimilisBrand.violet.withValues(alpha: 0.18) : AssimilisBrand.panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: me ? AssimilisBrand.violet : AssimilisBrand.line),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SelectableText(m.content, style: const TextStyle(color: Colors.white, height: 1.35)),
                    if (m.toolsUsed.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(m.toolsUsed.join(' · '), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ),
                  ]),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _input,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.send,
              onSubmitted: (v) {
                if (v.trim().isEmpty) return;
                _input.clear();
                _active = false;
                _send(v.trim());
              },
              decoration: InputDecoration(
                hintText: 'Or type to A…',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: AssimilisBrand.panel,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.mic_rounded, color: AssimilisBrand.violet),
                  onPressed: _tapReactor,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Brain + voice settings, shared by Jarvis everywhere.
Future<void> showJarvisSettings(BuildContext context) async {
  final s = await AssimilisSettings.get();
  final base = TextEditingController(text: s.baseUrl);
  final model = TextEditingController(text: s.model);
  final key = TextEditingController(text: await s.apiKey());
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AssimilisBrand.navy,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('A · brain (more in Models & Links)', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final e in AssimilisSettings.presets.entries)
                ActionChip(label: Text(e.key), onPressed: () => set(() => base.text = e.value)),
            ]),
            TextField(controller: base, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Base URL (OpenAI-compatible)')),
            TextField(controller: model, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Model')),
            TextField(controller: key, obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'API key (stored in the Android keystore)')),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('No key: Jarvis uses the local model loaded in Chat & Models.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
            const SizedBox(height: 16),
            const Text('Voice', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            RadioListTile(value: 'jarvis', groupValue: s.persona, onChanged: (v) => set(() => s.persona = v!),
                title: const Text('A · JARVIS voice (core voice when Hermes is linked, else Edge Ryan)', style: TextStyle(color: Colors.white))),
            RadioListTile(value: 'roamie', groupValue: s.persona, onChanged: (v) => set(() => s.persona = v!),
                title: const Text('Roamie · en-US Andrew (Edge)', style: TextStyle(color: Colors.white))),
            SwitchListTile(value: s.edgeVoice, onChanged: (v) => set(() => s.edgeVoice = v),
                title: const Text('Neural Edge voice (online)', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Off, or offline: the phone\'s own British voice.', style: TextStyle(color: Colors.white54))),
            SwitchListTile(value: s.beats, onChanged: (v) => set(() => s.beats = v),
                title: const Text('Spoken beats ("On it.")', style: TextStyle(color: Colors.white))),
            SwitchListTile(value: s.continuous, onChanged: (v) => set(() => s.continuous = v),
                title: const Text('Hands-free (keep listening)', style: TextStyle(color: Colors.white))),
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton(onPressed: () => JarvisVoice.instance.speak('Hi, I am Assimilis. You can call me A for short.'), child: const Text('Test voice')),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  s.baseUrl = base.text;
                  s.model = model.text;
                  await s.setApiKey(key.text);
                  if (c.mounted) Navigator.pop(c);
                },
                child: const Text('Save'),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
}
