# 030.005 — Structured confirmation live regions

## Context

Review probes on PR #674 found that confirmation evidence was still wider than the live
UI it represented:

- Codex treated the last ordinary `›` prompt as a confirmation boundary. Confirmation
  vocabulary in that user input, or in a completed response before the next prompt was
  painted, therefore reported blocked and could outrank a real working footer.
- Claude looked ten lines above a bare idle `❯` prompt. A short completed response that
  mentioned a confirmation question therefore remained blocked after the input box returned.

Both transitions are observable between 300 ms screen polls, so waiting for the next paint
does not make the false state harmless.

## Change

- Codex strong confirmation footers now require a current numbered selected row and must
  remain in the bottom live footer region. Explicit Yes/No choice structure remains a
  separate positive signal.
- Claude only opens its surrounding confirmation region when the current `❯` row is a
  numbered selection. A bare or ordinary input prompt cuts off preceding transcript prose.
- Regression fixtures cover confirmation vocabulary in a Codex user prompt, in a completed
  Codex response before the next prompt paint, and in a short Claude response above an idle
  prompt. Existing real confirmation fixtures remain positive controls.

The implementation remains private pure `String -> AgentRawState` classification in
`supacode/Infrastructure/AgentDetection/ScreenHeuristics.swift`; polling, caching, and state
stabilization are unchanged. Current behavior is described in
`docs/components/agent-detection.md`.

## Refs

- PR #674
- `supacode/Infrastructure/AgentDetection/ScreenHeuristics.swift`
- `supacodeTests/ScreenHeuristicsTests.swift`
- `docs/components/agent-detection.md`
