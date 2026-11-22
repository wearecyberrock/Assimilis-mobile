# Notices

Assimilis Mobile combines code from three apps.

| Part of Assimilis Mobile | Came from | Licence / copyright |
|---|---|---|
| `lib/` (everything outside `lib/workstation`, `lib/phone_agent`, `lib/hub`), `local_plugins/llama_flutter_android`, `local_plugins/sd_flutter_android`, `local_plugins/flutter_litert_lm`, most of `android/` | PrivateLM: github.com/wearecyberrock/cross-platform-llm-client (upstream orailnoor) | MIT. Copyright (c) 2026 cross-platform-llm-client contributors. See `third_party/LICENSE-PrivateLM`. |
| `lib/workstation/`, `assets/workstation/` | PocketStrike: github.com/wearecyberrock/PocketStrike (upstream AbuZar-Ansarii) | MIT. Copyright (c) 2026 Mohd Abuzar (AbuZar-Ansarii). See `third_party/LICENSE-PocketStrike`. |
| `lib/phone_agent/`, `local_plugins/flutter_overlay_window`, `android/.../AgentAccessibilityService.kt` | PrivateAgent: github.com/wearecyberrock/private-agent (fork of orailnoor/private-agent) | The upstream repo has no licence file. |

The bundled native engines keep their own licences: llama.cpp (MIT), stable-diffusion.cpp (MIT) and LiteRT-LM (Apache-2.0).

New for Assimilis Mobile: `lib/hub/`, `SafetyGate.kt`, `AgentChannel.kt`, the Full-allow mode and the brand assets in `assets/brand/`.
