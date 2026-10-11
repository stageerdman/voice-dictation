# INIT wiki — decisions & lessons

Durable knowledge for Voice Dictation. Status lives in `update v1.md`; this is
what we've decided and learned, and why.

## What this is (and isn't)
- A **personal, local Wispr** for one owner on one Apple-Silicon Mac. The whole
  value is: hotkey → speak → text appears at the cursor, fast, everywhere.
- **Not** a cloud service, not multi-user, not a general transcription tool.
  Bulk file transcription already lives in the sibling `transcriber` project —
  this is the *live dictation* counterpart.

## Build on `transcriber`, don't restart
- `~/dev/transcriber` is a local Mac app that transcribes audio/video on-device
  with `mlx-whisper` / `parakeet-mlx` (Apple Silicon/Metal), fully offline, and
  is the owner's **most-progressed** AI-voice project. Its `src/` transcription,
  converter, and duration modules are the reusable core.
- Decision: **reuse that on-device path** for the live dictation fast path rather
  than reimplementing transcription. Phase 0 reads it in depth and lifts what
  applies. The key open question is whether on-device latency is low enough to
  feel instant for short dictations; if not, Groq's `whisper-large-v3-turbo` is
  the optional cloud fast path.

## Why these scope choices
- **Audio is transient.** The owner wants only the text; keeping audio is a
  privacy and clutter cost with no payoff here. Delete it the moment
  transcription succeeds — this is a core behaviour, baked into Phase 2.
- **Offline-first, keys optional.** The default must work with no network and no
  secret, so the app is always usable. Groq (fast cloud transcribe + cheap fast
  cleanup) and Claude (quality cleanup) are **opt-in** upgrades gated on keys in
  `.env`. That's why both secrets are marked optional.
- **Models are user-settings, not hardcoded.** The owner explicitly wants to
  adjust the transcription model and the AI-cleanup technique. Design the
  transcription backend and the cleanup step as **swappable behind a small
  interface** from the start (CODING.md modularity), so adding/removing a model
  is a settings change, not a refactor.
- **Public repo.** It's a personal tool but nothing sensitive — happy to publish.
  The only secrets are in `.env`, which stays gitignored.

## The riskiest piece: insert at the cursor, anywhere
- "Insert at the current cursor in whatever app is focused" is a **system-wide**
  action and the biggest unknown. On macOS the realistic options are the
  Accessibility API (AXUIElement), synthetic keystrokes, or
  clipboard-paste-then-restore. Each has quirks per app. This gets its **own
  spike (Phase 1)** before any real wiring, tested across several real apps, and
  the clipboard must be left untouched or faithfully restored.
- Expect to need three macOS permissions: **Microphone**, **Accessibility**
  (insertion), and **Input Monitoring** (global hotkey). Onboarding for these is
  a Phase 6 polish item but should be anticipated earlier.

## Stack: leaning native, not yet decided
- Candidates: **native Swift** (SwiftUI menu-bar app), **Python + native UI**
  (mirror transcriber), **Tauri/Electron**. Leaning native Swift menu-bar for
  the tightest global-hotkey + Accessibility-insertion integration and lowest
  latency. **Not final** — settled by the Phase 0 shell spike and recorded here
  and in `.project` once proven.

## Open, tracked in issues.txt
Stack choice, text-insertion mechanism, default transcription backend, and which
cleanup models ship — all deliberately deferred to Phase 0/1 spikes rather than
guessed now.
