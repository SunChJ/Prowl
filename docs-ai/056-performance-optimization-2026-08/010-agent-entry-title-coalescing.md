# 056.010 — Active Agents Pane-Title Coalescing

## Context

Raw-state-only emission deduplication from #647/#654 did not cover `paneTitle`. Agent TUIs animate
spinner glyphs in the terminal title at roughly 10 Hz, so a title-only frame still crossed the
terminal event stream, replaced the TCA entry, and invalidated the Active Agents overlay.

## Change

- #660 spaces title-only entry emissions to at most once per second per surface. Any status,
  session, working-directory, Profile, or other semantic row change emits immediately and carries
  the current title.
- The active detection poll provides trailing delivery. Unlike general tab titles, an Active
  Agents entry exists only while the same detection schedule remains warm, so it does not require
  a second clock-driven task.
- The initial implementation retained an obsolete pending frame through `A -> B -> A`: returning
  to the visible title was treated as a no-op without canceling `B`, which could later flash back
  and remain visible. Fork integration #664 discards pending state when the current entry again
  equals the emitted entry.
- The comparison's mutation guard now includes `launchProfileName`, and the user-facing Active
  Agents manual records the one-second maximum title cadence.

## Refs

- Original PR #660
- Fork integration PR #664
- Original implementation commits `2a026b07`, `ffe2673b`, and `80f0b11c`

## Current state

Animated title frames no longer drive high-frequency TCA state replacement. The pending value is
newest-wins, semantic changes bypass the interval, settled titles arrive from the poll, and a
sequence that returns to the visible value cannot resurrect an intermediate frame.

## Verification

- The `A -> B -> A` regression produced one expected failure against #660, then passed after the
  pending cancellation fix.
- The focused entry-title, emission-dedup, pane-title, screen-scan, and tab-title suites passed 36
  tests after merging current `main`.
- `make check` and `make build-app` passed for #664 with no warnings.

