# 049.002 — Briefing Cancellation Integrity

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-07-20 |
| **Primary PRs** | #603 |
| **Related** | [049 plan](000-plan.md), [047 cross-agent handoff](../047-cross-agent-handoff/000-plan.md), `docs/components/handoff.md` |

## Context

The PR1 HUD promises that Skip preserves the existing progress summary and that Cancel
leaves the handoff artifact untouched. The preparation effect currently transcribes a valid
source reply before the reducer accepts its completion action. A reply that wins a cancellation
race can therefore rewrite `current.md` after Skip or Cancel.

The HUD's key-capture view also swallows Tab and every unhandled key. Arrow keys and Return can
choose a target, but a keyboard-only user has no route to the in-flight Skip control.

## Change

- Separate resume reply collection from preparation-reply transcription. The HUD commits a
  reply only after its reducer confirms the run is still in the briefing stage; cancelled or
  skipped runs discard late replies without filesystem changes.
- Keep CLI preparation behavior unchanged: its synchronous flow commits an accepted reply before
  mechanical save/archive work begins.
- Add a HUD-specific Skip shortcut and advertise it in the control's tooltip, while preserving
  the terminal-isolation behavior of the key capture view.
- Add race coverage with a cancellation-insensitive resume dependency; existing
  reducer coverage exercises the shared Skip action used by the keyboard path.

## Decisions

- **The reducer is the commit authority for HUD briefing.** Cancellation is a user-visible
  transaction boundary, so a detached background task cannot own the artifact mutation.
- **Retain the shared coordinator for persistence.** Only the timing changes: callers explicitly
  commit a reply instead of `prepare` mutating as part of collection.
- **Use an explicit Skip hotkey rather than forwarding arbitrary keys.** It keeps live-terminal
  input isolated while restoring a complete keyboard path for the one long-running decision.

## Verification

- `HandoffHudFeatureTests` covers a resume dependency that returns a valid reply
  after Cancel; the handoff directory remains absent.
- Focused handoff suites pass, including the HUD state machine and artifact
  persistence paths.
- `make check` passes.
