import 'package:flutter/material.dart';

import '../../hub/brand.dart';
import '../../hub/hud.dart';
import '../canvas/notes_store.dart';
import 'agent_reach.dart';

/// Agent Reach: search the web, or read a page / GitHub repo / YouTube video / subreddit / RSS feed.
class ReachView extends StatefulWidget {
  const ReachView({super.key});
  @override
  State<ReachView> createState() => _ReachViewState();
}

class _ReachViewState extends State<ReachView> {
  final _q = TextEditingController();
  String _mode = 'search';
  String _out = '';
  bool _busy = false;

  Future<void> _go() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _out = '';
    });
    try {
      _out = switch (_mode) {
        'search' => await AgentReach.search(q),
        'github' => await AgentReach.github(q),
        'reddit' => await AgentReach.reddit(q),
        'rss' => await AgentReach.rss(q),
        _ => await AgentReach.read(q),
      };
    } catch (e) {
      _out = 'Error: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return HudScaffold(
      title: 'Agent Reach',
      actions: [
        if (_out.isNotEmpty)
          IconButton(
            tooltip: 'Save to Canvas',
            icon: const Icon(Icons.note_add_rounded),
            onPressed: () async {
              await NotesStore.instance.load();
              await NotesStore.instance.quickNote(
                'Reach: ${_q.text.trim()}',
                _out,
                book: 'Research',
                section: 'Agent Reach',
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved to Canvas › Research')),
                );
              }
            },
          ),
      ],
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final m in const [
                  'search',
                  'read',
                  'github',
                  'reddit',
                  'rss',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(m),
                      selected: _mode == m,
                      selectedColor: AssimilisBrand.violet,
                      labelStyle: const TextStyle(color: Colors.white),
                      backgroundColor: AssimilisBrand.navyRaised,
                      onSelected: (_) => setState(() => _mode = m),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _q,
              onSubmitted: (_) => _go(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: switch (_mode) {
                  'search' => 'Search the web',
                  'github' => 'owner/repo or search words',
                  'reddit' => 'r/subreddit or post URL',
                  'rss' => 'Feed URL',
                  _ => 'URL: page, YouTube, GitHub, Reddit',
                },
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: AssimilisBrand.navyRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  onPressed: _go,
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    color: AssimilisBrand.violet,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _out.isEmpty ? 'Read-only: no logins, no posting.' : _out,
                      style: TextStyle(
                        color: _out.isEmpty ? Colors.white38 : Colors.white,
                        height: 1.4,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
