# Assimilis Mobile: what works and what is stubbed (2026-11-22)

**Honest baseline:** the merged code passes `flutter analyze` with **0 errors**, but **no APK has been built yet**.
The local build crashed because this PC ran out of RAM (7.8 GB) and disk. Nothing has been run on a phone. Until
an APK is built and installed, everything under "Merged in" is "should work", not "tested".

## New Assimilis features (on the phone, no server)

| Feature | What it does | Caveats |
|---|---|---|
| **Jarvis voice mode** | Hands-free listen → think → speak loop with "On it." beats and an arc-reactor screen. Voice is Edge `en-GB-RyanNeural` (rate -6%, pitch -3Hz) called straight from the phone, with the phone's British voice offline. The Phone Agent speaks as Jarvis too. | The Edge handshake (`Sec-MS-GEC`) is reimplemented from the `edge-tts` protocol. If Microsoft changes it, the app falls back to the phone voice. |
| **Brain + tools** | Any OpenAI-compatible model (OpenRouter by default) with 26 tools: alarms, reminders, notes, maths, HES, UWI, Agent Reach, phone_task. With no key, it uses the local GGUF from Chat & Models, plus offline shortcuts (timers, alarms, sums, HES logs). | Free models that refuse tool calls get one retry without tools. |
| **Canvas** | Book > section > page with `book-`/`sec-`/`page-`/`node-`/`conn-` IDs. Page mode: markdown, `$LaTeX$`, and `prompt(math\|graph\|derive\|integrate, …)` blocks. Canvas mode: 0.2–3× pan/zoom, cards, Bezier connectors, ink. | Only notes, maths and school. No business objects, no sync with web Notes. |
| **UWI · Academic** | Mona VLE login (same flow as `components/uwi-academic`), courses, deadlines, announcements. A deadline becomes reminders 1 day and 3 hours before, and a course becomes a Canvas notebook. | Read-only. If the VLE asks for a CAPTCHA, MFA or a password change, it stops and tells you. No material downloads or quiz generator yet. |
| **HES** | `engine.py` ported to Dart (same ranks E→Monarch, caps, decay, XP curve), the server's tree, classes, abilities and 31 modules. Daily quests (+20 XP, +10 coins), trackers, quick log. | No questionnaire onboarding (stats start at 10), no Gmail money, no abilities shop UI. |
| **Alarms & Reminders** | Clock-app alarms and timers, and reminders (once, daily, weekdays, weekly) at exact times. Reminders survive a reboot. | |
| **Agent Reach** | Exa search, Jina page reader, GitHub, Reddit, YouTube captions and RSS. Results can be saved to Canvas. | Read-only. No Twitter/X, Instagram, LinkedIn or Chinese sites (those need logins or yt-dlp). |

## Merged in (whole original code, wired into the hub)

| Area | Status |
|---|---|
| Hub, launcher icon, navy splash, pixel mascot | New. Compiles. |
| **Chat & Models** (PrivateLM): local GGUF via llama.cpp, Stable Diffusion images, LiteRT, cloud OpenAI/Claude/Gemini/Kimi, downloads, vision, documents | Full original code. llama.cpp compiles from source (needs the NDK). Stable Diffusion uses the repo's **prebuilt arm64** libraries. |
| **Workstation** (PocketStrike): ReAct agent, MCP, Hermes memory, file tools, providers, its local models and image generation | Full original code, opened from the hub. Shares the same llama.cpp plugin as Chat. |
| **Phone Agent** (PrivateAgent): screen reading, tap/type/scroll/swipe, open apps, voice, TTS, contacts, calls/SMS/email (open the composer), alarms, volume/brightness, Shizuku, floating bubble | Full original code plus native service, moved into the app. |
| **Safety & Permissions**: every Android permission with Allow / Allow all; Phone Agent **Ask me** or **Full allow** | New. The Ask me gate is native (`SafetyGate.kt`) and also covers Shizuku shell commands. |

## Off or stubbed

* **Telegram background relay (PocketStrike).** Not started at launch, because PrivateLM already runs Android's
  one background service. Telegram inside the Workstation while the app is open is untested.
* **Firebase push and crash reports.** Off: there's no `google-services.json`. The app runs without them.
* **In-app updates.** Off. They pointed at upstream PrivateLM's GitHub releases, which would have offered to
  replace this app.
* **Phone support.** 64-bit ARM phones only. No 32-bit ARM or x86 builds, and no iOS build (iOS can't do phone
  control anyway).
* **Separate settings per area.** Chat, Workstation and Phone Agent each keep their own API keys, chat history
  and settings. A single settings screen across all three isn't built yet.
* **Branding inside each area.** Each area keeps its original look (PrivateLM theme, PocketStrike glass,
  PrivateAgent indigo). Only the hub, icon, splash, safety card and Safety screen use Assimilis colours. The
  magenta eye loading indicators aren't ported.
* **Plugin example tests.** The `local_plugins/flutter_overlay_window/example` folder shows analyzer errors; it
  is sample code and isn't part of the app build.

## To verify once an APK exists

1. It installs and opens on the hub.
2. A GGUF model downloads and chats.
3. A Stable Diffusion image generates.
4. The Workstation opens, and Back returns to the hub.
5. The Phone Agent, once its Accessibility service is on, opens an app and types into a search field.
6. In **Ask me** mode, tapping "Send" shows Allow / Deny, and Deny stops the task.
7. In **Full allow** mode, no card appears.
