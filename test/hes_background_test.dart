import 'package:assimilis_mobile/assimilis/hes/hes_background.dart';
import 'package:assimilis_mobile/assimilis/hes/phone_signals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final answers = {'wake_time': '06:30', 'quiet_start': '23:00', 'quiet_end': '06:00'};
  DateTime at(int h, int m) => DateTime(2026, 11, 23, h, m);
  int ts(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

  test('quiet hours: the System stays silent', () {
    expect(HesBackground.reasonAt(at(23, 30), {}, answers), isNull);
    expect(HesBackground.reasonAt(at(3, 0), {}, answers), isNull);
  });

  test('a morning briefing once, after waking', () {
    expect(HesBackground.reasonAt(at(6, 40), {}, answers), startsWith('morning'));
    expect(HesBackground.reasonAt(at(6, 40), {'last_morning': '2026-11-23', 'last_think': ts(at(6, 35))}, answers), isNull);
  });

  test('an evening review once, after nine', () {
    final s = {'last_morning': '2026-11-23', 'last_think': ts(at(20, 50))};
    expect(HesBackground.reasonAt(at(21, 10), s, answers), startsWith('evening'));
    expect(HesBackground.reasonAt(at(21, 40), {...s, 'last_evening': '2026-11-23'}, answers), isNull);
  });

  test('check-ins every few hours in between', () {
    final s = {'last_morning': '2026-11-23', 'last_think': ts(at(9, 0))};
    expect(HesBackground.reasonAt(at(11, 0), s, answers), isNull);
    expect(HesBackground.reasonAt(at(12, 5), s, answers), startsWith('check-in'));
    expect(HesBackground.reasonAt(at(10, 5), {...s, 'think_every_hours': 1}, answers), startsWith('check-in'));
  });

  test('phone tools explain themselves where there is no phone', () async {
    expect(PhoneSignals.handles('calendar_add_event'), isTrue);
    expect(await PhoneSignals.runTool('next_alarm', {}), contains('next_alarm'));
    expect(await PhoneSignals.runTool('calendar_events', {}), 'Phone data is not available here.');
  });
}
