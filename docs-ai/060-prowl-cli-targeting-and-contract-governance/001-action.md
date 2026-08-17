# 060 — Prowl CLI Targeting and Contract Governance: Action

## Delivered

- Unified generic target references: `pN` and `tN` now work in `--target` and
  every existing positional auto-target form. Bare numbers remain worktree
  references outside typed `--pane` / `--tab` selectors, and stale prefixed
  handles never fall back to worktrees.
- Added action-first lifecycle commands:

  ```bash
  prowl create tab <worktree> [--path <directory>]
  prowl close <pN|tN|uuid> [--force]
  prowl close --pane <uuid|pN|N> [--force]
  prowl close --tab <uuid|tN|N> [--force]
  ```

  `close` has no worktree or UI-focus fallback. Its resolver returns the typed
  tab/pane resource, so `pN` and `tN` dispatch without cross-resource selector
  projection.
- Kept `tab create`, `tab close`, and `pane close` as one-release deprecated
  aliases. Help marks them `[Deprecated]`; each invocation emits a stderr
  migration warning while preserving the legacy wire command and JSON stdout.
- Added versioned `create` and `close` wire inputs, handlers, payloads, output
  rendering, error codes, schemas, parser tests, resolver tests, handler tests,
  and socket integration coverage.
- Rebased CLI documentation around `targeting.md`, action-first lifecycle
  grammar, per-command contracts, and a durable pane-creation boundary in
  [#699](https://github.com/onevcat/Prowl/issues/699).
- Replaced the non-executable Markdown schema copy with the Draft 2020-12
  `ProwlCLIContracts` bundle. `ProwlCLIIntegrationTests` validates every mock
  socket response with payload/error bytes before the CLI receives it. The
  bundle covers all 13 shipped wire commands, including deprecated aliases.

## Deliberate Boundary

`prowl create pane` remains unimplemented. [#699](https://github.com/onevcat/Prowl/issues/699)
now owns the action-first `create pane <pane> --direction <right|left|up|down>`
contract and requires a direct target-surface split primitive rather than a
focus-dependent implementation.

## Verification

Executed successfully:

```bash
make format-changed
make build-cli
make test-cli-smoke
make test-cli-integration
make check
make test
make build-app
```

Focused coverage also exercised prefixed generic resolution, stale-handle
non-fallback, lifecycle target routing, lifecycle handler behavior, parser
rejection, deprecated help/warnings, and raw socket JSON-schema validation.
