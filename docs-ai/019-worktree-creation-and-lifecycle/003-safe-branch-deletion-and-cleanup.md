# 019 — Amendment: Safe Branch Deletion & Cleanup Hardening (#375, #383; follow-up #592)

## Context

Worktree deletion originally preselected "also delete the local branch" in a destructive
alert, for every worktree — including branches the user created outside Prowl and
branches with unmerged work. Separately, the cleanup that runs when worktree *creation*
fails removed/relocated directories based on loose matching, which risked touching the
wrong directory (and requested branch deletion for a branch the user may want to keep).

## Change

PR #375 (merged 2026-05-30, "Make worktree branch deletion explicit and safe"):

- The destructive delete alert became a **confirmation sheet** with an explicit
  "delete local branch" toggle; default deletion no longer preselects branch deletion.
- Prowl now tracks which worktrees it created itself
  (`@Shared(.appStorage("prowlCreatedWorktreeIDs"))`); the toggle is preselected only for
  Prowl-created worktrees when the `deleteBranchOnDeleteWorktree` setting is on.
- Branch deletion runs `git branch -d` first, protects main/default branches, and only
  offers force deletion (`git branch -D`) behind a second confirmation alert
  (`ForceDeleteBranchRequest`) when `-d` fails.
- The merged-PR `.delete` automation (#190) inherits all of this because it dispatches
  the same `deleteWorktreeConfirmed` path, additionally gated on the worktree being
  Prowl-created.

PR #383 (merged 2026-06-03, "Harden failed worktree cleanup"):

- Require an **exact `git worktree list --porcelain` path match** before removing or
  relocating a worktree directory (porcelain reports raw on-disk paths, e.g.
  `/private/tmp/...`, so comparison handles that).
- Only relocate existing worktree directories that actually contain `.git` metadata.
- Failed-creation cleanup no longer requests branch deletion at all.

## Follow-up (2026-07-16, #592): split manual preselect from automatic cleanup

The single `deleteBranchOnDeleteWorktree` setting from #375 drove two unrelated
behaviors: preselecting the manual dialog toggle (gated on Prowl-created worktrees)
and enabling branch deletion during automatic cleanup. The Prowl-created gate on the
*manual* preselect proved too subtle — the checkbox was sometimes checked, sometimes
not, with no cue in the dialog (it confused even the author). The manual path already
has three backstops (visible toggle, `git branch -d` safe delete, force-delete
confirmation), so ownership gating added little safety there. It remains essential on
the automatic paths, which run with no dialog at all.

Decisions:

- **Manual dialog**: the toggle now simply remembers the last *confirmed* choice
  (`@Shared(.appStorage("deleteBranchOnManualWorktreeDelete"))`, default off). No
  settings toggle, no Prowl-created gating. Cancel does not update the memory.
- **Automatic cleanup** (merged-PR `.delete` action and archived auto-delete expiry):
  controlled by the new explicit `deleteBranchOnAutomaticCleanup` setting (default
  off), still additionally gated on `prowlCreatedWorktreeIDs` — Prowl never silently
  deletes a branch it did not create.
- **Migration**: decode falls back from `deleteBranchOnAutomaticCleanup` to the legacy
  `deleteBranchOnDeleteWorktree` key, because an opted-in user's expressed intent
  included automatic-cleanup branch deletion (the old settings copy said the merged
  `.delete` action "follows" it); letting it silently reset to off would be a worse
  surprise than the rename. The manual memory intentionally starts fresh at off — the
  old semantics ("preselect for Prowl-created only") don't map onto "remember last
  choice". The legacy key is no longer written.

## Refs

- PRs #375, #383; follow-up PR #592 splitting the settings (2026-07-16); tests in
  `supacodeTests/GitClientRemoveWorktreeTests`, `RepositoriesFeatureTests`, and
  `SettingsFilePersistenceTests` (legacy-key migration).

## Current state

Deletion flow and `ForceDeleteBranchRequest` handling in
`supacode/Features/Repositories/Reducer/RepositoriesFeature+WorktreeLifecycle.swift`
(manual preselect + remember-on-confirm live here); sheet UI in
`supacode/Features/Repositories/Views/DeleteWorktreeConfirmationView.swift`;
`deleteLocalBranch` plus the porcelain-match/`.git`-metadata guards
(`relocateWorktreeDirectory`) in `supacode/Clients/Git/GitClient.swift`.
`prowlCreatedWorktreeIDs` is registered on creation in
`RepositoriesFeature+WorktreeCreation.swift` and consulted by the automatic-cleanup
paths in `RepositoriesFeature+CoreReducer.swift` / `+GithubIntegration.swift`.
`deleteBranchOnAutomaticCleanup` (with the legacy-key fallback) lives in
`supacode/Features/Settings/Models/GlobalSettings.swift`; the settings UI is in
`WorktreeSettingsView.swift`.
