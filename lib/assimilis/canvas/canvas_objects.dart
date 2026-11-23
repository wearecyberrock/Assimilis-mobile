import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../hub/brand.dart';
import 'maths.dart';
import 'note_renderer.dart';

/// Shared painter for infinite Canvas planes (top-level board and per-page canvas):
/// subtle dot grid, Bezier connection lines (with labels and directional dots), and vector ink.
class CanvasBoardPainter extends CustomPainter {
  /// Every connectable item on the plane (books + objects), keyed by id with x, y, w.
  final List<Map<String, dynamic>> items;
  final List conns;
  final List ink;
  final List<Offset>? liveStroke;

  CanvasBoardPainter({
    required this.items,
    required this.conns,
    required this.ink,
    this.liveStroke,
  });

  @override
  void paint(Canvas c, Size size) {
    final dot = Paint()..color = AssimilisBrand.violet.withValues(alpha: 0.16);
    for (var x = 0.0; x < size.width; x += 40) {
      for (var y = 0.0; y < size.height; y += 40) {
        c.drawCircle(Offset(x, y), 1.1, dot);
      }
    }

    final byId = <String, Map<String, dynamic>>{for (final n in items) '${n['id']}': n};
    final glow = Paint()
      ..color = AssimilisBrand.violet.withValues(alpha: 0.22)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;
    final line = Paint()
      ..color = const Color(0xCCA855F7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final k in conns) {
      final a = byId['${k['from']}'];
      final b = byId['${k['to']}'];
      if (a == null || b == null) continue;
      final ax = (a['x'] as num? ?? 0).toDouble();
      final ay = (a['y'] as num? ?? 0).toDouble();
      final aw = (a['w'] as num? ?? 200).toDouble();
      final bx = (b['x'] as num? ?? 0).toDouble();
      final by = (b['y'] as num? ?? 0).toDouble();
      final bw = (b['w'] as num? ?? 200).toDouble();
      final p1 = Offset(ax + aw / 2, ay + 48);
      final p2 = Offset(bx + bw / 2, by + 48);
      final dx = (p2.dx - p1.dx).abs() / 2 + 44;
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(p1.dx + dx, p1.dy, p2.dx - dx, p2.dy, p2.dx, p2.dy);
      c.drawPath(path, glow);
      c.drawPath(path, line);
      c.drawCircle(p1, 3.5, Paint()..color = AssimilisBrand.violetSoft);
      c.drawCircle(p2, 4.5, Paint()..color = AssimilisBrand.magenta);

      final lbl = '${k['label'] ?? ''}'.trim();
      if (lbl.isNotEmpty) {
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final tp = TextPainter(
          text: TextSpan(text: lbl, style: AssimilisBrand.label(10, color: AssimilisBrand.text)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 140);
        final rect = Rect.fromCenter(center: mid, width: tp.width + 12, height: tp.height + 6);
        c.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()..color = AssimilisBrand.panel,
        );
        c.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()
            ..color = AssimilisBrand.violet.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke,
        );
        tp.paint(c, mid - Offset(tp.width / 2, tp.height / 2));
      }
    }

    void drawStroke(List<Offset> pts, Color color, double w) {
      if (pts.length < 2) return;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final o in pts.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      c.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }

