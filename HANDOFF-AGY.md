# Handoff to agy (Antigravity): Assimilis Mobile, 2026-11-23

From Claude (Shakir's session). Shakir owns this repo and has the final say. Read this, then `STATUS.md`.

## Where the work is

* **Branch:** `hes-system`. **Draft PR:** wearecyberrock/Assimilis-mobile#2 (not merged; Shakir merges).
* **Base:** `main` at `f708242` (A2A). The branch has 13 commits on top; `git log origin/main..hes-system` lists them.
* **CI:** `.github/workflows/build-apk.yml` builds an arm64 release APK on push to `main` or on manual dispatch:

  ```bash
  gh api -X POST repos/wearecyberrock/Assimilis-mobile/actions/workflows/build-apk.yml/dispatches -f ref=hes-system
  ```

  * The first build on the branch (commit `f2bf789`, M1 + M2) was green.
  * Two later builds failed:
    1. The `health` plugin needs `compileSdk` 37. Fixed in `8bfd883`.
    2. `packageRelease` failed with no message. `c14cab1` added a disk cleanup step and a `df -h` printout, and
       run 45227686371 on `c14cab1` is **green** (APK 128.6 MB, artifact `assimilis-mobile-apk`).
  * Disk was only 40% used, so disk was not the cause. The next build (`067ad1c`) showed the real cause:
    `Java heap space` in `mergeReleaseNativeDebugMetadata` (the big native libraries). CI now gives Gradle 6 GB
    through `~/.gradle/gradle.properties`; the project file keeps 3 GB for small PCs.
* **Checks** (Flutter 3.50.1):

  ```bash
  flutter analyze lib
  ```

  ```bash
  flutter test test/model_gateway_test.dart test/hes_system_test.dart test/hes_background_test.dart
  ```

  ```bash
  flutter test test/screenshots_test.dart --update-goldens
  ```

  * `flutter analyze lib` must stay at 0 errors (there are older warnings outside `lib/assimilis` and `lib/hub`).
  * The unit tests come to 22, all passing.
  * The screenshot test passes 21/21 and writes PNGs to `test/goldens/`. Look at them after UI changes.
* **Nothing has been run on a real phone yet.** Everything below is "built and unit-tested", not "tried on a
  device".

## What Shakir asked for (the mobile plan, M1 to M6)

He wants HES "perfect", in his words. Six milestones:

1. **M1 (done):**
   * The app icon is the Assimilis tentacle icon.
   * The bottom bar has five sections: HES, Canvas, Agents (A + the three agents), Team, Settings.
2. **M2 (done):** one Settings page for every agent's downloadable models and keys.
   * Each agent keeps its own models and keys, or can share any model.
   * It shows each agent's status.
   * ChatGPT sign-in is the device-code flow: a long link plus a code to type there.
3. **M3 (mostly done):** HES as a manhwa-style "System" run by an AI brain, either a local model or an API.
   * **No fixed coach modes** (Shakir, 2026-11-23): "no coach mode just general remember its an ai brain behind
     it so it suppose to can adapt".
   * The **ChatGPT subscription must work for it and for every agent**, with full tool use ("can do anything
     through the agents").
   * It uses phone data: location history, sleep, alarms, calendars, health, internet and MCP search.
   * Food photo to calories, the questionnaire, penalties on, story and achievements.
   * Reminders fused into HES: wake-up and study are quests; exams and "remember X" are reminders that still pay.
   * It reads and writes the phone and Google calendars.
   * A background workflow, and agents fully manipulating HES.
4. **M4 (done):** Canvas.
   * Opens as the infinite canvas, with books as draggable, connectable objects on it (`lib/assimilis/canvas/`).
   * Objects can hold anything: notes, coded graphs, media images, video, sound/audio, and code blocks (`canvas_objects.dart`).
   * Bezier connection lines with labels between books and objects; `canvas_read` and `canvas_add_object` tools so every AI agent can read and edit the canvas.
5. **M5 (done):** Team.
   * User-started team tasks (`lib/assimilis/team/`): only runs when the user taps Start, with roles (Manager, Worker, Checker, Researcher, Phone Operator) and optional per-role model overrides.
   * Uses `AgentLoop` + `AgentModels.endpointFor(...)`, hands jobs to Workstation (`workstation_task` with built-in tools), Phone Agent (`phone_task`), and nearby A2A devices, with automatic Checker verification.
   * Agent Reach, HES, Canvas, VLE, and WhatsApp tools available across every agent (including MCP `/mcp`).
6. **M6 (done):**
   * **WhatsApp (`lib/assimilis/whatsapp/`):** spare agent number (pairing-code flow showing `XXXX-XXXX` for Linked Devices) + receiver number + `whatsapp_send` tool.
   * **VLE scan tool for UWI Mona (`lib/assimilis/uwi/`):** multi-user encrypted accounts in `flutter_secure_storage`, read-only scan of courses, deadlines, announcements and course resources, plus `vle_accounts` / `vle_scan` tools.
   * **QR codes & sync (`lib/assimilis/sync/`):** QR / pairing-key connect for your own devices (key-authenticated two-way HES merge on `/hes/sync`), other players (read-only Hunter Card on `/hes/card` + A2A), and desktop/VPS sync by QR, key, or Hermes.
* **Dropped for now:** iOS.

## What is built (map of the code)

### Shell

`lib/hub/shell_view.dart`: the five tabs and the floating Core button for talking to A. It also adds the
Assimilis MCP server to the Workstation at start-up.

### Models and keys: `lib/assimilis/links/`

* `model_gateway.dart`: an OpenAI-compatible server at `http://127.0.0.1:8790/v1`.
  * It listens on loopback only, and its key is in the keystore.
  * Model ids look like `local/<file>`, `chatgpt/<model>`, `hermes/<model>` or `<provider>/<model>` (shared keys).
  * Tool calls work for every source. Images work for ChatGPT and for the key-based providers.
  * It also serves **`/mcp`**: A's whole tool list over MCP (Streamable HTTP, JSON responses).
* `agent_models.dart`: the agent list (A, HES System, Chat & Models, Workstation, Phone Agent).
  * `assign(agent, model)` backs up the agent's own setting; choosing "own" restores it.
  * `endpointFor(agent)` gives the in-app brains (HES, and later team roles) their endpoint.
  * `ensureWorkstationTools()` adds the MCP server to the Workstation.
* `chatgpt_auth.dart`: Codex device-code sign-in (the same endpoints as Hermes' `web_routers/oauth.py`).
  `complete()` turns a chat-completions request into a Responses API call, with tools, tool results and images.
* `chatgpt_sign_in.dart`: the dialog that shows the link and the code.
* `links_view.dart`: the Models & keys screen (agent rows with a model picker, downloaded models with Load,
  A's brain, Hermes, ChatGPT, shared keys).

### HES System: `lib/assimilis/hes/`

* **`hes_system.dart` (the core):**
  * Quests: daily, side, urgent, hidden, penalty and reminder, each with rewards, due times, repeats and
    penalties. Penalties are on by default.
  * `sweep()` fails overdue quests and completes module quests from your logs.
  * The feed of System windows, which also posts phone notifications.
  * Questions to the player, remembered facts, chronicle chapters, achievements.
  * `think()` is a check-in through `AgentLoop`; `chat()` lets the player talk to the System.
  * 16 `hes_*` tools. `plugins` and `contextProviders` let other modules add tools and context.
  * Data lives in the same `hes.json` as the engine (keys `system_*` and `location_history`).
* `phone_signals.dart`: the Dart side of phone data.
  * Sources: next alarm, screen time, calendars (phone and Google calendars on the phone, read and write), Health
    Connect (through the `health` plugin), and the location history HES keeps itself.
  * Tools: `calendar_*`, `health_summary`, `location_history`, `screen_time`, `next_alarm`.
  * The native side is the local plugin `local_plugins/assimilis_phone_data`. It is a plugin so that WorkManager's
    background engine also registers it.
* `hes_background.dart`: WorkManager runs every ~30 minutes.
  * Each run samples location and sweeps quests.
  * The brain checks in: a morning briefing, every N hours, and an evening review that writes a chronicle
    chapter. Quiet hours are respected.
  * `reasonAt()` is pure and tested.
* `hes_food.dart`: food photo or description to calories and macros, using the HES brain. It is logged as a
  `meal` event and also written to Health Connect.
* `hes_questionnaire_view.dart`: the "Awakening" questionnaire, driven by `assets/hes/questionnaire.json` (a Goals
  page was added). When it finishes, the System reads the answers and asks follow-up questions.
* `hes_system_tabs.dart`: the System, Quests (System quests), Story and Data tabs.
* `hes_view.dart` hosts the tabs: system, status, quests, story, data, modules, abilities, log, evolution.
* The old engine (`hes_engine.dart`, `hes_store.dart`) is unchanged apart from these additions:
  * raw `get` / `put` / `addEvent` / `export`;
  * a fix to `_fill`: its regex was `s+` and stripped every letter "s" from quest titles.

### Agents and tools

* `lib/assimilis/agent_loop.dart`: a plain tool-calling loop that runs on any OpenAI-compatible endpoint.
* `lib/assimilis/tools.dart`: A's tool list now includes HES, phone and food tools. A's `set_reminder` goes
  through `HesSystem.remind`.
* `lib/assimilis/brain.dart`: A's ChatGPT brain now runs the full tool loop through the gateway.
* **Phone Agent** (`lib/phone_agent/`): a new `assimilis_tool` action, `{"tool", "args"}`. Its prompt lists
  A's tools.
* **Workstation:** gets the tools through MCP, as the server named "Assimilis (HES, phone, calendar)".

### Android

`android/app/src/main/AndroidManifest.xml` now declares:

* calendar, location (including background), usage access, activity recognition;
* Health Connect read permissions and nutrition write;
* the Health Connect queries and the `ViewPermissionUsageActivity` alias.

Also:

* `MainActivity` is now a `FlutterFragmentActivity`, which Health Connect needs.
* `compileSdk` is 37; targetSdk is unchanged.

## What to do next, in order

1. **Done (CI green):** APK build succeeds with 6 GB Gradle heap in CI.
2. **Done (built & unit/screenshot tested):** M4 Canvas, M5 Team, M6 WhatsApp / multi-user encrypted VLE / QR Connect & HES Sync.
3. **Remaining — real Android phone verification:**
   * M3 HES: Awakening questionnaire -> first check-in, Health Connect permission flow, WorkManager background ticks (`hesBackgroundDispatcher`), Google calendar writes, food photo via ChatGPT.
   * M4 Canvas: infinite plane pan/zoom/drag, image/video/audio pickers & playback, connector creation, `canvas_read` via A.
   * M5 Team: start a team task with Manager + Worker + Checker, test Workstation & Phone Agent handoff and Save to Canvas.
   * M6: WhatsApp pairing code against Hermes/Baileys bridge, live UWI Mona VLE scan with multiple encrypted accounts, QR scan between two phones / desktop.

## Rules that still hold

* Never commit secrets, tokens or signing files. The release keystore comes from repository secrets in CI.
* Don't touch `LICENSE`, `NOTICE.md` or `third_party/` licence files.
* Don't integrate `hermes-claude-auth` or anything else that signs in to a Claude subscription: it breaks
  Anthropic's terms. Claude goes through an Anthropic API key, or through Hermes on the desktop or VPS.
* Keep VLE and other people's credentials encrypted on the device (`flutter_secure_storage`).
* Stage changes in small commits on the branch, run the checks, push, and let Shakir merge.
