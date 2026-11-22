import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../assimilis/links/chatgpt_auth.dart';
import '../assimilis/links/hermes_link.dart';
import '../assimilis/links/shared_providers.dart';
import '../assimilis/settings.dart';
import 'brand.dart';
import 'core_view.dart';
import 'hud.dart';
import 'permissions_view.dart';

/// First-run setup for anyone who installs Assimilis Mobile: name, a brain, permissions.
class WelcomeView extends StatefulWidget {
  const WelcomeView({super.key});
  @override
  State<WelcomeView> createState() => _WelcomeViewState();
}

class _WelcomeViewState extends State<WelcomeView> {
  int _step = 0;
  final _name = TextEditingController();
  final _key = TextEditingController();
  final _hUrl = TextEditingController();
  final _hPw = TextEditingController();
  String _brain = 'openrouter';
  String? _msg;
  bool _busy = false;

  Future<void> _saveBrain() async {
    setState(() { _busy = true; _msg = null; });
    final s = await AssimilisSettings.get();
    try {
      switch (_brain) {
        case 'openrouter':
          if (_key.text.trim().isEmpty) throw Exception('Paste your OpenRouter key first.');
          ProviderContainer? c;
          try { c = ProviderScope.containerOf(context, listen: false); } catch (_) {}
          await SharedProviders.save({'openrouter': {'key': _key.text.trim(), 'model': ''}}, 'openrouter', c);
          await s.setBlob('brain', 'auto');
        case 'chatgpt':
          await ChatGptAuth.instance.signIn();
          await s.setBlob('brain', 'chatgpt');
        case 'hermes':
          await HermesLink.instance.configure(_hUrl.text, _hPw.text);
          await HermesLink.instance.test();
          await s.setBlob('brain', 'hermes');
        default:
          await s.setBlob('brain', 'local');
      }
      setState(() => _step = 2);
    } catch (e) {
      _msg = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finish() async {
    final s = await AssimilisSettings.get();
    s.userName = _name.text;
    s.onboarded = true;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AssimilisBrand.theme(),
      child: Scaffold(
        backgroundColor: AssimilisBrand.graphite,
        body: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: GridBackdrop())),
          SafeArea(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
              const Center(child: CoreView(size: 240)),
              Text('ASSIMILIS', textAlign: TextAlign.center,
                  style: AssimilisBrand.display(26, w: FontWeight.w800).copyWith(letterSpacing: 8, shadows: [const Shadow(color: AssimilisBrand.violet, blurRadius: 18)])),
              const SizedBox(height: 6),
              Text('SETUP ${_step + 1} / 3', textAlign: TextAlign.center, style: AssimilisBrand.label(11, color: AssimilisBrand.violetSoft)),
              const SizedBox(height: 18),
              ...switch (_step) { 0 => _hello(), 1 => _brainStep(), _ => _permsStep() },
            ]),
          ),
        ]),
      ),
    );
  }

  List<Widget> _hello() => [
        HudPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Hi, I am Assimilis. You can call me A for short.', style: AssimilisBrand.body(17, w: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('I live on your phone: notes and maths, a life-stats system, reminders, the web, local AI models, and I can use your phone for you.',
                style: AssimilisBrand.body(13, color: AssimilisBrand.muted)),
            const SizedBox(height: 14),
            TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'What should I call you?')),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => setState(() => _step = 1), child: const Text('Next')),
          ]),
        ),
      ];

  List<Widget> _brainStep() => [
        HudPanel(
          title: 'Choose my brain',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final b in const [
              ('openrouter', 'Free cloud models', 'An OpenRouter key (free models available). Recommended.'),
              ('local', 'On this phone only', 'Download a model in Chat & Models. Private, works offline; needs a recent phone.'),
              ('chatgpt', 'My ChatGPT account', 'Sign in with ChatGPT (advanced; outside OpenAI\'s intended use).'),
              ('hermes', 'My own Assimilis server', 'Connect to Assimilis / Hermes on your PC or server.'),
            ])
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: b.$1,
                groupValue: _brain,
                title: Text(b.$2, style: AssimilisBrand.body(14, w: FontWeight.w600)),
                subtitle: Text(b.$3, style: AssimilisBrand.body(12, color: AssimilisBrand.muted)),
                onChanged: (v) => setState(() => _brain = v!),
              ),
            if (_brain == 'openrouter') ...[
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://openrouter.ai/keys'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Get a free key at openrouter.ai'),
              ),
              TextField(controller: _key, obscureText: true, decoration: const InputDecoration(labelText: 'OpenRouter key')),
            ],
            if (_brain == 'hermes') ...[
              TextField(controller: _hUrl, decoration: const InputDecoration(labelText: 'Server address, e.g. http://192.168.1.10:8787')),
              const SizedBox(height: 8),
              TextField(controller: _hPw, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            ],
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: AssimilisBrand.label(11, color: AssimilisBrand.red))),
            const SizedBox(height: 14),
            FilledButton(onPressed: _busy ? null : _saveBrain, child: Text(_busy ? 'Connecting…' : 'Next')),
            TextButton(onPressed: () => setState(() => _step = 2), child: const Text('Skip for now')),
          ]),
        ),
      ];

  List<Widget> _permsStep() => [
        HudPanel(
          title: 'Permissions',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Allow what you want me to use. You can change any of this later in Safety & Permissions.',
                style: AssimilisBrand.body(13, color: AssimilisBrand.muted)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Theme(data: AssimilisBrand.theme(), child: const PermissionsView()))),
              child: const Text('Open Safety & Permissions'),
            ),
            const SizedBox(height: 10),
            FilledButton(onPressed: _finish, child: Text(_name.text.trim().isEmpty ? 'Start' : 'Start, ${_name.text.trim()}')),
          ]),
        ),
      ];
}