    for (final s in ink) {
      final rawPts = (s['points'] as List? ?? const []);
      drawStroke(
        [for (final q in rawPts) Offset((q[0] as num).toDouble(), (q[1] as num).toDouble())],
        Color((s['color'] ?? 0xFFA855F7) as int),
        ((s['w'] ?? 3) as num).toDouble(),
      );
    }
    if (liveStroke != null) drawStroke(liveStroke!, AssimilisBrand.violet, 3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Renders one rich Canvas object: note, coded graph, media image, video, sound, or code block.
class CanvasObjectCard extends StatelessWidget {
  final Map<String, dynamic> node;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;

  const CanvasObjectCard({
    super.key,
    required this.node,
    this.selected = false,
    this.onTap,
    this.onDoubleTap,
    this.onPanUpdate,
    this.onPanEnd,
  });

  static Color accentFor(String kind) => switch (kind) {
        'graph' => AssimilisBrand.mint,
        'media' => AssimilisBrand.violetSoft,
        'video' => AssimilisBrand.magenta,
        'sound' => const Color(0xFFFFB300),
        'code' => const Color(0xFF38BDF8),
        _ => AssimilisBrand.violet,
      };

  static IconData iconFor(String kind) => switch (kind) {
        'graph' => Icons.show_chart_rounded,
        'media' => Icons.image_rounded,
        'video' => Icons.smart_display_rounded,
        'sound' => Icons.graphic_eq_rounded,
        'code' => Icons.code_rounded,
        _ => Icons.sticky_note_2_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final kind = '${node['kind'] ?? 'note'}';
    final title = '${node['title'] ?? ''}'.trim();
    final accent = accentFor(kind);
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: Container(
        decoration: BoxDecoration(
          color: Color((node['color'] ?? 0xFF1A1A22) as int),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AssimilisBrand.magenta : accent.withValues(alpha: 0.7),
            width: selected ? 2 : 1.3,
          ),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.14), blurRadius: 14)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              ),
              child: Row(children: [
                Icon(iconFor(kind), size: 14, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title.isEmpty ? kind.toUpperCase() : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AssimilisBrand.label(11, color: AssimilisBrand.text, w: FontWeight.w700),
                  ),
                ),
                Text(kind.toUpperCase(), style: AssimilisBrand.label(9, color: accent)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: _body(context, kind),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, String kind) {
    switch (kind) {
      case 'graph':
        final fns = (node['functions'] as List? ?? const ['sin(x)']).map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();
        final code = '${node['code'] ?? ''}'.trim();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FunctionGraph(functions: fns.isEmpty ? const ['x'] : fns, height: 150),
          if (code.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AssimilisBrand.graphite, borderRadius: BorderRadius.circular(6)),
              child: Text(code, style: AssimilisBrand.label(10, color: AssimilisBrand.mint)),
            ),
          ],
        ]);

      case 'media':
        final src = '${node['uri'] ?? node['path'] ?? ''}'.trim();
        final cap = '${node['text'] ?? ''}'.trim();
        Widget img;
        if (src.startsWith('http://') || src.startsWith('https://')) {
          img = Image.network(src, height: 130, fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholder(Icons.broken_image_rounded, src));
        } else if (src.isNotEmpty && File(src).existsSync()) {
          img = Image.file(File(src), height: 130, fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholder(Icons.broken_image_rounded, src));
        } else {
          img = _placeholder(Icons.image_outlined, src.isEmpty ? 'Double-tap to pick an image or URL' : src);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(borderRadius: BorderRadius.circular(6), child: img),
          if (cap.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(cap, style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
          ],
        ]);

      case 'video':
        final src = '${node['uri'] ?? node['path'] ?? ''}'.trim();
        final cap = '${node['text'] ?? ''}'.trim();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: src.isEmpty ? onDoubleTap : () => _openVideo(context, '${node['title'] ?? 'Video'}', src),
            child: Container(
              height: 110,
              decoration: BoxDecoration(
                color: AssimilisBrand.graphite,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AssimilisBrand.magenta.withValues(alpha: 0.45)),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.play_circle_fill_rounded, size: 42, color: AssimilisBrand.magenta),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    src.isEmpty ? 'Double-tap to attach video or URL' : _shortSrc(src),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AssimilisBrand.label(10, color: AssimilisBrand.muted),
                  ),
                ),
              ]),
            ),
          ),
          if (cap.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(cap, style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
          ],
        ]);

      case 'sound':
        return _SoundTile(
          src: '${node['uri'] ?? node['path'] ?? ''}'.trim(),
          caption: '${node['text'] ?? ''}'.trim(),
        );

      case 'code':
        final lang = '${node['language'] ?? 'code'}';
        final code = '${node['code'] ?? node['text'] ?? ''}'.trim();
        final eval = lang.toLowerCase() == 'math' && code.isNotEmpty ? Maths.calc(code) : null;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AssimilisBrand.graphite, borderRadius: BorderRadius.circular(6)),
            child: Text(
              code.isEmpty ? '// double-tap to edit' : code,
              style: AssimilisBrand.label(11, color: const Color(0xFF7DD3FC)),
            ),
          ),
          if (eval != null && !eval.startsWith('Could not')) ...[
            const SizedBox(height: 4),
            Text('= $eval', style: AssimilisBrand.label(11, color: AssimilisBrand.mint, w: FontWeight.w700)),
          ],
        ]);

      default:
        final txt = '${node['text'] ?? ''}';
        return txt.trim().isEmpty
            ? Text('Double-tap to edit', style: AssimilisBrand.body(12, color: AssimilisBrand.faint))
            : NoteRenderer(txt);
    }
  }

  Widget _placeholder(IconData icon, String label) => Container(
        height: 96,
        color: AssimilisBrand.graphite,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: AssimilisBrand.muted, size: 28),
          const SizedBox(height: 4),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AssimilisBrand.label(10)),
        ]),
      );

  static String _shortSrc(String s) {
    if (s.startsWith('http')) return s.replaceFirst(RegExp(r'^https?://'), '');
    return s.split(Platform.pathSeparator).last;
  }

  static Future<void> _openVideo(BuildContext context, String title, String src) async {
    final uri = Uri.tryParse(src);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final embed = _toEmbedUrl(src);
      if (embed != null && context.mounted) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AssimilisBrand.panel,
          builder: (_) => _VideoWebSheet(title: title, url: embed, originalUrl: src),
        );
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (src.isNotEmpty) {
      await launchUrl(Uri.file(src), mode: LaunchMode.externalApplication);
    }
  }

  static String? _toEmbedUrl(String url) {
    final yt = RegExp(r'(?:youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]{6,})').firstMatch(url);
    if (yt != null) return 'https://www.youtube.com/embed/${yt.group(1)}';
    return null;
  }
}

