# 056.004 — Agent Entry Emission Deduplication

## Context

Agent detection polls active surfaces as frequently as every 300 ms. The raw detector state
can oscillate with an agent's animated terminal output even when the stabilized display state,
session, working directory, and every other consumer-visible field remain unchanged. Before
#647, each raw-only change emitted a new `ActiveAgentEntry`, traversed the terminal event stream,
updated `ActiveAgentsFeature.State.entries`, and invalidated the sidebar view that read the
entries while constructing the repository list.

The author measured nine `SidebarListView.body` evaluations and 99 repository-section
evaluations over an eight-second working-agent capture. Those counts are author measurements;
the review verified the emission and observation path, not the original instrumented capture.

## Change

- #647 adds `ActiveAgentEntry.equalsIgnoringRawState(_:)` and uses it in
  `WorktreeTerminalState.emitAgentEntry`. A raw-state-only change remains in the terminal-owned
  `surfaceAgentStates` snapshot but no longer emits through TCA.
- `SidebarActiveAgentsOverlay` owns the `activeAgents.entries` read and row-display computation.
  Entry changes therefore invalidate the overlay rather than the parent
  `SidebarListView.body` that constructs every repository section.
- The original PR would also have made `prowl agents` report the raw state from the most recent
  visible entry change. The fork follow-up keeps the existing point-in-time CLI contract:
  `AgentsRuntimeSnapshot` captures live `PaneAgentState.fallbackState` values from
  `WorktreeTerminalManager`, and `AgentsCommandHandler` uses that value when available while
  retaining the reducer entry as a defensive fallback.
- The emission-equivalence regression test changes every stored `ActiveAgentEntry` field one at
  a time. The follow-up adds the previously omitted `launchProfileName`, which affects the agent
  display name and must force a new entry.

## Refs

- Original PR #647
- Fork integration PR #654
- Original implementation commits `7903375c` and `e77ba660`
- Fork follow-up commit `d209df96`

## Current state

Raw detector flicker no longer crosses the terminal-to-TCA event boundary or invalidates the
sidebar. Stabilized status, session, title, working-directory, Profile attribution, and other
entry changes still emit normally. CLI requests read the latest terminal-owned raw state on the
main actor, so the optimization does not turn `raw_state` into a delayed value.

The follow-up deliberately does not add another raw-state stream or dependency client. CLI
snapshot construction already receives `WorktreeTerminalManager`, and the live state is copied
only when a CLI request arrives.

## Verification

- The original focused `AgentEntryEmissionDedupTests` and `CLIAgentsCommandHandlerTests` passed
  seven tests before the follow-up.
- A CLI test was changed first to require a live raw state different from the reducer entry; it
  failed to compile until the live-state snapshot input existed.
- The focused suites then passed seven tests, including raw-only deduplication, visible-state
  emission, removal/re-attachment, full-field equality protection, and live CLI raw-state
  precedence.
