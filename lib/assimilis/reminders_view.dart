import 'package:flutter/material.dart';
import 'hes/hes_system.dart';

import '../hub/brand.dart';
import '../hub/hud.dart';
import 'reminders.dart';

/// Alarms, timers and reminders.
class RemindersView extends StatefulWidget {
  const RemindersView({super.key});
  @override
  State<RemindersView> createState() => _RemindersViewState();
}

class _RemindersViewState extends State<RemindersView> {
  final _r = Reminders.instance;
  List<Reminder> _list = [];
  String? _msg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await _r.list();
    if (mounted) setState(() => _list = l);
  }

  Future<void> _alarm() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t == null) return;
    final m = await _r.alarm(t.hour, t.minute, label: 'Assimilis');
    setState(() => _msg = m);
  }

  Future<void> _timer() async {
    final c = TextEditingController(text: '10');
    final mins = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AssimilisBrand.navyRaised,
        title: const Text(
          'Timer (minutes)',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (mins == null || mins <= 0) return;
    final m = await _r.timer(mins * 60);
    setState(() => _msg = m);
  }

  Future<void> _reminder() async {
    final title = TextEditingController();
    var repeat = 'none';
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AssimilisBrand.navyRaised,
          title: const Text('Reminder', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'What'),
              ),
              DropdownButton<String>(
                value: repeat,
                dropdownColor: AssimilisBrand.navyRaised,
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('Once')),
                  DropdownMenuItem(value: 'daily', child: Text('Every day')),
                  DropdownMenuItem(value: 'weekdays', child: Text('Weekdays')),
                  DropdownMenuItem(value: 'weekly', child: Text('Every week')),
                ],
                onChanged: (v) => set(() => repeat = v!),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Set'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    final at = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    // Through HES: wake-up, study and training become quests; others stay reminders that pay when done.
    final m = await HesSystem.instance.remind(title.text.trim(), at, repeat: repeat);
    setState(() => _msg = m);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return HudScaffold(
      title: 'Alarms & Reminders',
      actions: [
        IconButton(
          onPressed: _r.showAlarms,
          icon: const Icon(Icons.alarm_rounded),
          tooltip: 'Clock alarms',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: _btn(Icons.alarm_add_rounded, 'Alarm', _alarm)),
              const SizedBox(width: 8),
              Expanded(child: _btn(Icons.timer_rounded, 'Timer', _timer)),
              const SizedBox(width: 8),
              Expanded(
                child: _btn(
                  Icons.notification_add_rounded,
                  'Reminder',
                  _reminder,
                ),
              ),
            ],
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _msg!,
                style: const TextStyle(color: AssimilisBrand.mint),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            'Tip: say "Jarvis, remind me to submit COMP2201 tomorrow at 9" or "wake me at 6:30".',
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 16),
          for (final r in _list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HudPanel(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: ListTile(
                  leading: Icon(
                    r.source == 'hes'
                        ? Icons.military_tech_rounded
                        : Icons.notifications_active_rounded,
                    color: AssimilisBrand.violet,
                  ),
                  title: Text(
                    r.title,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '${r.at.day}/${r.at.month} ${r.at.hour.toString().padLeft(2, '0')}:${r.at.minute.toString().padLeft(2, '0')}'
                    '${r.repeat == 'none' ? '' : ' · ${r.repeat}'}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white54,
                    ),
                    onPressed: () async {
                      await _r.cancel(r.id);
                      _load();
                    },
                  ),
                ),
              ),
            ),
          if (_list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No reminders yet.',
                style: TextStyle(color: Colors.white38),
              ),
            ),
        ],
      ),
    );
  }

  Widget _btn(IconData i, String t, VoidCallback f) => FilledButton.tonalIcon(
    style: FilledButton.styleFrom(
      backgroundColor: AssimilisBrand.navyRaised,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14),
    ),
    onPressed: f,
    icon: Icon(i, color: AssimilisBrand.violet),
    label: Text(t),
  );
}
