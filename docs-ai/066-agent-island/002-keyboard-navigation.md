# 066.002 — Keyboard Navigation

## Context

Agent Island shipped as a pointer-driven projection of Active Agents. That made the compact
status useful while another application was frontmost, but opening the secondary roster and
choosing an agent still required the pointer. For an efficiency tool, the island needs a
keyboard path that builds on an existing Prowl concept instead of asking users to memorize an
unrelated global shortcut.

## Change

- Reuse the resolved **Active Agents** shortcut (`⌘⌥P` by default) as the global hot-window
  entry while Agent Island is enabled. In Prowl it keeps toggling the sidebar panel; from another
  application it toggles the island roster. User remapping and disabling continue to flow from
  the existing keybinding resolver.
- Let the expanded nonactivating panel become key without activating Prowl. The compact island
  remains non-key, and collapsing the roster releases keyboard focus.
- Give the island its own transient selection and nine-entry pages. Arrow Up/Down and `k`/`j`
  move the selection; `u`/`d` move one page while preserving the row position when possible;
  Space or Return opens the selected pane in Prowl; Escape collapses the roster.
- Use `⌘1`…`⌘9` for direct activation of the nine visible slots, not globally numbered agents.
  Every visible row keeps its current shortcut label; the mapping restarts at `⌘1` after paging.
- Keep a compact legend at the bottom of the roster for the persistent interaction model:
  Arrow Up/Down or `j`/`k` select, `u`/`d` page, and Space or Return open. The row-level shortcut
  labels communicate the direct `⌘1`…`⌘9` mapping without a redundant transient or footer hint.
  Clickable page controls expose the current page beside that legend when multiple pages exist.
- Keep the selection presentation-only until activation. It does not mutate Active Agents state,
  mark entries as handled, or focus a terminal while merely navigating.

The global entry uses Carbon hot-key registration, which consumes the configured chord without
requiring Accessibility or Input Monitoring permission. Once expanded, ordinary navigation keys
are handled locally by the key panel, so they do not leak into the previously frontmost app.

## Refs

PR pending.

## Current state

Implemented on 2026-09-03. The island now reuses the resolved Active Agents shortcut globally,
owns keyboard focus only while expanded, and supports transient selection, nine-entry paging,
visible-slot activation, confirmation, and dismissal. Visible rows keep their `⌘1`…`⌘9` labels;
the footer permanently shows only movement, paging, and confirmation hints.

Verification completed with `make check`, `make test`, and `make build-app`; all passed with zero
test or build failures. Final native screenshot capture was unavailable because the computer-use
native pipe could not start; the final layout change is covered by source inspection and the
successful Debug build.
