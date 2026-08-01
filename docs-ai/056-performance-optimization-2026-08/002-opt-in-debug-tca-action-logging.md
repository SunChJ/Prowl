# 056.002 — Opt-in Debug TCA Action Logging

## Context

The root `AppFeature` reducer is wrapped by `LogActionsReducer` in
`supacode/App/supacodeApp.swift`. Before #645, every action in a Debug build paid for
`debugCaseOutput` reflection, a pre-reduction state snapshot, full-state equality, and a
`CustomDump` diff when state changed. That diagnostic path ran even when its stdout was not
observable from a Finder- or launchd-launched app.

The author reported that a sampled idle workload with 24 terminal surfaces attributed about
5% of main-thread time to this path, with the wrapper accounting for 93% of sampled
main-thread reducer time. Those percentages are author measurements; the review verified
the code path and resulting bypass, not the original capture.

## Change

- PR #645 adds the launch-scoped `PROWL_LOG_TCA_ACTIONS=1` gate in
  `supacode/Support/DebugCaseOutput.swift`.
- With the flag absent or set to any other value, the Debug wrapper immediately calls
  `base.reduce` and skips action reflection, state snapshotting and comparison, and diff
  generation.
- With the flag set, action labels use `SupaLogger.notice` so they reach the unified log and
  `make log-stream`; state diffs remain on stdout through `print`.
- `supacode/Support/SupaLogger.swift` now owns an `OSLog.Logger` in Debug as well as Release
  and exposes `notice` for diagnostics that must reach the unified log in both configurations.
- The Release branch is unchanged: it still emits the existing compact action label,
  Sentry log entry, and breadcrumb before reducing the action.
- `AGENTS.md` documents the opt-in flag and its default-off behavior.

## Refs

- Original PR #645
- Fork integration PR #653
- Original implementation commit `616bbf4b`

## Current state

The default Debug hot path now adds only the flag branch and the direct call to the wrapped
reducer; the measured reflection, state-copy/equality, and diff costs are not reachable. The
diagnostic behavior remains intentionally expensive when explicitly enabled.

The focused tests in `supacodeTests/LogActionsReducerTests.swift` cover state mutation through
the wrapper, but they do not distinguish enabled from disabled flag evaluation and their
test reducer returns no effects. The implementation's pass-through is direct and low risk,
but future changes to the gate should use an injectable configuration seam if deterministic
branch and effect-forwarding coverage becomes important.

## Verification

- `LogActionsReducerTests` passed 2 tests with `PROWL_LOG_TCA_ACTIONS` absent.
- The same focused suite passed 2 tests with `PROWL_LOG_TCA_ACTIONS=1`.
- `make check` passed.
- `make build-app` completed with no errors or warnings.
- The author-reported sampled percentages were not independently reproduced during this
  review.
