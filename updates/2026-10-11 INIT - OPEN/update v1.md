# INIT — Voice Dictation

**Status:** OPEN · created 2026-10-11 · plan v1

## Goal
A **personal, local "Wispr" for Mac** — just for the owner. Hold a global hotkey
(e.g. `⌘ + ⌥`), speak, release, and the spoken words are transcribed and
**inserted at the current cursor position** in whatever app is focused, and also
saved to the app's **history**. It must feel **fast** (near-instant), be
**English-optimized** to start, and let the owner **adjust the transcription
model and the AI-cleanup technique in settings**.

Per dictation:
1. Capture the mic to a temporary audio file while the hotkey is held.
2. Transcribe (on-device by default; optional fast cloud path).
3. Optionally run an **AI cleanup** pass (punctuation, filler removal, light
   formatting) — model/technique chosen in settings.
4. **Insert the text at the current cursor**, system-wide.
5. Save the text to **history**.
6. **Delete the audio file** once transcription has succeeded — only text is kept.

This builds on `~/dev/transcriber`, whose on-device `mlx-whisper` /
`parakeet-mlx` stack is the biggest proven win across the owner's AI-voice
projects. We reuse that transcription approach for the live dictation path
rather than starting over.

## Scope decisions (agreed at INIT)
- **Visibility:** **public** GitHub repo (`stageerdman/voice-dictation`).
- **Audience:** single user (the owner), one Mac (Apple Silicon). No multi-user,
  no sync, no cloud account — a personal tool.
- **Language:** optimize for **English** first; keep the model selectable so
  other languages are a later setting, not a rewrite.
- **Audio retention:** audio is **transient** — deleted immediately after a
  successful transcription. Only the resulting text lives in history.
- **Offline-first:** the default transcription path runs **on-device** (no
  secret required). Cloud (Groq) and premium cleanup (Claude) are **optional**
  settings, gated on keys in `.env`.

## Open decisions (Phase 0 — also in issues.txt)
- **App shell / stack.** Native Swift (SwiftUI menu-bar app) vs Python + native
  UI (mirror transcriber) vs Tauri/Electron. Needs: reliable **global hotkey**,
  **menu-bar** presence, **system-wide text insertion**, low latency. Leaning
  **native Swift menu-bar** for the tightest hotkey + Accessibility insertion and
  lowest latency; confirm in the Phase 0/1 spikes.
- **Text-insertion mechanism** (the riskiest piece): Accessibility API paste vs
  simulated keystrokes vs clipboard-paste-then-restore. Decided by spike.
- **Cleanup models** that ship as selectable options and the default.

## Phased roadmap
Each phase ends by **verifying the real thing runs** (dictate for real into a
real app), then a commit + push. Phases touching a new API (global hotkey,
system text insertion, a transcription or cleanup backend) start with a
throwaway **research spike** inside this update folder; findings go in `wiki.md`.

### Phase 0 — Review transcriber + choose the stack 🔬 spike first
- Read `~/dev/transcriber` and extract the reusable **on-device transcription**
  path (which backend, model list, how audio is fed in, real latency for short
  clips).
- Spike the **app shell**: prove a global hotkey, a menu-bar item, and mic
  capture in the candidate stack. Settle Swift vs Python vs Tauri.
- **Verify:** a bare shell launches, sits in the menu bar, and the hotkey fires
  a logged event. Record the stack decision in `wiki.md` and `.project`.

### Phase 1 — System-wide text insertion 🔬 spike first
- Spike inserting text **at the current cursor** across several real apps
  (browser, Notes, a code editor): Accessibility API vs synthetic keystrokes vs
  clipboard-paste-and-restore. Handle the macOS **Accessibility** permission.
- **Verify:** typed-in text lands at the caret in 3+ different apps, with the
  clipboard left untouched (or faithfully restored).

### Phase 2 — Core dictation loop (hotkey → record → transcribe → insert)
- Wire the pieces: hold hotkey → record to temp file → on-device transcribe →
  insert at cursor → **delete the audio file**. English, no cleanup yet.
- Clear recording indicator (menu-bar state) and honest error states.
- **Verify:** real end-to-end dictation into a real app feels fast; the temp
  audio file is gone afterward.

### Phase 3 — History
- Persist each dictation's text (timestamp, duration, app inserted into) to a
  local store; a simple history view to browse/copy/re-insert past entries.
- **Verify:** dictations appear in history; survive restart; copy/re-insert work.

### Phase 4 — Settings: selectable models (UX agents)
- Settings surface to pick the **transcription model** (on-device variants +
  optional Groq cloud) and global **language**. Defaults sensible and fast.
- **Verify:** switching models changes the backend used and persists.

### Phase 5 — AI cleanup (selectable technique)
- Pluggable cleanup step after transcription: **none / local LLM / Groq llama /
  Claude**, chosen in settings, with a tunable prompt/technique. Must not add
  perceptible lag — run inline only if fast, otherwise insert raw then refine, or
  make it opt-in.
- **Verify:** cleanup visibly improves output for the chosen model; raw mode is
  still instant.

### Phase 6 — Speed & polish
- Latency pass end-to-end (warm models, stream where possible), empty/error
  states, onboarding for the three macOS permissions (Mic, Accessibility, Input
  Monitoring), menu-bar polish.
- **Verify:** short dictations feel instant from release to inserted text.

