# Notices

Assimilis Mobile combines code from three apps.

| Part of Assimilis Mobile | Came from | Licence / copyright |
|---|---|---|
| `lib/` (everything outside `lib/workstation`, `lib/phone_agent`, `lib/hub`), `local_plugins/llama_flutter_android`, `local_plugins/sd_flutter_android`, `local_plugins/flutter_litert_lm`, most of `android/` | PrivateLM: github.com/wearecyberrock/cross-platform-llm-client (upstream orailnoor) | MIT. Copyright (c) 2026 cross-platform-llm-client contributors. See `third_party/LICENSE-PrivateLM`. |
| `lib/workstation/`, `assets/workstation/` | PocketStrike: github.com/wearecyberrock/PocketStrike (upstream AbuZar-Ansarii) | MIT. Copyright (c) 2026 Mohd Abuzar (AbuZar-Ansarii). See `third_party/LICENSE-PocketStrike`. |
| `lib/phone_agent/`, `local_plugins/flutter_overlay_window`, `android/.../AgentAccessibilityService.kt` | PrivateAgent: github.com/wearecyberrock/private-agent (fork of orailnoor/private-agent) | The upstream repo has no licence file. |

The bundled native engines keep their own licences: llama.cpp (MIT), stable-diffusion.cpp (MIT) and LiteRT-LM (Apache-2.0).

New for Assimilis Mobile: `lib/hub/`, `SafetyGate.kt`, `AgentChannel.kt`, the Full-allow mode and the brand assets in `assets/brand/`.

## Added 2026-11-22

* `assets/core/assimilis-core.js` and `assets/core/assimilis-eye.js`: the Assimilis Core and eye from the Assimilis web UI
  (Elevedenbot `webui/static`, commit 2956c69f9), the owner's own code, copied unchanged.
* `assets/fonts/`: Orbitron, JetBrains Mono and Inter (SIL Open Font License 1.1), static files from Fontsource.
* `lib/assimilis/links/chatgpt_auth.dart` uses the public Codex CLI OAuth client id, the same sign-in Hermes uses.
* `node/`: scripts that download llama.cpp release b11157 (MIT, ggml-org) on a PC; llama.cpp itself is not bundled.
