import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../links/hermes_link.dart';
import '../settings.dart';
import 'edge_tts.dart';

/// The Jarvis voice (from assimilis-jarvis.js): Edge `en-GB-RyanNeural`, rate -6%, pitch -3Hz.
/// Roamie: `en-US-AndrewMultilingualNeural`. Offline, it falls back to the phone's own
/// British-English voice at a matching rate and pitch.
class JarvisVoice {
  JarvisVoice._();
  static final JarvisVoice instance = JarvisVoice._();

  static const personas = {
    'jarvis': (voice: 'en-GB-RyanNeural', rate: -6, pitch: -3, locale: 'en-GB', name: 'A'),
    'roamie': (voice: 'en-US-AndrewMultilingualNeural', rate: 0, pitch: 0, locale: 'en-US', name: 'Roamie'),
  };

  /// Short acknowledgements spoken while the brain thinks (same list as the desktop Jarvis).
  static const beats = [
    'One sec.', 'On it.', 'Hang on.', 'Got it.', 'Okay.', 'Sure.', 'Right.', 'Alright.', 'Checking.',
    "Let's see.", 'Sure thing.', 'Coming up.', 'One moment.', 'Bear with.', 'Will do.', 'Roger.', 'Righto.',
  ];

  // Created on first use, so screens that never speak do not start audio engines.
  late final _player = AudioPlayer();
  late final _tts = FlutterTts();
  bool _used = false;
  final _cache = <String, Uint8List>{};
  bool _ttsReady = false;
  Completer<void>? _speaking;

  /// Emits true while speaking (drives the arc-reactor animation).
  final speakingStream = StreamController<bool>.broadcast();

  Future<void> _initTts(String locale, int rate, int pitch) async {
    await _tts.setLanguage(locale);
    // Prefer a male en-GB voice if the phone has one.
    try {
      final voices = (await _tts.getVoices as List?) ?? const [];
      final match = voices.cast<Map>().firstWhere(
            (v) =>
                '${v['locale']}'.toLowerCase().startsWith(locale.toLowerCase()) &&
                '${v['name']}'.toLowerCase().contains(RegExp(r'male|gbb|gbd|rjs|ryan')),
            orElse: () => const {},
          );
      if (match.isNotEmpty) {
        await _tts.setVoice({'name': '${match['name']}', 'locale': '${match['locale']}'});
      }
    } catch (_) {}
    await _tts.setSpeechRate(0.5 * (1 + rate / 100));
    await _tts.setPitch((1 + pitch / 40).clamp(0.5, 2.0));
    await _tts.awaitSpeakCompletion(true);
    _ttsReady = true;
  }

  String randomBeat() => beats[Random().nextInt(beats.length)];

  Future<void> stop() async {
    if (_used) {
      try {
        await _player.stop();
        await _tts.stop();
      } catch (_) {}
    }
    _speaking?.complete();
    _speaking = null;
    speakingStream.add(false);
  }

  /// Speak and wait until finished.
  Future<void> speak(String text) async {
    final clean = _speechText(text);
    if (clean.isEmpty) return;
    await stop();
    _used = true;
    final s = await AssimilisSettings.get();
    final p = personas[s.persona] ?? personas['jarvis']!;
    speakingStream.add(true);
    try {
      // 1. The core's own voice from your Hermes (Fish JARVIS if the server has a key, else its Edge voice).
      if (s.blob('voice_source') != 'phone' && await HermesLink.instance.configured) {
        try {
          final key = 'core|$clean';
          final bytes = _cache[key] ?? await HermesLink.instance.speak(clean, persona: s.persona);
          if (bytes != null && bytes.isNotEmpty) {
            _cache[key] = bytes;
            await _play(bytes);
            return;
          }
        } catch (_) {}
      }
      // 2. Edge Ryan straight from the phone.
      if (s.edgeVoice) {
        try {
          final key = '${p.voice}|$clean';
          final bytes = _cache[key] ??
              await EdgeTts.synthesize(clean, voice: p.voice, ratePercent: p.rate, pitchHz: p.pitch);
          if (_cache.length > 40) _cache.remove(_cache.keys.first);
          _cache[key] = bytes;
          await _play(bytes);
          return;
        } catch (_) {
          // Offline or Edge changed its handshake: fall through to the phone voice.
        }
      }
      if (!_ttsReady) await _initTts(p.locale, p.rate, p.pitch);
      await _tts.speak(clean);
    } finally {
      speakingStream.add(false);
    }
  }

  Future<void> _play(Uint8List bytes) async {
    _speaking = Completer<void>();
    final c = _speaking!;
    late StreamSubscription sub;
    sub = _player.onPlayerComplete.listen((_) {
      if (!c.isCompleted) c.complete();
      sub.cancel();
    });
    await _player.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
    await c.future;
  }

  /// Same idea as the desktop's SpeechText filter: don't read out code, URLs or markdown.
  static String _speechText(String t) {
    var s = t.replaceAll(RegExp(r'```[\s\S]*?```'), ' (code on screen) ');
    s = s.replaceAll(RegExp(r'https?://\S+'), ' link ');
    s = s.replaceAll(RegExp(r'[*_#>`|]'), '');
    s = s.replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), ' (equation on screen) ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > 1200 ? '${s.substring(0, 1200)}…' : s;
  }
}