## Status tracking
- [x] Phase 0 — review transcriber + choose stack (spike) — DONE. Stack: native
      Swift shell + Python transcription sidecar. Shell spike VERIFIED on the
      owner's Mac: menu bar + global ⌘+⌥ hold-to-talk + mic→wav all work.
- [x] Phase 1 — system-wide text insertion — DONE. `TextInserter`:
      clipboard-paste-and-restore at the caret (needs Accessibility).
- [x] Phase 2 — core dictation loop — DONE & VERIFIED by the owner in a real app
      ("works very well"): hold ⌘⌥ → record → Parakeet transcribe → insert →
      delete audio, with menu-bar state + bottom-center waveform HUD.
- [x] Phase 3 — history — DONE. `HistoryStore` (JSON, text-only) + day-grouped,
      searchable History window with copy/re-insert. Unit-tested.
- [x] Phase 4 — settings / selectable models — DONE. Two-tab Settings; model
      picker (on-device variants + optional Groq), language. Unit-tested.
- [x] Phase 5 — AI cleanup — DONE (key-free). none / Claude CLI (`claude -p`
      headless, Haiku) / local MLX LLM (gemma via sidecar). Both verified on
      sample text. NOT YET tested on the owner's real speech.
- [~] Phase 6 — speed & polish — IN PROGRESS. Tests green; real dictation works.
      Remaining: test cleanup on real speech; latency pass (cleanup is a few
      seconds — consider insert-raw-then-refine); permission onboarding; a
      smaller/faster local cleanup model; in-app model-download UX.
  - [x] **Activity/Error Log + permission self-check (2026-10-12).** New
        `Logging/LogStore` (JSON at `…/VoiceDictation/log.json`, newest-first,
        capped 500, writes off the hot path). Every pipeline stage and failure
        now logs with a category; the sidecar's stderr (previously discarded in
        `MLXSidecar`) is captured; at launch a self-check logs Accessibility &
        Microphone grant state. The History window gained a toolbar
        `History | Log` segmented switcher (UX-agent design) with a red dot on
        `Log` for unseen errors, a level filter (All / Warnings & Errors /
        Errors), day-grouped rows (level glyph + mono time + category pill +
        tap-to-expand detail), Copy All / Reveal in Finder / Clear Log…, and
        per-row Copy Line / Copy Detail. 8 new unit tests (17 total) green.
  - **Diagnosed the owner's "records but no text" report:** the self-check
        confirmed **Accessibility NOT granted**. Root cause is the documented
        ad-hoc-signing grant reset — the last reinstall (Oct 11 21:23) came right
        after the last working dictation (21:21) and wiped the Accessibility
        grant, so the global hotkey still fired and the mic still recorded but
        the ⌘V insertion (gated on `AXIsProcessTrusted()`) silently no-op'd. Fix:
        re-grant Accessibility (and Mic) to *Voice Dictation Dev.app* and
        relaunch. The log now makes this self-evident instead of a 1.6s flash.

## Where we are (handoff — 2026-10-11)
**The whole app is built and the core flow works on the owner's Mac.** Native
Swift AppKit menu-bar shell + a warm Python MLX sidecar. Real dictation
(hold ⌘⌥ → speak → text at the cursor) was tried by the owner and "works very
well." Phases 0–5 are done; Phase 6 (polish) is in progress.

Modular Swift at the repo root, each piece behind a small interface:
`Hotkey/`, `Audio/`, `Transcription/` (`MLXSidecar` shared client +
`SidecarTranscriber` + optional `GroqTranscriber`), `Cleanup/`, `Insertion/`,
`History/`, `Settings/`, `Pipeline/DictationController`, `App/` (UI). Sidecar at
`sidecar/transcribe_server.py` serves `transcribe` (Parakeet default) and
`clean` (MLX LLM) ops. 9 unit tests green; clean build, 0 warnings.

**Cleanup is key-free** (owner's requirement): `claude -p` headless (Haiku) or a
local MLX LLM (gemma-3-12b, warm in the sidecar). Both verified on sample text,
NOT yet on the owner's real speech.

**Dev workflow:** `./scripts/install.sh` builds + bundles + embeds the sidecar +
**ad-hoc signs** to `/Applications/Voice Dictation Dev.app` (no keychain prompt).
The stable-identity path is still available via `VOICE_DICTATION_SIGN_IDENTITY`
but ad-hoc is the friction-free default; cost is re-granting Mic/Accessibility
after a rebuild. See [[dev-app-run-workflow]] and the wiki.

## NEXT STEP (resume here)
**Test cleanup on the owner's real speech.** Record a sample
(`ffmpeg -f avfoundation -i ":1" -t 20 -ar 16000 -ac 1 /tmp/vd_sample.wav`), then
run it through Parakeet → both cleanup modes and compare raw vs. cleaned on real
dictation (not just the synthetic sample used so far).

Then finish Phase 6 polish:
- **Latency:** cleanup adds a few seconds (CLI ~8s warm / 28s cold; local gemma
  ~2–5s warm). Consider **insert-raw-immediately then refine in place**, or a
  smaller/faster local model (a 3B instruct would be ~1s) so cleanup isn't a
  perceptible wait.
- Permission onboarding (Mic/Accessibility/Input Monitoring) and first-run model
  download UX (the UX specs for this are captured — see the UX agent output).
- Close this INIT update once Phase 6 lands; flip the folder to CLOSED.
