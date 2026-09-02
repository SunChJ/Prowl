# 066.009 — Carousel Stability and Workflow Parity

## Context

Review of PR #753 at `bab88299` found two merge blockers:

- every `agentEntryChanged` action cancelled and recreated the four-second carousel effect. Pane
  title refreshes arrive roughly once per second without changing Working membership or order, so
  repeated title-only updates could postpone the first carousel tick indefinitely;
- `origin/main` added Workflow role badges and a **Run Workflow** context-menu path to Active
  Agents after the Agent Island branch diverged. The island roster retained a copied older
  subtitle and context menu, so it could not present or dispatch the new Workflow behavior.

## Change

- Merge the latest `origin/main` into the feature branch and retain `runWorkflowTapped`,
  `openWorkflowStart`, role-badge synchronization, and their tests.
- Compare the ordered Working-entry IDs before and after roster mutations. Preserve the current
  carousel item and running timer when that projection is unchanged; rebuild the timer only when
  Working membership/order or enabled, hover, or expansion gates materially change.
- Add a `TestClock` regression that sends title-only refreshes through both the four- and
  eight-second boundaries and requires both carousel ticks to arrive on schedule.
- Extract the current Active Agents subtitle/help presentation and context-menu content into
  shared Active Agents components. Compose those components from both the sidebar panel and the
  island roster, including Workflow role badges and **Run Workflow**, instead of copying either
  behavior into Agent Island.
- Keep row layout, Agent lifecycle semantics, and the existing Workflow start path unchanged.

## Verification

- Targeted `ActiveAgentsFeatureTests`, `AgentIslandRosterContentTests`, and
  `WorkflowStartFeatureTests` pass, including title-only refreshes across both carousel ticks.
- `make check` passes.
- `make test` passes with 2,989 tests and zero failures.
- `make build-app` passes with zero warnings or errors.
- Record physical-notch, Stage Manager, fullscreen/Spaces, and display hot-plug behavior as a
  manual release-verification item unless those environments are exercised during this change.

## Refs

- [Agent Island plan](000-plan.md)
- [Agent Island action log](001-action.md)
- [PR #753](https://github.com/onevcat/Prowl/pull/753)
