# 047.006 — Remove Fork Briefing

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-01 |
| **Primary PRs** | #643 |
| **Related** | [047 plan](000-plan.md), [047.004](004-inline-handoff-redesign.md), [047.005](005-hud-request-ownership.md), [055 runtime expansion](../055-agent-profile-runtimes/000-plan.md) |

## Context

The inline redesign made the live source agent the primary and best briefing
author, but retained a recorded-session resume/fork as a rescue path. That
fallback required a second agent process, exact native-session identity,
runtime-specific immutable-fork flags, deterministic output capture, a timeout,
and failure degradation. It also made native `--resume` support look like a
generic runtime capability even though Profile launch and Handoff do not need
it.

The remaining use cases did not justify that protocol. A wedged or unavailable
source already has a deterministic Context Only path based on generated state
and archived artifacts. A third-party CLI caller should not trigger a hidden,
potentially paid model turn merely because it omitted briefing input.

## Decision

- The live source agent is the only briefing author. It passes a validated
  document through `--brief -`.
- Context-only handoff is always explicit through `--no-brief`, except when the
  HUD cannot deliver its already-authorized request to the source pane; that
  failure proceeds context-only automatically.
- Every CLI caller, including one targeting another pane, must provide
  `--brief` or `--no-brief`. Missing input returns `BRIEF_REQUIRED` with zero
  side effects.
- Native resume remains useful research and detection metadata, but is not
  part of `AgentRuntimeAdapter` or Handoff admission.

## Change

- Removed `AgentRuntimeResumeAdapter`, `AgentResumeRequest`,
  `AgentRuntimeClient`, the Claude/Codex fork invocation implementations, and
  resume-specific registry/error cases.
- Removed `HandoffBriefing.fork` / `.failed`, fork collection from
  `HandoffCoordinator`, native session ownership from `HandoffSourceContext`,
  and third-party implicit fork selection from `HandoffCommandHandler`.
- Reduced the HUD state machine from `requesting → forking → finishing` to
  `requesting → finishing`; removed Fork Briefing and its cancellation phase.
- Kept request supersession and the non-cancellable artifact commit boundary so
  a queued injected request cannot race a user-selected Context Only fallback.

## Verification

- Contract tests first failed for missing-brief rejection and
  failed-injection context-only behavior, then passed after the removal.
- Focused `HandoffCommandHandlerTests`, `HandoffHudFeatureTests`,
  `AgentRuntimeAdapterTests`, and `AppFeatureHandoffTests`: 56 passed, zero
  warnings.
- `make test`: 2152 passed, with five pre-existing dependency-scan warnings;
  `make check` and `make build-app`: passed with zero warnings.
- `make build-cli` and `make test-cli-smoke`: passed;
  `make test-cli-integration`: 64 passed.
