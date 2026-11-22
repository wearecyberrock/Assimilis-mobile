import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../hub/brand.dart';
import '../canvas/notes_store.dart';
import '../reminders.dart';
import '../settings.dart';
import 'uwi_client.dart';

/// UWI / Academic: Mona VLE courses, deadlines and announcements on the phone.
class UwiView extends StatefulWidget {
  const UwiView({super.key});
  @override
  State<UwiView> createState() => _UwiViewState();
}

class _UwiViewState extends State<UwiView> {
  Map<String, dynamic>? _snap;
  bool _busy = false;
  String? _msg;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await AssimilisSettings.get();
    _signedIn = s.uwiUser.isNotEmpty && (await s.uwiPassword()).isNotEmpty;
    _snap = await UwiClient.cached();
    if (mounted) setState(() {});
  }

  Future<void> _sync() async {
    setState(() { _busy = true; _msg = null; });
    try {
      _snap = await UwiClient.instance.sync();
      _msg = 'Synced ${(_snap!['courses'] as List).length} courses, ${(_snap!['deadlines'] as List).length} deadlines.';
    } catch (e) {
      _msg = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _signIn() async {
    final s = await AssimilisSettings.get();
    final u = TextEditingController(text: s.uwiUser);
    final p = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AssimilisBrand.navyRaised,
        title: const Text('Mona VLE sign-in', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: u, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'UWI ID / username')),
          TextField(controller: p, obscureText: true, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Password')),
          const SizedBox(height: 8),
          const Text('Stored only on this phone, in the Android keystore.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
      ),
    );
    if (ok != true) return;
    s.uwiUser = u.text;
    if (p.text.isNotEmpty) await s.setUwiPassword(p.text);
    _signedIn = true;
    await _sync();
  }

  @override
  Widget build(BuildContext context) {
    final courses = List<Map>.from(_snap?['courses'] ?? const []);
    final deadlines = List<Map>.from(_snap?['deadlines'] ?? const [])
      ..sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));
    final ann = List<Map>.from(_snap?['announcements'] ?? const []);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AssimilisBrand.navy,
        appBar: AppBar(
          backgroundColor: AssimilisBrand.navy,
          foregroundColor: Colors.white,
          title: const Text('UWI · Academic'),
          actions: [
            IconButton(onPressed: _signIn, icon: const Icon(Icons.person_rounded), tooltip: 'Sign-in'),
            IconButton(
                onPressed: _busy || !_signedIn ? null : _sync,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync_rounded),
                tooltip: 'Sync'),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: AssimilisBrand.violet,
            tabs: [Tab(text: 'Deadlines'), Tab(text: 'Courses'), Tab(text: 'News')],
          ),
        ),
        body: !_signedIn
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Sign in to Mona VLE to see your courses, deadlines and announcements.',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _signIn, child: const Text('Sign in')),
                  ]),
                ),
              )
            : Column(children: [
                if (_msg != null)
                  Padding(padding: const EdgeInsets.all(8), child: Text(_msg!, style: const TextStyle(color: Colors.white70))),
                if (_snap?['synced'] != null)
                  Text('Last sync ${_snap!['synced'].toString().substring(0, 16).replaceAll('T', ' ')}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                Expanded(
                  child: TabBarView(children: [
                    ListView(children: [
                      for (final d in deadlines) _deadline(d),
                      if (deadlines.isEmpty) _empty('No upcoming deadlines.'),
                    ]),
                    ListView(children: [
                      for (final c in courses)
                        ListTile(
                          leading: const Icon(Icons.school_rounded, color: AssimilisBrand.violet),
                          title: Text('${c['code']}', style: const TextStyle(color: Colors.white)),
                          subtitle: Text('${c['name']}', style: const TextStyle(color: Colors.white54)),
                          trailing: IconButton(
                            tooltip: 'Make notebook',
                            icon: const Icon(Icons.note_add_rounded, color: Colors.white70),
                            onPressed: () async {
                              final s = NotesStore.instance;
                              await s.load();
                              if (s.bookNamed('${c['code']}') == null) {
                                final b = await s.addBook('${c['code']}');
                                for (final sec in ['Lectures', 'Tutorials', 'Assignments', 'Exam prep']) {
                                  await s.addSection(b['id'], sec);
                                }
                              }
                              setState(() => _msg = 'Notebook ${c['code']} is in Canvas.');
                            },
                          ),
                          onTap: () => launchUrl(Uri.parse('${c['url']}'), mode: LaunchMode.externalApplication),
                        ),
                      if (courses.isEmpty) _empty('No courses yet. Tap sync.'),
                    ]),
                    ListView(children: [
                      for (final a in ann)
                        ListTile(
                          leading: const Icon(Icons.campaign_rounded, color: AssimilisBrand.violet),
                          title: Text('${a['title']}', style: const TextStyle(color: Colors.white)),
                          subtitle: Text('${a['course']} · ${a['author']}', style: const TextStyle(color: Colors.white54)),
                          onTap: () => launchUrl(Uri.parse('${a['url']}'), mode: LaunchMode.externalApplication),
                        ),
                      if (ann.isEmpty) _empty('No announcements.'),
                    ]),
                  ]),
                ),
              ]),
      ),
    );
  }

  Widget _deadline(Map d) {
    final at = DateTime.tryParse('${d['at']}');
    final left = at?.difference(DateTime.now());
    final soon = left != null && left.inHours < 48;
    return ListTile(
      leading: Icon(d['type'] == 'quiz' ? Icons.quiz_rounded : Icons.assignment_rounded,
          color: soon ? AssimilisBrand.magenta : AssimilisBrand.violet),
      title: Text('${d['name']}', style: const TextStyle(color: Colors.white)),
      subtitle: Text(
          '${d['course'] ?? ''} · ${at == null ? '' : '${at.day}/${at.month} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'}'
          '${left == null ? '' : left.isNegative ? ' · overdue' : ' · ${left.inDays}d ${left.inHours % 24}h left'}',
          style: TextStyle(color: soon ? AssimilisBrand.magenta : Colors.white54)),
      trailing: IconButton(
        tooltip: 'Remind me',
        icon: const Icon(Icons.alarm_add_rounded, color: Colors.white70),
        onPressed: at == null
            ? null
            : () async {
                final msgs = <String>[];
                for (final before in [const Duration(days: 1), const Duration(hours: 3)]) {
                  final when = at.subtract(before);
                  if (when.isAfter(DateTime.now())) {
                    msgs.add(await Reminders.instance.add('${d['course']}: ${d['name']} is due', when, source: 'uwi'));
                  }
                }
                setState(() => _msg = msgs.isEmpty ? 'Too close to set a reminder.' : 'Reminders set 1 day and 3 hours before.');
              },
      ),
      onTap: d['url'] == null ? null : () => launchUrl(Uri.parse('${d['url']}'), mode: LaunchMode.externalApplication),
    );
  }

  Widget _empty(String t) => Padding(
      padding: const EdgeInsets.all(32), child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38)));
}
