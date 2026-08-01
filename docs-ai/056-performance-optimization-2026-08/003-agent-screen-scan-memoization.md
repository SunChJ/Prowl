# 056.003 — Agent Screen-Scan Memoization

## Context

An active terminal surface with a detected agent is polled every 300 ms. Before #646, each
poll read the active terminal text and reran `DetectedAgent.detectState(in:)`, even when both
the detected agent and rendered text were unchanged. The detector narrows the input to recent
lines, then performs agent-specific splitting, normalization, and heuristic matching on the
main actor.

The author reported that a sampled idle workload with 24 terminal surfaces attributed about
19% of main-thread time to the wider detection path, with `detectClaude` alone accounting for
roughly 10%. Those percentages are author measurements; this review verified the code path
and equivalence boundary, not the original capture.

## Change

- `WorktreeTerminalState.AgentScreenScan` records one `(agent, text, raw)` tuple, and
  `lastAgentScreenScanBySurface` retains the latest tuple independently for each surface.
  The dictionary is `@ObservationIgnored` because it is an implementation cache and does not
  drive UI state.
- `detectAgentState(for:tabId:)` still probes the foreground process and calls
  `readActiveText()` on every tick. If both the detected `agent` and the full active-screen
  `text` match the cached tuple, it reuses the previous `AgentRawState`; otherwise it reruns
  `DetectedAgent.detectState(in:)` and replaces the tuple.
- Only the pure raw screen classification is memoized. Presence handling, time-based state
  stabilization, seen/unseen transitions, session resolution, diagnostics, and Active Agents
  emission continue through the existing path on every applicable tick. In particular, the
  working-to-idle hold can still expire while terminal text remains unchanged.
- Cache entries are removed when a cold detection task finishes, when an individual surface
  is cleaned up, and during global agent-detection cleanup.
- `supacodeTests/AgentScreenScanCacheTests.swift` covers a cold scan, an exact cache hit, and
  invalidation when either the text or detected agent changes.

## Refs

- PR #646
- Implementation commit `b2ac2936`
- Merge commit `5a2d877f`

## Current state

The optimization preserves the existing classification contract because the cached raw value
is keyed by every input to the pure detector. It trades one retained active-screen string per
detected surface for avoiding repeated parsing and normalization of identical text.

The cache does not eliminate the complete polling cost: Ghostty text extraction, exact string
comparison, process detection, stabilization, and session matching still run as before. A
future optimization would need a reliable Ghostty screen-generation signal to bypass text
materialization itself; #646 intentionally does not introduce that broader integration.
