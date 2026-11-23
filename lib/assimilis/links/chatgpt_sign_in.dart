import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../hub/brand.dart';
import 'chatgpt_auth.dart';

/// "Sign in with ChatGPT": shows the long link and the code to type there, and waits until ChatGPT approves.
/// Returns the result message (or null if the user closed it).
Future<String?> signInWithChatGpt(BuildContext context) =>
    showDialog<String>(context: context, barrierDismissible: false, builder: (_) => const _ChatGptSignInDialog());

class _ChatGptSignInDialog extends StatefulWidget {
  const _ChatGptSignInDialog();
  @override
  State<_ChatGptSignInDialog> createState() => _ChatGptSignInDialogState();
}

class _ChatGptSignInDialogState extends State<_ChatGptSignInDialog> {
  ChatGptDeviceCode? _code;
  String? _error;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final c = await ChatGptAuth.instance.startDeviceSignIn();
      if (!mounted) return;
      setState(() => _code = c);
      final msg = await ChatGptAuth.instance.finishDeviceSignIn(c, cancelled: () => _cancelled);
      if (mounted) Navigator.of(context).pop(msg);
    } catch (e) {
      if (!_cancelled && mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _code;
    return AlertDialog(
      backgroundColor: AssimilisBrand.panel,
      title: Text('Sign in with ChatGPT', style: AssimilisBrand.display(15, w: FontWeight.w700)),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_error != null)
            Text(_error!, style: AssimilisBrand.body(13, color: AssimilisBrand.red))
          else if (c == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else ...[
            Text('1. Open this link and sign in to ChatGPT:', style: AssimilisBrand.body(13)),
            const SizedBox(height: 6),
            SelectableText(c.url, style: AssimilisBrand.label(12, color: AssimilisBrand.violetSoft)),
            const SizedBox(height: 14),
            Text('2. Type this code there:', style: AssimilisBrand.body(13)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: Border.all(color: AssimilisBrand.violet), color: AssimilisBrand.graphite),
              alignment: Alignment.center,
              child: SelectableText(c.userCode, style: AssimilisBrand.display(24, w: FontWeight.w800).copyWith(letterSpacing: 4)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy code'),
                  onPressed: () => Clipboard.setData(ClipboardData(text: c.userCode)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Open link'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: c.userCode));
                    await ChatGptAuth.instance.openLink(c);
                  },
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(child: Text('Waiting for ChatGPT… come back here when it says you are signed in.', style: AssimilisBrand.body(12, color: AssimilisBrand.muted))),
            ]),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.of(context).pop();
          },
          child: Text(_error == null ? 'Cancel' : 'Close'),
        ),
        if (_error != null)
          FilledButton(
            onPressed: () {
              setState(() {
                _error = null;
                _code = null;
              });
              _run();
            },
            child: const Text('Try again'),
          ),
      ],
    );
  }
}
