# 056.006 — Terminal Tab Title Coalescing

## Context

Agent TUIs commonly animate a spinner in the terminal title through OSC 2 updates at roughly
10 Hz. `TerminalTabManager.tabs` is observed as one array, so every visible title write rebuilds
all tab views and drives AppKit layout and Core Animation work across the window. The original
implementation also resolved each row's tab with a linear search, making one tab-bar rebuild
quadratic in the number of tabs.

The author sampled a 300-second workload with 32 tabs and attributed 82.5% of one main-thread
core to SwiftUI graph work, Core Animation commits, and AppKit layout. The review verified the
structural invalidation path and the resulting behavior; it did not independently reproduce that
exact profile.

## Change

- #649 builds one tab lookup dictionary for each tab-bar render instead of scanning the tab
  array for every row.
- Live terminal-title writes are coalesced independently per tab, with at most one visible write
  per second. Only the newest withheld title is retained, so bursts do not create queues.
- A clock-driven trailing task flushes the newest withheld title at its deadline even when agent
  detection is absent or has moved to its cold schedule. The first implementation tied delivery
  to the detection poll and could leave the final title stale indefinitely for a non-agent
  program.
- If a title sequence returns to its currently visible value, the obsolete withheld frame is
  discarded. This prevents `A -> B (held) -> A` from later flashing the stale `B` value.
- Closing or pruning a tab removes its coalescing bookkeeping. Custom titles continue to mask
  live values while preserving the newest underlying title, and title-locked tabs remain
  immutable.
- A trailing flush refreshes Active Agents through the same title-change path as an immediate
  write. User-facing terminal documentation records the one-second maximum visible lag.

## Refs

- Original PR #649
- Fork integration PR #656
- Original implementation commits `14a6c1d8` and `b77888f3`
- Fork follow-up commit `5c7e2a35`

## Current state

Animated live titles no longer mutate the observed tab array on every frame. Each tab has an
independent deadline, and the scheduled task always arms the earliest one, flushes all entries
that are due, then re-arms for the next later deadline. Cancellation and a stored-deadline guard
prevent a replaced or reverted task from applying stale state.

The coalescing boundary is intentionally limited to the shared tab title. An individual pane's
raw title remains available to split-pane and CLI consumers, preserving the existing semantic
distinction between a tab title and a surface title.

## Verification

- The original title-coalescing, flush-refresh, and pane-title suites passed 21 tests before the
  follow-up.
- Regression tests were added first for stale `A -> B -> A` delivery and trailing delivery with
  no agent-detection task; each failed against the original implementation before its fix.
- A clock-driven two-tab test covers re-arming after the first deadline so a later pending title
  cannot be stranded.
- The affected title, Active Agents, and terminal-manager suites passed 45 tests before the final
  multi-tab addition; the new test also passed independently.
- `make check` passed before integrating the latest `main`.
- `make build-app` completed with no errors or warnings before integrating the latest `main`.
