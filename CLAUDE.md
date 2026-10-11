# Voice Dictation — working agreement

Compiled from the global AI Control modules (WORKFLOW, STRUCTURE, CODING, UX)
for this project. See `.project` for the module list; rebuild with the
`rebuild-claude-md` routine when the modules change.

Voice Dictation is a **personal, local "Wispr" for Mac**: hold a global hotkey,
speak, release, and the words are transcribed and **inserted at the current
cursor** in whatever app is focused, then saved to the app's history. The audio
file is deleted once transcription succeeds. Both the transcription model and
the AI-cleanup technique are **user-selectable in settings**. English-optimized
first. It reuses the on-device `mlx-whisper` / `parakeet-mlx` approach proven in
the sibling `transcriber` project (`~/dev/transcriber`).

## Structure
- Standard AI Control scaffold lives at the project root: `.project`,
  `CLAUDE.md`, `.gitignore` (covers `.env`), `.env` (secrets, never committed),
  `updates/`, `issues.txt`.
- Keep the layout **flat and idiomatic to the chosen stack**. Add folders only
  when the project genuinely grows into them; don't nest prematurely.
- **Updates** go in `updates/YYYY-MM-DD NAME - OPEN|CLOSED/` folders, each with
  `update vX.md` (goal + phased roadmap + live status) and `wiki.md` (durable
  decisions and lessons). Reopen an update by flipping `CLOSED` → `OPEN`.

## Coding
- **Modular, isolatable.** Draw clear boundaries between the pieces — hotkey
  capture, audio recording, transcription backend, AI cleanup, cursor
  insertion, history store, settings. Each should be understandable and fixable
  on its own, with a small explicit interface and low coupling, so a bug has one
  obvious home and a model/backend can be swapped without touching the rest.
- **Minimal.** Build only what's needed. Prefer reuse over duplication; don't
  add abstraction on speculation. Borrow from `transcriber` rather than
  reinventing its on-device transcription work.
- **Idiomatic to the ecosystem.** Match the conventions and standard tooling of
  whatever stack is chosen at Phase 0; read the neighbors before writing.
- **Test what matters.** Cover the risky paths — audio capture/cleanup
  lifecycle, transcription output, cursor insertion, history persistence,
  settings round-trips. Skip trivial glue. Most roadmap phases end with tests
  that lock in what they built.

## UX
- It's a user-facing desktop app whose whole point is **speed and
  invisibility** — for any change to the surface (hotkey feedback, settings,
  history), **launch a dedicated UX-expert agent** (several in parallel for
  multi-part surfaces) and synthesize their thinking; don't improvise it.
- **Cut everything unnecessary** (Steve-Jobs default: does this element earn its
  place?). The core flow is hotkey → speak → text appears; keep it that tight.
- Minimal visual system: a small deliberate scale of fonts/colors/spacing, built
  from reusable, isolated components. Responsive and accessible by default —
  real contrast, keyboard reachability, sensible focus, honest error states.
  **Fast feedback above all**: instant recording indicator, visible state, no
  perceptible lag between release and inserted text.

## Workflow
- **Commit AND push after every logical change** — small, focused, one unit per
  commit. Plain, honest messages. Never commit secrets (`.env` stays ignored).
- **Everything lives on GitHub:** https://github.com/stageerdman/voice-dictation.
  Push regularly; nothing important stays local-only.
- **Roadmaps in phases** for any non-trivial work — design phases first, record
  them in the update's `update vX.md`, track status as you go, most phases end
  with tests.
- **Research spikes** for new APIs/libraries/designs (global hotkeys, system
  text insertion, a new transcription or cleanup backend) run *outside* the main
  code, inside the update folder, in isolation; capture findings in `wiki.md`.
- **Orchestrate:** prefer delegating to focused agents over doing everything
  inline; decompose, fan out, synthesize.
- **Verify by running the actual app** (dictate for real into a real app, check
  the inserted text and history), not just green tests, before moving on.
