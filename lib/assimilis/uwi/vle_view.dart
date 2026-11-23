import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../hub/brand.dart';
import '../../hub/hud.dart';
import '../canvas/notes_store.dart';
import '../hes/hes_system.dart';
import 'vle_client.dart';
import 'vle_store.dart';

/// Multi-user UWI Mona VLE scanner UI (HES-styled).
/// Supports storing multiple users' encrypted accounts on the device, switching between them,
/// scanning courses/deadlines/announcements/resources, creating Canvas books, and adding deadlines to HES.
class VleView extends StatefulWidget {
  const VleView({super.key});
  @override
  State<VleView> createState() => _VleViewState();
}

class _VleViewState extends State<VleView> {
  final _store = VleStore.instance;
  List<VleAccount> _accounts = [];
  VleAccount? _active;
  Map<String, dynamic>? _snap;
  bool _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _store.listAccounts();
    final active = await _store.activeAccount();
    final snap = active == null ? null : await _store.snapshot(active.id);
    if (!mounted) return;
    setState(() {
      _accounts = list;
      _active = active;
      _snap = snap;
    });
  }

  Future<void> _scan() async {
    final acc = _active;
    if (acc == null || _busy) return;
    setState(() {
      _busy = true;
      _msg = 'Scanning ${acc.label}…';
    });
    try {
      final snap = await VleClient.instance.scan(acc);
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _msg = 'Scanned ${(snap['courses'] as List).length} courses, '
            '${(snap['deadlines'] as List).length} deadlines, '
            '${(snap['resources'] as List).length} resources.';
      });
    } catch (e) {
      if (mounted) setState(() => _msg = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editAccount([VleAccount? existing]) async {
    final label = TextEditingController(text: existing?.label ?? '');
    final user = TextEditingController(text: existing?.username ?? '');
    final pass = TextEditingController();
    final url = TextEditingController(text: existing?.baseUrl ?? VleAccount.defaultBaseUrl);

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AssimilisBrand.panel,
        title: Text(existing == null ? 'Add VLE account' : 'Edit ${existing.label}', style: AssimilisBrand.body(16, w: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: label, decoration: const InputDecoration(labelText: 'Account label (e.g. Shakir, Guest)')),
            const SizedBox(height: 8),
            TextField(controller: user, decoration: const InputDecoration(labelText: 'UWI ID / username')),
            const SizedBox(height: 8),
            TextField(
              controller: pass,
              obscureText: true,
              decoration: InputDecoration(labelText: existing == null ? 'Password' : 'Password (leave blank to keep)'),
            ),
            const SizedBox(height: 8),
            TextField(controller: url, decoration: const InputDecoration(labelText: 'VLE URL')),
            const SizedBox(height: 8),
            Text(
              'Stored encrypted on this device in the Android keystore. Read-only scan; never submits anything.',
              style: AssimilisBrand.body(11, color: AssimilisBrand.muted),
            ),
          ]),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('Remove', style: TextStyle(color: AssimilisBrand.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (action == null) return;
    if (action == 'delete' && existing != null) {
      await _store.removeAccount(existing.id);
      await _load();
      return;
    }
    if (action == 'save') {
      await _store.saveAccount(
        id: existing?.id,
        label: label.text,
        username: user.text,
        password: pass.text,
        baseUrl: url.text,
      );
      await _load();
      if (mounted) setState(() => _msg = 'Saved encrypted account.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final courses = List<Map>.from(_snap?['courses'] ?? const []);
    final deadlines = List<Map>.from(_snap?['deadlines'] ?? const [])
      ..sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));
    final ann = List<Map>.from(_snap?['announcements'] ?? const []);
    final resources = List<Map>.from(_snap?['resources'] ?? const []);

    return DefaultTabController(
      length: 4,
      child: HudScaffold(
        title: 'UWI Mona VLE',
        subtitle: '${_accounts.length} ENCRYPTED ACCOUNT${_accounts.length == 1 ? '' : 'S'}',
        actions: [
          IconButton(
            tooltip: 'Add account',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: () => _editAccount(),
          ),
          IconButton(
            tooltip: 'Scan now',
            onPressed: _busy || _active == null ? null : _scan,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync_rounded),
          ),
        ],
        bottom: TabBar(
          labelColor: AssimilisBrand.violetSoft,
          unselectedLabelColor: AssimilisBrand.muted,
          indicatorColor: AssimilisBrand.violet,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          labelStyle: AssimilisBrand.label(11, color: AssimilisBrand.violetSoft).copyWith(letterSpacing: 0.4),
          unselectedLabelStyle: AssimilisBrand.label(11, color: AssimilisBrand.muted).copyWith(letterSpacing: 0.4),
          tabs: const [
            Tab(text: 'Deadlines'),
            Tab(text: 'Courses'),
            Tab(text: 'Resources'),
            Tab(text: 'News'),
          ],
        ),
        body: _accounts.isEmpty
            ? ListView(
                padding: const EdgeInsets.fromLTRB(18, 48, 18, 32),
                children: [
                  HudPanel(
                    title: 'Multi-user VLE scanner',
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        'Add one or more UWI Mona VLE accounts. Every account is stored encrypted in this device\'s keystore so multiple people can use the scanner safely.',
                        textAlign: TextAlign.center,
                        style: AssimilisBrand.body(13, color: AssimilisBrand.muted),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _editAccount(),
                        icon: const Icon(Icons.lock_outline_rounded),
                        label: const Text('Add encrypted account'),
                      ),
                    ]),
                  ),
                ],
              )
            : Column(children: [
                SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    children: [
                      for (final acc in _accounts)
                        HudChip(
                          acc.label,
                          icon: Icons.lock_rounded,
                          selected: acc.id == _active?.id,
                          onTap: () async {
                            await _store.setActiveAccount(acc.id);
                            await _load();
                          },
                        ),
                      if (_active != null)
                        IconButton(
                          tooltip: 'Edit active account',
                          icon: const Icon(Icons.edit_outlined, size: 18, color: AssimilisBrand.muted),
                          onPressed: () => _editAccount(_active),
                        ),
                    ],
                  ),
                ),
                if (_msg != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: Text(_msg!, style: AssimilisBrand.body(12, color: AssimilisBrand.mint)),
                  ),
                if (_snap?['synced'] != null)
                  Text(
                    'Last scan ${_snap!['synced'].toString().substring(0, 16).replaceAll('T', ' ')}',
                    style: AssimilisBrand.label(10),
                  ),
                Expanded(
                  child: TabBarView(children: [
                    ListView(padding: const EdgeInsets.all(12), children: [
                      for (final d in deadlines) _deadline(d),
                      if (deadlines.isEmpty) const HudNote('No upcoming deadlines. Tap sync to scan.'),
                    ]),
                    ListView(padding: const EdgeInsets.all(12), children: [
                      for (final c in courses)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: HudPanel(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            onTap: () => launchUrl(Uri.parse('${c['url']}'), mode: LaunchMode.externalApplication),
                            child: Row(children: [
                              const Icon(Icons.school_rounded, color: AssimilisBrand.violetSoft),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${c['code']}', style: AssimilisBrand.body(14, w: FontWeight.w600)),
                                  Text('${c['name']}', style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
                                ]),
                              ),
                              IconButton(
                                tooltip: 'Make Canvas book',
                                icon: const Icon(Icons.note_add_outlined, color: AssimilisBrand.violetSoft),
                                onPressed: () async {
                                  final s = NotesStore.instance;
                                  await s.load();
                                  if (s.bookNamed('${c['code']}') == null) {
                                    final b = await s.addBook('${c['code']}');
                                    for (final sec in ['Lectures', 'Tutorials', 'Assignments', 'Exam prep']) {
                                      await s.addSection('${b['id']}', sec);
                                    }
                                  }
                                  if (mounted) setState(() => _msg = 'Book ${c['code']} is on Canvas.');
                                },
                              ),
                            ]),
                          ),
                        ),
                      if (courses.isEmpty) const HudNote('No courses yet. Tap sync to scan.'),
                    ]),
                    ListView(padding: const EdgeInsets.all(12), children: [
                      for (final r in resources)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            r['kind'] == 'quiz'
                                ? Icons.quiz_outlined
                                : r['kind'] == 'assign'
                                    ? Icons.assignment_outlined
                                    : Icons.description_outlined,
                            color: AssimilisBrand.violetSoft,
                          ),
                          title: Text('${r['title']}', style: AssimilisBrand.body(13)),
                          subtitle: Text('${r['course']} · ${r['kind']}', style: AssimilisBrand.label(10)),
                          onTap: () => launchUrl(Uri.parse('${r['url']}'), mode: LaunchMode.externalApplication),
                        ),
                      if (resources.isEmpty) const HudNote('No scanned resources yet. Tap sync.'),
                    ]),
                    ListView(padding: const EdgeInsets.all(12), children: [
                      for (final a in ann)
                        ListTile(
                          leading: const Icon(Icons.campaign_rounded, color: AssimilisBrand.violetSoft),
                          title: Text('${a['title']}', style: AssimilisBrand.body(14)),
                          subtitle: Text('${a['course']} · ${a['author']}', style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
                          onTap: () => launchUrl(Uri.parse('${a['url']}'), mode: LaunchMode.externalApplication),
                        ),
                      if (ann.isEmpty) const HudNote('No announcements yet.'),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HudPanel(
        accent: soon ? AssimilisBrand.magenta : AssimilisBrand.violet,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: d['url'] == null ? null : () => launchUrl(Uri.parse('${d['url']}'), mode: LaunchMode.externalApplication),
        child: Row(children: [
          Icon(d['type'] == 'quiz' ? Icons.quiz_rounded : Icons.assignment_rounded,
              color: soon ? AssimilisBrand.magenta : AssimilisBrand.violetSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d['name']}', style: AssimilisBrand.body(14, w: FontWeight.w600)),
              Text(
                '${d['course'] ?? ''} · ${at == null ? '' : '${at.day}/${at.month} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'}'
                '${left == null ? '' : left.isNegative ? ' · overdue' : ' · ${left.inDays}d ${left.inHours % 24}h left'}',
                style: AssimilisBrand.body(12, color: soon ? AssimilisBrand.magenta : AssimilisBrand.muted),
              ),
            ]),
          ),
          IconButton(
            tooltip: 'Send to HES reminders',
            icon: const Icon(Icons.alarm_add_rounded, color: AssimilisBrand.violetSoft),
            onPressed: at == null
                ? null
                : () async {
                    final when = at.subtract(const Duration(days: 1));
                    final target = when.isAfter(DateTime.now()) ? when : at;
                    final msg = await HesSystem.instance.remind('${d['course']}: ${d['name']} is due', target, source: 'vle');
                    if (mounted) setState(() => _msg = msg);
                  },
          ),
        ]),
      ),
    );
  }
}
