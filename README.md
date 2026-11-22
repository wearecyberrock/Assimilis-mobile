# Assimilis Mobile

An Android app anyone can use: talk to **A** (Assimilis) hands-free, take notes and do maths in Canvas, level up your life with HES, set reminders, read the web, run AI models on your phone (or pool phones and PCs for bigger ones), and let A use your phone for you. First launch walks you through setup: your name, a brain (free OpenRouter key, a local model, ChatGPT, or your own Assimilis server) and permissions.

**Get it without building:** every push to `main` builds an APK in GitHub Actions (Actions tab → latest green run → `assimilis-mobile-apk`).

One Android app that combines **PrivateLM** (cross-platform-llm-client), **PocketStrike** and **PrivateAgent**
(private-agent). Everything runs on the phone: local models, plus cloud models if you add API keys. There is
no server.

When you open the app you land on the **Assimilis hub**, with four areas:

| Area | From | What it does |
|---|---|---|
| **Chat & Models** | PrivateLM | Chat with local GGUF models (llama.cpp), generate images on the phone (Stable Diffusion), run LiteRT models, and use cloud models (OpenAI, Claude, Gemini, Kimi) with your keys. Also handles model downloads, vision and documents. |
| **Workstation** | PocketStrike | ReAct agent with tools, MCP servers, Hermes memory (USER / MEMORY / SOUL), file tools, more providers (OpenAI, Claude, Gemini, DeepSeek, Ollama), its own local models and image generation. |
| **Phone Agent** | PrivateAgent | Tell it a task and it uses your phone: reads the screen, taps, types, scrolls, opens apps. It also has voice commands and a floating bubble. |
| **Canvas** | Assimilis Notes | Notebooks > sections > pages, LaTeX maths, calculator, graphs, derivatives and integrals, plus an infinite canvas with cards, connectors and ink. |
| **HES** | organelle/hes | Stats E→SSS+, level, class, daily quests, trackers, quick log. |
| **Alarms & Reminders** | new | Alarms, timers, and repeating reminders. |
| **Agent Reach** | components/agent-reach | Read-only web search and readers. |
| **Safety & Permissions** | new | Allow each Android permission (or **Allow all**), and pick the Phone Agent mode: **Ask me** or **Full allow**. |

## Phone Agent modes

* **Ask me** (default): before a risky action, an Allow / Deny card from Assimilis appears on screen.
  * Risky actions are sending, paying, buying, deleting, transferring, posting, pressing Enter in a non-search
    field, running a shell (Shizuku) command, and anything inside a banking or payment app.
  * Deny stops the task.
  * Typing into password fields is refused in this mode.
* **Full allow**: no prompts. The agent does everything it decides to do, including passwords and shell
  commands. You turn it on in **Safety & Permissions**, and it asks you once before switching.

The check lives in the Android code (`SafetyGate.kt`), so it applies to every path the agent can take.

## Build it on Windows

You need Flutter, which is already installed at `C:\Users\shaki\flutter`, plus the Android SDK and Android
Studio's Java, which are already on this PC. The first build downloads the Android NDK and CMake
automatically (about 2–3 GB).

```powershell
cd C:\Users\shaki\Documents\AssimilisMobile\app
```

```powershell
$env:Path = "C:\Users\shaki\flutter\bin;$env:Path"; $env:ASSIMILIS_ALLOW_DEBUG_RELEASE_SIGNING = "true"; flutter build apk --release --target-platform android-arm64
```

The APK is written to `build\app\outputs\flutter-apk\app-release.apk`.

That APK is signed with the debug key, which is fine for your own phone. To publish it, copy
`android/key.properties.example` to `android/key.properties` and point it at your own keystore. Never commit
that file.

## Install it on an Android phone

1. Copy `app-release.apk` to the phone (USB, Google Drive or Telegram) and open it. Allow "Install unknown apps"
   for whichever app you opened it with.
2. Or, with USB debugging on, install it from the PC:

   ```powershell
   & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r build\app\outputs\flutter-apk\app-release.apk
   ```

3. Open **Assimilis**, go to **Safety & Permissions** and tap **Allow all**.
4. Turn on **Assimilis Phone Control** in Accessibility settings.
   * If Android says the setting is **restricted** (this happens with APKs not installed from the Play Store),
     go to **Settings → Apps → Assimilis**, open the **⋮** menu, choose **Allow restricted settings**, then try
     again.
5. Add an API key in the area you want to use (an OpenRouter key works for the Phone Agent), or download a
   local model in **Chat & Models**.

It needs a 64-bit ARM phone (practically every Android phone from 2019 on) running Android 9 or newer. Phone
control works best on Android 11+.

## Project layout

```
lib/main.dart              start-up: PrivateLM services + Phone Agent init + shared Riverpod scope
lib/hub/                   Assimilis hub, Safety & Permissions screen, brand
lib/ (rest)                PrivateLM (GetX)
lib/workstation/           PocketStrike (Riverpod + go_router + Drift)
lib/phone_agent/           PrivateAgent
local_plugins/             llama.cpp, Stable Diffusion (prebuilt arm64 libs), LiteRT, overlay window
android/app/src/main/kotlin/com/assimilis/mobile/
  MainActivity.kt          PrivateLM native code + Phone Agent channel hookup
  AgentAccessibilityService.kt  screen reading and actions
  AgentChannel.kt          Flutter <-> service bridge; every tap/type/Enter goes through SafetyGate
  SafetyGate.kt            Ask me / Full allow, Allow/Deny overlay
```

See `NOTICE.md` for where each part came from. `STATUS.md` lists what works and what is stubbed.
