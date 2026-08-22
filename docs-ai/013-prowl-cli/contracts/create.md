# `prowl create` Contract

## Status

Current version: `prowl.cli.create.v1`.

`create` is the action-first lifecycle namespace. V1 exposes deterministic tab and split-pane creation.

## Input

```bash
prowl create tab <worktree> [--path <directory>] [--json]
prowl create tab --worktree <worktree> [--path <directory>] [--json]
prowl create pane <pane> --direction <right|left|up|down> [--json]
prowl create pane --pane <pane> --direction <right|left|up|down> [--json]
```

`create tab` requires exactly one positional worktree reference or `--worktree`. `--pane`,
`--tab`, and a positional-plus-flag combination fail before transport with `INVALID_ARGUMENT`.
`--path` is normalized by the CLI and must be the resolved worktree root or a subdirectory
of it. A path outside the worktree fails with `PATH_NOT_ALLOWED`.

`create pane` requires exactly one pane UUID or current-process `pN` handle, positionally or
through `--pane`, plus an explicit direction. It rejects `--target`, `--worktree`, `--tab`,
bare numeric handles, `--path`, and positional-plus-flag targeting. Public `up` maps to the
terminal layer's internal top direction. The operation resolves the anchor directly; it never
focuses a different pane as an intermediate targeting step.

The new pane inherits the anchor's working directory and split surface configuration. On
success it becomes the focused pane in the anchor tab, following normal tab-local focus behavior.

## Success: tab

```json
{
  "ok": true,
  "command": "create",
  "schema_version": "prowl.cli.create.v1",
  "data": {
    "resource": "tab",
    "target": {
      "worktree": { "id": "…", "name": "App", "path": "/…", "root_path": "/…", "kind": "git" },
      "tab": { "id": "…", "title": "zsh", "selected": true },
      "pane": { "id": "…", "title": "zsh", "cwd": "/…", "focused": true }
    }
  }
}
```

## Success: pane

```json
{
  "ok": true,
  "command": "create",
  "schema_version": "prowl.cli.create.v1",
  "data": {
    "resource": "pane",
    "anchor": {
      "worktree": { "id": "…", "name": "App", "path": "/…", "root_path": "/…", "kind": "git" },
      "tab": { "id": "…", "title": "zsh", "selected": true },
      "pane": { "id": "anchor-uuid", "title": "zsh", "cwd": "/…", "focused": true }
    },
    "direction": "right",
    "target": {
      "worktree": { "id": "…", "name": "App", "path": "/…", "root_path": "/…", "kind": "git" },
      "tab": { "id": "…", "title": "zsh", "selected": true },
      "pane": { "id": "created-uuid", "title": "zsh", "cwd": "/…", "focused": true }
    }
  }
}
```

`target` identifies the newly created resource. Pane creation additionally records the resolved
`anchor` and public `direction`. UUID fields are the automation-safe output of this command.

## Errors

`INVALID_ARGUMENT`, `TARGET_NOT_FOUND`, `TARGET_NOT_UNIQUE`, `PATH_NOT_ALLOWED`, and
`CREATE_FAILED` use the common error envelope in
[`cli-output-schema.json`](../../../ProwlCLIContracts/Resources/cli-output-schema.json).
