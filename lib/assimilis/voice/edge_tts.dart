import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Microsoft Edge "Read aloud" neural TTS, spoken directly from the phone (no server).
/// Same service and voices the Assimilis server uses through the Python `edge-tts` library.
class EdgeTts {
  static const _token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const _chromium = '143.0.3650.75';
  static const _base =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';

  /// Sec-MS-GEC: SHA-256 of Windows file-time ticks (rounded down to 5 minutes) + the client token.
  static String _secMsGec() {
    final secs = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 11644473600;
    final rounded = secs - (secs % 300);
    final ticks = BigInt.from(rounded) * BigInt.from(10000000);
    return sha256.convert(ascii.encode('$ticks$_token')).toString().toUpperCase();
  }

  static String _id() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static String _stamp() =>
      '${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'\.\d+'), '')}Z';

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// Returns MP3 bytes (24 kHz mono), or throws.
  static Future<Uint8List> synthesize(
    String text, {
    String voice = 'en-GB-RyanNeural',
    int ratePercent = -6,
    int pitchHz = -3,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final url = '$_base?TrustedClientToken=$_token&ConnectionId=${_id()}'
        '&Sec-MS-GEC=${_secMsGec()}&Sec-MS-GEC-Version=1-$_chromium';
    final ws = await WebSocket.connect(url, headers: {
      'Pragma': 'no-cache',
      'Cache-Control': 'no-cache',
      'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/${_chromium.split('.').first}.0.0.0 Safari/537.36 Edg/${_chromium.split('.').first}.0.0.0',
      'Accept-Encoding': 'gzip, deflate, br',
      'Accept-Language': 'en-US,en;q=0.9',
      'Cookie': 'muid=${_id().toUpperCase()};',
    }).timeout(timeout);

    final audio = BytesBuilder();
    final done = Completer<Uint8List>();
    final sub = ws.listen((msg) {
      if (msg is String) {
        if (msg.contains('Path:turn.end') && !done.isCompleted) done.complete(audio.takeBytes());
      } else if (msg is List<int>) {
        final b = Uint8List.fromList(msg);
        if (b.length < 2) return;
        final headerLen = (b[0] << 8) | b[1];
        if (b.length < 2 + headerLen) return;
        final header = ascii.decode(b.sublist(2, 2 + headerLen), allowInvalid: true);
        if (header.contains('Path:audio')) audio.add(b.sublist(2 + headerLen));
      }
    }, onError: (e) {
      if (!done.isCompleted) done.completeError(e);
    }, onDone: () {
      if (!done.isCompleted) {
        final bytes = audio.takeBytes();
        bytes.isEmpty ? done.completeError(StateError('Edge TTS closed without audio')) : done.complete(bytes);
      }
    });

    ws.add('X-Timestamp:${_stamp()}\r\nContent-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false",'
        '"wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}\r\n');
    final rate = '${ratePercent >= 0 ? '+' : ''}$ratePercent%';
    final pitch = '${pitchHz >= 0 ? '+' : ''}${pitchHz}Hz';
    ws.add('X-RequestId:${_id()}\r\nContent-Type:application/ssml+xml\r\n'
        'X-Timestamp:${_stamp()}\r\nPath:ssml\r\n\r\n'
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
        "<voice name='$voice'><prosody pitch='$pitch' rate='$rate' volume='+0%'>"
        '${_escape(text)}</prosody></voice></speak>');

    try {
      return await done.future.timeout(timeout);
    } finally {
      await sub.cancel();
      await ws.close();
    }
  }
}
