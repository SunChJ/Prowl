# Prowl CLI Targeting Contract

> Normative target-language contract. Command contracts link here rather than redefining resolution rules.

## References

```text
GenericTarget ::= PaneUUID | TabUUID | PaneHandle | TabHandle | WorktreeRef
PaneHandle    ::= "p" PositiveInteger
TabHandle     ::= "t" PositiveInteger
WorktreeRef   ::= worktree id | name | path
```

- UUIDs are the canonical JSON and cross-process automation identity.
- `pN` / `tN` are current-process interaction handles. They are globally monotonic,
  never reused by a running Prowl process, and invalid after restart or target close.
- Bare `N` is only a typed `--pane N` / `--tab N` handle. In generic positions it
  remains a worktree reference.
- Generic `pN` resolves only as a pane and generic `tN` resolves only as a tab. A
  stale prefixed handle fails with `TARGET_NOT_FOUND`; it never falls back to a
  worktree named `pN` or `tN`. Use `--worktree p12` for that worktree.

## Generic resolution

Generic target positions are `--target` and the target-first positional forms of
`focus`, `read`, `send`, `key`, and `handoff`.

1. `pN` resolves as a pane handle.
2. `tN` resolves as a tab handle.
3. A UUID resolves pane first, then tab.
4. Any other spelling resolves as a worktree id, name, or path.

Typed selectors remain mutually exclusive:

```text
--target <GenericTarget>
--worktree <WorktreeRef>
--tab <TabUUID|tN|N>
--pane <PaneUUID|pN|N>
```

A positional target and any selector flag are mutually exclusive and fail with
`INVALID_ARGUMENT`; flags never silently override a positional target.

## No-target behavior

- `focus`, `read`, `send`, `key`, and legacy `tab create` retain current UI-focus
  fallback for interactive use.
- `handoff` defaults to the pane that spawned the CLI process, never UI focus.
- `agents read` always requires a pane argument.
- New `create tab` and `close` always require an explicit target.

Automation should use UUIDs or an explicit same-session `pN`/`tN` target; it must
not rely on a focus fallback.

## Typed lifecycle targeting

Lifecycle commands intentionally do not use generic worktree projection:

```text
create tab <WorktreeRef> | --worktree <WorktreeRef>
close <PaneUUID|TabUUID|pN|tN> | --pane <PaneUUID|pN|N> | --tab <TabUUID|tN|N>
```

`close` rejects `--target`, `--worktree`, bare-number positionals, UI-focus
fallback, and mixed positional/flag targeting. `create pane` is reserved for
[#699](https://github.com/onevcat/Prowl/issues/699): it will require a pane-only
anchor and direction.