class _VideoWebSheet extends StatefulWidget {
  final String title, url, originalUrl;
  const _VideoWebSheet({required this.title, required this.url, required this.originalUrl});
  @override
  State<_VideoWebSheet> createState() => _VideoWebSheetState();
}

class _VideoWebSheetState extends State<_VideoWebSheet> {
  late final WebViewController _ctrl = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(Uri.parse(widget.url));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.62,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
          child: Row(children: [
            Expanded(child: Text(widget.title, style: AssimilisBrand.body(14, w: FontWeight.w600))),
            IconButton(
              tooltip: 'Open externally',
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              onPressed: () => launchUrl(Uri.parse(widget.originalUrl), mode: LaunchMode.externalApplication),
            ),
            IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Expanded(child: WebViewWidget(controller: _ctrl)),
      ]),
    );
  }
}

class _SoundTile extends StatefulWidget {
  final String src, caption;
  const _SoundTile({required this.src, required this.caption});
  @override
  State<_SoundTile> createState() => _SoundTileState();
}

class _SoundTileState extends State<_SoundTile> {
  AudioPlayer? _player;
  bool _playing = false;
  String? _err;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (widget.src.isEmpty) return;
    try {
      _player ??= AudioPlayer()
        ..onPlayerComplete.listen((_) {
          if (mounted) setState(() => _playing = false);
        });
      if (_playing) {
        await _player!.pause();
        setState(() => _playing = false);
      } else {
        setState(() => _err = null);
        if (widget.src.startsWith('http://') || widget.src.startsWith('https://')) {
          await _player!.play(UrlSource(widget.src));
        } else {
          await _player!.play(DeviceFileSource(widget.src));
        }
        setState(() => _playing = true);
      }
    } catch (e) {
      if (mounted) setState(() { _playing = false; _err = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton.filled(
          style: IconButton.styleFrom(backgroundColor: const Color(0xFFFFB300).withValues(alpha: 0.2), foregroundColor: const Color(0xFFFFB300)),
          onPressed: widget.src.isEmpty ? null : _toggle,
          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              widget.src.isEmpty ? 'Double-tap to pick audio' : CanvasObjectCard._shortSrc(widget.src),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AssimilisBrand.label(11, color: AssimilisBrand.text),
            ),
            if (widget.caption.isNotEmpty)
              Text(widget.caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: AssimilisBrand.body(11, color: AssimilisBrand.muted)),
            if (_err != null) Text(_err!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AssimilisBrand.label(10, color: AssimilisBrand.red)),
          ]),
        ),
      ]),
    ]);
  }
}

