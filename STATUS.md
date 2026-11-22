# Assimilis Mobile: what works and what is stubbed (2026-11-22)

**Honest baseline:** the merged code passes `flutter analyze` with **0 errors**, but **no APK has been built yet**.
The local build crashed because this PC ran out of RAM (7.8 GB) and disk. Nothing has been run on a phone. Until
an APK is built and installed, everything under "Merged in" is "should work", not "tested".

## Agent to agent (A2A, 2026-11-22, not yet tried on real devices)

* Every device running the app is an A2A agent (open Agent2Agent protocol): agent card at `/.well-known/agent-card.json`, JSON-RPC `message/send` at `/a2a`, port 47800.
* Found automatically on the same Wi-Fi (mDNS `_assimilis-a2a._tcp`); over Tailscale, add a device by its Tailscale name or IP in **Nearby A's**.
* Skills per device: **ask** (its A answers), **generate** (raw text from its loaded model, for heavy jobs), **phone_task** (it uses that device; its own safety gate still applies).
* A can `list_devices` and `ask_device` (by name or "best"). With no brain on this phone, A passes the question to the strongest nearby device automatically. A forwarded request is never forwarded again (no loops).
* Incoming requests: **Ask me** (default: Allow once / Always / Deny per device), **Allow all**, or **Off**. Anyone running the app nearby can send requests.
* Limits: works while the app is open (Android may pause it in the background). No encryption beyond what Tailscale gives; on open Wi-Fi others can read the traffic.

## For everyone (2026-11-22)

* UWI / Mona VLE removed: it was personal to the owner.
* First-run setup (name, brain, permissions) so anyone can install and use it; A uses your name.
* Every Assimilis screen in the HES style (HUD title bar, corner-bracket panels).

## Redesign and links (2026-11-22, built but not yet tried on a phone)

| Feature | What it does | Caveats |
|---|---|---|
| **New brand** | Violet #A855F7 on graphite, HES-style panels with corner brackets, Orbitron / JetBrains Mono / Inter fonts bundled. App icon and splash are the Core. The green pixel mascot is retired. | The three agent apps keep their own look, on purpose. |
| **The real Core** | The hub and voice mode run the web UI's own `assimilis-core.js` + `assimilis-eye.js` in a small WebView. Its orbits show your reminders and deadlines, brains, HES stats, tools, courses and notes; it listens, thinks and speaks with A. | Display only on the phone (no dragging). |
| **A** | The assistant is now Assimilis, "A". Voice mode says "Hi, I am Assimilis. You can call me A for short." | |
| **HES rebuilt** | Status (title, class, rank, power, coins, AP, radar per branch), Quests, Modules, Abilities (unlock with AP when requirements are met), Log with undo, Evolution (why you got XP). "{time}" quest bug fixed. | Abilities check level, mission counts and streaks; other requirement kinds count as not met. |
| **Models & Links** | One brain choice for A (Auto / My Hermes / ChatGPT / API key / local). | |
| **My Hermes** | Phone logs into your Assimilis on laptop or VPS (LAN or Tailscale) and uses every model it has, including your subscriptions, and its core voice (Fish JARVIS if the server has a key, else Edge Ryan). | Needs Hermes reachable from the phone. |
| **ChatGPT sign-in** | Codex-style OAuth on the phone; replies from your ChatGPT subscription. | Outside OpenAI's intended use for other apps (owner's choice). No Claude subscription login (Anthropic forbids it); use Claude through My Hermes. Model names may need updating as OpenAI changes them. |
| **Shared keys** | Enter API keys once; they are written into Chat & Models, the Workstation (as "· shared" providers), the Phone Agent and A. | |
| **Shared model library** | Everyone uses `<app documents>/models`; the Workstation downloads there and lists every model in it. | Models PocketStrike downloaded to Download/ before this update are not moved. |
| **Laptops and PCs in the RAM pool** | `node/assimilis-node.ps1` (Windows) and `node/assimilis-node.sh` (Linux/macOS) download llama.cpp b11157 and run its RPC worker; add the PC in Devices & RAM. Host mode runs a big model on the PC with phones as extra RAM and gives A an OpenAI-style URL. | Windows PCs are added by address (Scan finds Linux/macOS only). The worker has no password: own Wi-Fi or Tailscale only. |

## New Assimilis features (on the phone, no server)

| Feature | What it does | Caveats |
|---|---|---|
| **Jarvis voice mode** | Hands-free listen → think → speak loop with "On it." beats and an arc-reactor screen. Voice is Edge `en-GB-RyanNeural` (rate -6%, pitch -3Hz) called straight from the phone, with the phone's British voice offline. The Phone Agent speaks as Jarvis too. | The Edge handshake (`Sec-MS-GEC`) is reimplemented from the `edge-tts` protocol. If Microsoft changes it, the app falls back to the phone voice. |
| **Brain + tools** | Any OpenAI-compatible model (OpenRouter by default) with 26 tools: alarms, reminders, notes, maths, HES, UWI, Agent Reach, phone_task. With no key, it uses the local GGUF from Chat & Models, plus offline shortcuts (timers, alarms, sums, HES logs). | Free models that refuse tool calls get one retry without tools. |
| **Canvas** | Book > section > page with `book-`/`sec-`/`page-`/`node-`/`conn-` IDs. Page mode: markdown, `$LaTeX$`, and `prompt(math\|graph\|derive\|integrate, …)` blocks. Canvas mode: 0.2–3× pan/zoom, cards, Bezier connectors, ink. | Only notes, maths and school. No business objects, no sync with web Notes. |
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
