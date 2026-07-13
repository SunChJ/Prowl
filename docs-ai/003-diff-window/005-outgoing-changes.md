# 003.005 — Outgoing Changes

## Context

`Show Diff` deliberately compares the working directory with `HEAD`; it cannot
review commits that the current worktree would contribute to a pull request.
Fork issue #510 requested that distinct review surface. The comparison needs a
reliable base: assuming `origin/main` is incorrect for forks, multiple remotes,
and stacked pull requests.

## Change

Fork issue #510 is implemented as a built-in `Outgoing Changes` action in the
View menu and Command Palette. `Show Diff` and the line-change badge remain
working-tree views.

- The action requires the selected worktree's cached pull request URL and base
  ref. It maps the pull request target repository to exactly one local remote,
  then resolves `<remote>/<baseRef>` and its merge base with `HEAD`.
- The file list and document contents come from `<merge-base>` and `HEAD`, which
  implements `git diff <base>...HEAD`. Staged, unstaged, and untracked files are
  deliberately excluded.
- Refreshing the window resolves a fresh base/`HEAD` comparison before loading
  files, so an advanced base or a new commit cannot leave a stale snapshot open.
- Missing PR data, an ambiguous or unfetched target remote, and no common
  ancestor produce an actionable error. There is no implicit default-branch
  fallback.
- The action always uses the built-in diff window. Configurable external tools
  continue to receive only `HEAD`-versus-working-directory snapshots.

## Alternatives & decisions

- **PR-derived base with explicit failure, not `origin/main` fallback** — chosen
  for correctness in forks and stacked branches. A base picker for worktrees
  without a PR is deferred; it needs a dedicated selection UI and persistent
  semantics rather than a hidden heuristic.
- **Reuse the built-in Diff window, not external tools** — it already renders
  per-file YiTong documents, while the external integrations have incompatible
  snapshot inputs.
- **Merge-base left tree, not the current base tip** — a base branch can advance
  after the feature branch is created. Reading `<base>:path` would disagree with
  GitHub's three-dot pull-request comparison.

## Refs

- Fork issue #510. Files: `GitClient.swift`, `OutgoingChangesClient.swift`,
  `DiffWindowState.swift`, `DiffWindowManager.swift`, `DiffWindowContentView.swift`,
  the AppFeature and Command Palette routes, and their focused tests.

## Current state

Outgoing Changes is available for a selected worktree through View and the
Command Palette. It can compare a pull request aimed at a fork upstream, an
Enterprise-style repository host, or a remote using a custom SSH port, provided
that Prowl can identify one matching local remote.

## Verification

- Focused `xcodebuild test` coverage passed 10 tests, including target-remote
  resolution, merge-base contents after the base advanced, uncommitted-file
  exclusion, refresh behavior, copied files, and AppFeature/Command Palette
  routing.
- `make test` passed 1,807 tests; `make check` and `make build-app` completed
  successfully.
- An isolated debug Prowl instance was exercised through its dedicated socket:
  open the worktree, create a tab, send and read a terminal marker, close both
  tabs, and terminate only the debug process. The menu/reducer route is covered
  by the focused tests because the CLI does not expose app menu commands.
