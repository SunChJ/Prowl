# `prowl workflow` Contract

## Status

Current version: `prowl.cli.workflow.v1` (docs-ai 063 B1).

`workflow` is the definitions surface of Agent Workflows: it discovers, validates, and
describes `prowl.workflow/v1` YAML files. `list` crosses the socket (the app resolves the
worktree and reads the enabled set); `validate` and `schema` are **local-only** and work with
Prowl closed. Every response uses `command: "workflow"` and one closed `data` object
discriminated by `action`. Running workflows (`run`, `status`, `done`, `cancel`) is a later
slice and is not part of this contract.

## Input

```bash
prowl workflow list [target] [--target|--worktree|--tab|--pane <selector>] [--json]
prowl workflow validate <file> [--scope bundle|user|repo] [--json]
prowl workflow schema [--json]
```

### Sources and precedence

| Scope | Directory | Notes |
| --- | --- | --- |
| `bundle` | `Prowl.app/Contents/Resources/workflows/` | ids `prowl.*` are reserved for this source; absent until the first built-in ships |
| `user` | `~/.prowl/workflows/` | |
| `repo` | `<worktree root>/.prowl/workflows/` | resolved per worktree |

Files with extension `.yaml` or `.yml` directly inside a source directory are read in
file-name order; hidden files and other extensions are ignored. A **valid** file (parses and
validates without errors) shadows valid files with the same id in lower-precedence sources
(`repo` > `user` > `bundle`) and later files in the same source. Invalid files never shadow
and are never shadowed; a file that does not parse is listed without an `id`.

### `list` worktree resolution

- No selector: the caller's own pane (socket peer ancestry → pane → worktree), then the
  focused worktree. When neither exists the response omits `worktree` and `sources.repo` and
  searches the bundle and user sources only.
- Any selector follows the 060 targeting rules (`TARGET_NOT_FOUND` / `TARGET_NOT_UNIQUE`);
  a pane or tab selector resolves to its worktree.

### `validate` scope

`--scope` decides whether a `prowl.*` id is allowed. When omitted it is inferred from the
file's directory: `~/.prowl/workflows` → `user`, any other `…/.prowl/workflows` → `repo`,
anything else → `user`. The path must be an existing file (`PATH_NOT_FOUND`; a directory is
`INVALID_ARGUMENT`).

### Bundle resolution for skills

`skill:` references are checked against the bundled skill registry resolved exactly as
`prowl skills` does (`PROWL_SKILLS_DIR`, then the executable's app bundle). When no bundle can
be resolved the reference is reported as a `skill_unchecked` **warning** and the file stays
valid; the app-side `list` always has the bundle.

## Success

### `list`

```json
{
  "ok": true,
  "command": "workflow",
  "schema_version": "prowl.cli.workflow.v1",
  "data": {
    "action": "list",
    "worktree": { "id": "…", "name": "main", "path": "/Projects/App", "root_path": "/Projects/App" },
    "sources": {
      "bundle": "/Applications/Prowl.app/Contents/Resources/workflows",
      "user": "/Users/me/.prowl/workflows",
      "repo": "/Projects/App/.prowl/workflows"
    },
    "workflows": [
      {
        "id": "review",
        "name": "Review",
        "description": "…",
        "scope": "repo",
        "path": "/Projects/App/.prowl/workflows/review.yaml",
        "enabled": true,
        "valid": true,
        "errors": 0,
        "warnings": 1,
        "shadowed": false
      }
    ]
  }
}
```

- `worktree`, `sources.bundle`, and `sources.repo` are omitted when they do not apply.
- `workflows[]` is ordered by id (winners first, then shadowed files by scope precedence
  and path); files without an id come last. `id`, `name`, and `description` are omitted when
  the file did not parse or has no description.
- `enabled` is the user's per-definition switch keyed by `<scope>/<id>` (all enabled by
  default; the Settings toggle arrives with 063 D1). A file without an id is never enabled.

### `validate`

```json
{
  "ok": true,
  "command": "workflow",
  "schema_version": "prowl.cli.workflow.v1",
  "data": {
    "action": "validate",
    "path": "/Projects/App/.prowl/workflows/review.yaml",
    "valid": true,
    "workflow": { "id": "review", "name": "Review" },
    "diagnostics": [
      { "severity": "warning", "code": "timeout_long", "message": "…", "line": 31, "column": 9 }
    ]
  }
}
```

`diagnostics[]` lists parse diagnostics first, then validation diagnostics; `line` and
`column` are 1-based and omitted when a diagnostic has no position. `workflow` is present
whenever the file parsed. Codes are stable identifiers (`unknown_key`, `undefined_role`,
`message_before_launch`, `until_verdict_literal`, `skill_unchecked`, …) and are the
contract; messages are not.

### `schema`

```json
{
  "ok": true,
  "command": "workflow",
  "schema_version": "prowl.cli.workflow.v1",
  "data": { "action": "schema", "schema": { "$schema": "https://json-schema.org/draft/2020-12/schema", "…": "…" } }
}
```

`data.schema` is the Draft 2020-12 workflow definition schema
(`ProwlCLIContracts/Resources/workflow-definition-schema.json`, `$id`
`https://prowl.onev.cat/contracts/workflow/v1/workflow-definition.json`). In text mode the
schema is printed alone, pretty-printed.

## Errors

| Code | When |
| --- | --- |
| `WORKFLOW_INVALID` | `validate` found at least one error. `details` carries the full validate payload (`action`, `path`, `valid: false`, `workflow` when parsed, `diagnostics`). Exit status 1. |
| `WORKFLOW_NOT_FOUND` | Reserved for id-addressed actions of later slices. |
| `WORKFLOW_FAILED` | `list` could not read a source directory or encode the payload. |
| `TARGET_NOT_FOUND` / `TARGET_NOT_UNIQUE` | `list` selector resolution. |
| `PATH_NOT_FOUND` / `INVALID_ARGUMENT` | `validate` path is missing or a directory; conflicting selectors on `list`. |
| `APP_NOT_RUNNING` | `list` without a reachable app. Never raised by `validate` or `schema`. |

## Verification

`ProwlCLITests/WorkflowDocumentParserTests`, `WorkflowValidatorTests`,
`WorkflowDiscoveryTests`, `WorkflowSchemaTests` (output contract + definition schema pinned
to `WorkflowJSONSchema.definitionSchemaJSON`), `WorkflowCommandParsingTests`,
`WorkflowCommandExecutorTests`, and the `workflow` cases in `ProwlCLIIntegrationTests`
(real `prowl` process for `validate`/`schema`, mock socket for `list`);
`supacodeTests/WorkflowCommandHandlerTests` for worktree resolution and the enabled set.
