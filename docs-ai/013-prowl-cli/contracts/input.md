# Prowl CLI Input Contract

This document owns argv/stdin grammar. Shared target semantics live in
[targeting.md](targeting.md); JSON response contracts live in the command documents
and the executable [schema bundle](schema.md).

## Root grammar

```text
prowl [path]
prowl open [path]
prowl list | agents | focus | read | send | key | handoff | create | close
```

Bare path forms (`/`, `./`, `../`, `~/`, `file://`, `.`, `..`) enter `open`.
`--` stops option parsing. `--json` and `--no-color` are leaf-command output
options; JSON stdout always contains exactly one response envelope when parsing
succeeds.

## Shared target rules

- Generic target positions use `GenericTarget` from [targeting.md](targeting.md).
  Prefixed `pN`/`tN` handles work in `--target` and positional auto-targets.
- Typed selectors are mutually exclusive. A positional target plus selector flag is
  `INVALID_ARGUMENT`; no selector silently overrides another.
- `send` and `key` retain count-sensitive positional grammar:

| Command | 0 args | 1 arg | 2 args |
| --- | --- | --- | --- |
| `send` | stdin → focused pane | text → focused pane | target + text |
| `key` | invalid | token → focused pane | target + token |

`send p12` remains text to the focused pane. Use `send p12 'text'`, or stdin with
`--target p12`, for a target-first send.

## Lifecycle grammar

```bash
prowl create tab <worktree> [--path <directory>]
prowl create tab --worktree <worktree> [--path <directory>]
prowl create pane <pN|pane-uuid> --direction <right|left|up|down>
prowl create pane --pane <pN|pane-uuid> --direction <right|left|up|down>
prowl close <pN|tN|uuid> [--force]
prowl close --pane <uuid|pN|N> [--force]
prowl close --tab <uuid|tN|N> [--force]
```

`create tab` requires a worktree-only target. `create pane` requires a pane-only
anchor and explicit direction; it rejects `--target`, `--worktree`, `--tab`, bare
numbers, and focus fallback. `close` requires a pane-or-tab-only target and rejects
`--target`, `--worktree`, bare-number positions, and focus fallback. See
[create.md](create.md) and [close.md](close.md).

`tab create`, `tab close`, and `pane close` remain deprecated aliases for one
shipped release. They keep their legacy parser/transport behavior while emitting a
stderr warning; new automation must use the lifecycle grammar above.

## Command-specific exceptions

- `agents read <pN|pane-uuid>` is a pane-only semantic snapshot, no selectors or
  focus fallback.
- `handoff` defaults to the calling pane, not UI focus.
- `list` and `agents` are global discovery commands with no target selector.
- `open` consumes a path rather than a target.

## Transport request model

The CLI sends one typed `CommandEnvelope` over the local socket. Command spelling is
owned by `ProwlCLI` ArgumentParser declarations; target state resolution remains
app-side. Parser and handler both enforce destructive lifecycle constraints so a
malformed direct socket request cannot gain a focus fallback.
