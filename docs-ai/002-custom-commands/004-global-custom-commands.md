# 002.004 — Global Custom Commands

## Context

Repository custom commands are unavailable when the same workflow should be run from
multiple repositories. Issue #282 requests a user-owned command list that is available
for every selected worktree without changing repository configuration.

## Change

- Persist global commands separately in `global.onevcat.json` through a dedicated
  `UserGlobalSettings` shared key.
- Resolve repository and global commands once in `AppFeature`: repository commands retain
  their order and hide global commands whose trimmed, case-insensitive title matches.
- Carry source-qualified identities through execution, command palette entries, menus,
  toolbars, and keybindings. Local shortcuts win collisions with global shortcuts.
- Reuse the existing command editor for global settings and label global toolbar items
  with the system globe symbol.

## Decision

The global settings are intentionally not added to upstream-owned `GlobalSettings`.
Keeping a fork-owned JSON file limits Codable and merge surface while preserving the
existing local settings isolation.

## Verification

Regression coverage will prove persistence, local precedence, source-qualified command
IDs, active-worktree updates, palette dispatch, and shortcut conflict handling. User
documentation will be updated with the resulting configuration and precedence rules.
