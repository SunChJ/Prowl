# 066.002 — Keyboard Navigation

## Context

Agent Island shipped as a pointer-driven projection of Active Agents. That made the compact
status useful while another application was frontmost, but opening the secondary roster and
choosing an agent still required the pointer. For an efficiency tool, the island needs a
keyboard path with a dedicated, discoverable shortcut that does not overload the in-app Active
Agents panel command.

## Change

- Add a dedicated **Toggle Agent Island** shortcut (`⌘⇧P` by default) as the global hot-window
  entry while Agent Island is enabled. It is separate from **Toggle Active Agents Panel**
  (`⌘⌥P`) and participates in the existing Settings → Shortcuts resolver, including clear,
  remap, conflict handling, and reset-to-default behavior.
- Let the expanded nonactivating panel become key without activating Prowl. The compact island
  remains non-key, and collapsing the roster releases keyboard focus.
- Give the island its own transient selection and nine-entry pages. Arrow Up pairs with `k` and
  Arrow Down with `j` for selection; Arrow Left pairs with `h` and Arrow Right with `l` for paging
  while preserving the row position when possible. Space or Return opens the selected pane in
  Prowl; Escape collapses the roster. The earlier `u`/`d` page bindings are removed.
- Use `⌘1`…`⌘9` for direct activation of the nine visible slots, not globally numbered agents.
  Every visible row keeps its current shortcut label; the mapping restarts at `⌘1` after paging.
- Register `⌘⌥1`…`⌘⌥9` for the first nine strong-reminder slots while the roster is closed. The
  mapping follows the existing attention projection (Blocked before unviewed Done, newest first
  within each state), and every assigned attention cell keeps its shortcut label visible. Only
  currently backed slots are registered; roster expansion removes them until it collapses again.
- Keep a compact legend at the bottom of the roster for the persistent interaction model. Each
  arrow is grouped with its Vim counterpart (`↑ K`, `↓ J`, `← H`, `→ L`) so the direction is
  explicit; Space and Return remain grouped for opening. The row-level shortcut labels
  communicate the direct `⌘1`…`⌘9` mapping without a redundant transient or footer hint.
  The paging hint and clickable page controls appear only when multiple pages exist.
- Keep the selection presentation-only until activation. It does not mutate Active Agents state,
  mark entries as handled, or focus a terminal while merely navigating.

The global entry uses Carbon hot-key registration, which consumes the configured chord without
requiring Accessibility or Input Monitoring permission. Once expanded, ordinary navigation keys
are handled locally by the key panel, so they do not leak into the previously frontmost app.

## Refs

- Implementation: `1f32784a`
- PR: #758

## Current state

Implemented on 2026-09-03. The island owns a dedicated, remappable `⌘⇧P` global shortcut and
keyboard focus only while expanded. It supports transient selection, nine-entry paging through
Arrow Left/Right or `h`/`l`, visible-slot activation, confirmation, and dismissal. Visible rows
keep their `⌘1`…`⌘9` labels; the footer permanently shows movement and confirmation, adding
paging only when a second page exists. Collapsed strong reminders expose `⌘⌥1`…`⌘⌥9` for their
first nine priority-ordered cells, using the same focus path as a pointer click.

Verification completed with `make check`, `make test`, and `make build-app`; all passed with zero
test or build failures. Final native screenshot capture was unavailable because the computer-use
native pipe could not start; the final layout change is covered by source inspection and the
successful Debug build.
