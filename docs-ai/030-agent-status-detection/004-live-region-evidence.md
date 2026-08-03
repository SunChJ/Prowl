# 030.004 — Live-region evidence for Codex and Claude

## Context

PR #673 proposed recognizing a generic `glyph + word + elapsed counter` line anywhere in
the recent screen. Live testing on 2026-08-03 found a more fundamental issue: Prowl treated
ordinary retained transcript text as current UI state.

- Codex CLI 0.146.0 rendered `• Working (Ns • esc to interrupt)` while active. After an
  answer or user prompt mentioned `do you want` and later `yes`, the idle pane was reported
  as blocked. The same weak confirmation match also outranked a real working footer.
- Claude Code 2.1.220 rendered animated glyph status rows such as
  `✶ Philosophising… (6s · thinking with xhigh effort)`. An idle answer that quoted
  `esc to interrupt` remained classified as working because the detector searched all
  response prose above the prompt box.
- Real Codex and Claude permission prompts carried structured, current-interaction chrome:
  numbered choices plus an explicit confirmation/cancel footer. Both were cancelled during
  the reproduction; neither temporary probe file was created.

The screen-scan memoization introduced later was not causal. Its cache key includes the
detected agent and full active-screen text, so changed terminal content is reclassified.

## Change

Screen evidence is now selected and ranked per agent instead of treating every recent line
as equally live:

1. Claude viewer/overlay detection remains the strongest no-signal state.
2. Structured confirmation UI in the current interaction region remains blocked and
   outranks working evidence.
3. Claude working evidence is limited to the status rows immediately above its prompt box.
   Current spinner glyphs remain supported; PR #673's `● <word>… (<elapsed> · …)` shape is
   accepted only there and only with a complete elapsed token.
4. Codex confirmation evidence comes from strong current-interaction footer text or an
   explicit Yes/No choice structure. The generic `hasConfirmationPrompt` transcript search
   is no longer used for Codex.
5. Codex screen fallback accepts only the current `•`/`◦ Working (... esc to interrupt)`
   footer in the bottom three non-empty lines. Arbitrary reworded elapsed bullets are not a
   Codex signal.

Pure fixtures in `supacodeTests/ScreenHeuristicsTests.swift` cover live working rows, idle
prose quoting detector vocabulary, real permission dialogs, blocker/working conflicts,
strict elapsed-token boundaries, and status-shaped transcript text outside the live region.
Current behavior is documented in `docs/components/agent-detection.md`.

## Decisions and follow-ups

- A full declarative rule engine was not needed for this repair. Small agent-specific region
  helpers preserve the existing pure `String -> AgentRawState` API and minimize blast radius.
- Prowl already receives OSC titles in `GhosttySurfaceState.title`, and the current hierarchy gives
  title evidence higher priority than screen fallbacks. Passing that signal through detector
  input and cache identity remains a separate enhancement because it changes more than the
  screen classifier.
- Screen-only evidence cannot prove liveness when transcript prose exactly reproduces live
  chrome in the same terminal position. The repair deliberately narrows that residual
  ambiguity instead of claiming authoritative state.

## Refs

- PR #673 (reviewed source proposal; not merged unchanged)
- `supacode/Infrastructure/AgentDetection/ScreenHeuristics.swift`
- `supacodeTests/ScreenHeuristicsTests.swift`
- `docs/components/agent-detection.md`