/// Dialog to create or edit any rich Canvas object (note, graph, media, video, sound, code).
/// Returns null if cancelled, `{'_delete': true}` if deleted, or the updated fields.
Future<Map<String, dynamic>?> showCanvasObjectDialog(
  BuildContext context, {
  Map<String, dynamic>? existing,
  String initialKind = 'note',
}) async {
  var kind = '${existing?['kind'] ?? initialKind}';
  final title = TextEditingController(text: '${existing?['title'] ?? ''}');
  final text = TextEditingController(text: '${existing?['text'] ?? ''}');
  final fns = TextEditingController(text: ((existing?['functions'] as List?) ?? const ['sin(x)']).join(', '));
  final code = TextEditingController(text: '${existing?['code'] ?? ''}');
  final lang = TextEditingController(text: '${existing?['language'] ?? 'dart'}');
  final uri = TextEditingController(text: '${existing?['uri'] ?? existing?['path'] ?? ''}');

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        backgroundColor: AssimilisBrand.panel,
        title: Text(existing == null ? 'Add to Canvas' : 'Edit object', style: AssimilisBrand.body(16, w: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (existing == null)
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in const [
                  ('note', 'Note', Icons.sticky_note_2_outlined),
                  ('graph', 'Graph', Icons.show_chart_rounded),
                  ('media', 'Image', Icons.image_rounded),
                  ('video', 'Video', Icons.smart_display_rounded),
                  ('sound', 'Sound', Icons.graphic_eq_rounded),
                  ('code', 'Code', Icons.code_rounded),
                ])
                  ChoiceChip(
                    avatar: Icon(k.$3, size: 15),
                    label: Text(k.$2),
                    selected: kind == k.$1,
                    onSelected: (_) => set(() => kind = k.$1),
                  ),
              ]),
            const SizedBox(height: 10),
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 8),
            if (kind == 'note')
              TextField(
                controller: text,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Markdown / \$LaTeX\$ / prompt(...)'),
              ),
            if (kind == 'graph') ...[
              TextField(
                controller: fns,
                decoration: const InputDecoration(labelText: 'Functions (comma-separated)', hintText: 'sin(x), x^2/4'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: code,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Graph code / notes (optional)'),
              ),
            ],
            if (kind == 'code') ...[
              TextField(controller: lang, decoration: const InputDecoration(labelText: 'Language (or "math" to evaluate)')),
              const SizedBox(height: 8),
              TextField(controller: code, maxLines: 6, style: AssimilisBrand.label(12, color: AssimilisBrand.text), decoration: const InputDecoration(labelText: 'Code')),
            ],
            if (kind == 'media' || kind == 'video' || kind == 'sound') ...[
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: uri,
                    decoration: InputDecoration(
                      labelText: kind == 'media' ? 'Image path or URL' : (kind == 'video' ? 'Video path or YouTube URL' : 'Audio path or URL'),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Pick file',
                  icon: const Icon(Icons.folder_open_rounded),
                  onPressed: () async {
                    try {
                      if (kind == 'media') {
                        final x = await ImagePicker().pickImage(source: ImageSource.gallery);
                        if (x != null) set(() => uri.text = x.path);
                      } else {
                        final r = await FilePicker.pickFiles(
                          type: kind == 'video' ? FileType.video : FileType.audio,
                        );
                        final p = r.isEmpty ? null : r.first.path;
                        if (p != null) set(() => uri.text = p);
                      }
                    } catch (_) {}
                  },
                ),
              ]),
              const SizedBox(height: 8),
              TextField(controller: text, maxLines: 2, decoration: const InputDecoration(labelText: 'Caption / notes (optional)')),
            ],
          ]),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, {'_delete': true}),
              child: const Text('Delete', style: TextStyle(color: AssimilisBrand.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final extra = <String, dynamic>{};
              if (kind == 'graph') {
                extra['functions'] = fns.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                extra['code'] = code.text;
              } else if (kind == 'code') {
                extra['language'] = lang.text.trim().isEmpty ? 'code' : lang.text.trim();
                extra['code'] = code.text;
              } else if (kind == 'media' || kind == 'video' || kind == 'sound') {
                extra['uri'] = uri.text.trim();
              }
              Navigator.pop(ctx, {
                'kind': kind,
                'title': title.text.trim(),
                'text': text.text,
                'extra': extra,
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
