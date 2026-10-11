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
- [ ] Phase 0 — review transcriber + choose stack (spike)
- [ ] Phase 1 — system-wide text insertion (spike)
- [ ] Phase 2 — core dictation loop
- [ ] Phase 3 — history
- [ ] Phase 4 — settings / selectable models
- [ ] Phase 5 — AI cleanup
- [ ] Phase 6 — speed & polish

## Where we are (handoff — 2026-10-11)
**Project just created under AI Control.** Scaffold is in place (`.project`,
`CLAUDE.md`, `.gitignore`, `.env`, `updates/`, `issues.txt`), the public GitHub
repo is connected, and this INIT plan is the first commit. No app code yet.

## NEXT STEP (resume here)
Start **Phase 0**: read `~/dev/transcriber` to lift its on-device transcription
path, then spike the app shell (global hotkey + menu bar + mic capture) to
settle the stack. Capture the stack decision in `wiki.md`, update `.project`'s
stack line, and check off Phase 0.
