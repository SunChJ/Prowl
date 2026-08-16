# `prowl create` Contract

## Status

Current version: `prowl.cli.create.v1`.

`create` is the action-first lifecycle namespace. V1 exposes only `create tab`;
`create pane` is reserved for [#699](https://github.com/onevcat/Prowl/issues/699).

## Input

```bash
prowl create tab <worktree> [--path <directory>] [--json]
prowl create tab --worktree <worktree> [--path <directory>] [--json]
```

Exactly one positional worktree reference or `--worktree` is required. `--pane`,
`--tab`, `--target`, and a positional-plus-flag combination fail before transport
with `INVALID_ARGUMENT`.

`--path` is normalized by the CLI and must be the resolved worktree root or a
subdirectory of it. A path outside the worktree fails with `PATH_NOT_ALLOWED`.

## Success

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

`target` identifies the newly created tab and its initial pane. Its UUID fields
are the automation-safe output of this command.

## Errors

`INVALID_ARGUMENT`, `TARGET_NOT_FOUND`, `TARGET_NOT_UNIQUE`, `PATH_NOT_ALLOWED`,
and `CREATE_FAILED` use the common error envelope in
[`schema-bundle.json`](../../../ProwlCLIContracts/Resources/cli-output-schema.json).
