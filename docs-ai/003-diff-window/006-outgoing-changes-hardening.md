# 003.006 — Outgoing Changes Hardening: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-07-24 |
| **Primary PRs** | #586 (base work, superseded), hardening PR TBD |
| **Related** | [005-outgoing-changes.md](005-outgoing-changes.md), `docs/components/diff-view.md` |

## Background

#586 added the Outgoing Changes view ([005-outgoing-changes.md](005-outgoing-changes.md)).
Review (4× changes-requested on `c4a5ab95`) plus a follow-up audit on a
fresh merge with `main` (branch `outgoing-changes-hardening`; focused suites
pass post-merge, `main` did not touch the diff/Git layers) confirmed four
problems worth fixing and one product-scope gap:

1. **Short-ref ambiguity (correctness).** `outgoingChangesBaseRef` builds
   `<remote>/<base>` and feeds it to `rev-parse`/`merge-base`. Git's refname
   disambiguation prefers `refs/heads/` over `refs/remotes/`, so a local
   branch literally named `upstream/main` silently wins and the diff is
   computed against the wrong base.
2. **No-PR scope gap (product).** The entry point requires a cached pull
   request with `baseRefName`; fork issue #510's core scenario — previewing
   what a PR *would* contain before opening one — errors out. Prowl is a
   general-purpose tool; "no PR yet" is the common case, not an edge.
3. **Conflated failure reasons (UX).** No matching remote, multiple matching
   remotes, and an unfetched base all collapse to `nil` → one "Fetch the
   target remote" message, which is wrong guidance for the ambiguous case.
4. **First-refocus staleness (pre-existing).** `DiffWindowManager.show`
   sets `skipNextFocusRefresh` before the `didBecomeKey` observer exists
   (new window) or when no notification will fire (already-key window), so
   the flag survives and swallows the first genuine refocus refresh. Same
   defect exists on `main` for Show Diff; it is merely more visible in
   outgoing mode where an agent commits in the background.
5. **Not keybindable (minor UX).** Show Diff has an `AppShortcuts.CommandID`
   entry; Outgoing Changes cannot be bound at all.

## Goals

- Outgoing Changes never computes a diff against a wrong base ref.
- It works without a pull request, using an explicitly labeled base, and
  falls back in a predictable, user-visible order.
- Every resolution failure states its actual reason and an actionable fix.
- The first refocus after leaving the window always refreshes (both modes).
- The action is bindable like Show Diff.
- The view is reachable from visible UI, not only menu/palette/shortcut.

### Non-goals

- **Interactive base picker.** Still deferred (as in 005): the labeled
  fallback ladder below covers branches cut from the configured base, which
  is the dominant case. A picker can later build on `remoteBranchRefs`.
- **NUL-safe `--name-status` parsing.** Special filenames (tab/quote/newline)
  break `DiffChangedFile.parseNameStatus` for Show Diff and Outgoing alike;
  fixing it only here would fork the parser. Separate follow-up for both paths.
- **Path-prefixed PR URL parsing.** PR URLs come from GitHub GraphQL and are
  always `https://host/owner/repo/pull/N`; today's parser fails safe (error,
  never a wrong diff). Accepted limitation, documented here.

## Design / Approach

**A. Typed base resolution** (`supacode/Clients/Git/GitClient.swift`,
`supacode/Clients/Git/GitClientTypes.swift`). Replace the `String?` returned
by `outgoingChangesBaseRef` with a resolution result:

```
OutgoingBaseResolution { ref: String            // fully qualified, e.g. refs/remotes/upstream/main
                         displayName: String    // upstream/main
                         source: .pullRequest | .repositorySetting | .automatic }
OutgoingBaseError: .noMatchingRemote(host, path)
                   .multipleMatchingRemotes([String])
                   .baseRefNotFetched(remote, branch)
                   .noResolvableBase
```

Verification and `merge-base` always use `resolution.ref` (fully qualified),
killing the local-branch shadowing bug. `GitOutgoingChangesComparison` keeps
the qualified ref plus `displayName` for titles/messages.

**B. Fallback ladder for the no-PR case**
(`supacode/Clients/ExternalDiff/OutgoingChangesClient.swift`,
`supacode/Features/App/Reducer/AppFeature+CommandPalette.swift`):

1. Cached PR base (current behavior) — source `.pullRequest`.
2. Per-repo `RepositorySettings.worktreeBaseRef`
   (`supacode/Features/Settings/Models/RepositorySettings.swift`) — the base
   the user told Prowl to cut worktrees from; correct by construction for
   Prowl-created worktrees. Source `.repositorySetting`.
3. `GitClient.automaticWorktreeBaseRef` (origin/HEAD → local default branch),
   the same chain worktree creation already trusts. Source `.automatic`.
4. Nothing resolves → `.noResolvableBase` with guidance.

The ladder advances only when a source is *absent*. A source that is present
but fails to resolve errors out with its own reason instead of cascading: a
stacked PR whose base `feature-a` is unfetched must never silently become a
diff against `origin/main` — that would count all of `feature-a`'s commits
as outgoing with only a label to notice it by. Explicit intent (a PR, a
configured `worktreeBaseRef`) is never silently bypassed.

Every refresh re-runs the full ladder (same code path as the mode switch),
so a PR created, retargeted, or closed while the window is open moves the
base visibly on the next refresh — decided over pinning the base for the
window's lifetime, because the view answers "what would my PR contain",
not "what was the base when I opened this window".

The window makes the guess explicit instead of hidden: title becomes
"Outgoing Changes — <branch> vs <displayName>" and the file-list header/empty
state names the source ("pull request base" / "worktree base setting" /
"default branch"). 005's "no implicit default-branch fallback" decision is
narrowed, not reversed: no *silent* fallback; a labeled one is fine.

**C. Distinct failure messages.** `OutgoingChangesClient` maps each
`OutgoingBaseError` case to its own message; only `.baseRefNotFetched`
suggests fetching, `.multipleMatchingRemotes` lists the conflicting remote
names.

**D. Focus-refresh fix** (`supacode/Features/DiffView/DiffWindowManager.swift`).
Register the `didBecomeKey` observer before `makeKeyAndOrderFront`, and set
`skipNextFocusRefresh` only when the window is not already key (i.e. only
when the show itself will emit the notification the flag is meant to
swallow). Extract the skip/refresh decision into a small pure helper so it
is unit-testable without real windows. Fixes Show Diff too.

**E. Keybinding registration** (`supacode/App/AppShortcuts.swift`). Add
`CommandID.outgoingChanges` with no default binding; wire menu + palette rows
so users can bind it.

**F. In-window mode switcher as the primary UI trigger**
(`supacode/Features/DiffView/DiffWindowContentView.swift`,
`DiffWindowManager.swift`, `DiffWindowState.swift`). The diff window gains a
toolbar segmented control — segments "Uncommitted" and "Outgoing" (plain
language over git jargon; "Outgoing" matches the command name) — bound to
`DiffComparison`. Window titles: working-tree mode keeps "Changes —
<branch>"; outgoing mode uses "Outgoing Changes — <branch> vs <display
base>", with base provenance detailed in the file-list header/empty state,
not the title. Show Diff and Outgoing Changes become two initial modes of
the same window, and the current mutual-replacement behavior of the singleton
window turns into an explicit, visible switch. Switching to Outgoing runs the
same resolution ladder (B); a failure renders the in-window error state with
the reason from C while the switcher stays usable to flip back. To support
switching from a window opened in working-tree mode, `DiffWindowManager.show`
gains an injected outgoing-comparison resolver closure instead of requiring
callers to resolve up front. Secondary trigger: add "Show Diff" and
"Outgoing Changes" rows to the worktree context menu
(`supacode/Features/Repositories/Views/WorktreeRowsView.swift`,
`rowContextMenu`), which today lacks even Show Diff.

**G. Bounded document loading**
(`supacode/Features/DiffView/DiffWindowState.swift`). `loadAllFiles` fans
out one task per changed file (two `git show` processes each) with no
concurrency bound — tolerable for typically-small working-tree diffs,
not for outgoing diffs of long-lived branches. Bound the task group to a
small fixed width for both modes.

**Tests.** Real-git regression for the `refs/heads/upstream/main` shadow
(extends `supacodeTests/GitOutgoingChangesTests.swift`); ladder tests per
source and per error case; focus-decision helper tests; existing suites stay
green (`make test`, `make check`, `make build-app`).

## Alternatives & decisions

- **Labeled fallback vs. base picker first** — ladder chosen: reuses two
  proven resolution sources, no new UI/persistence; picker remains open as a
  later layer on top of the same `OutgoingBaseResolution`.
- **Repo setting above origin/HEAD** — the setting is explicit user intent
  and matches how the worktree was actually created; origin/HEAD is only the
  hosting default.
- **Fix focus refresh here vs. separate PR** — here: the outgoing mode is
  what makes the stale window user-visible, and the fix is small and shared.
- **Keep `String` refs vs. typed resolution** — typed: the same struct
  carries qualification, display, and provenance, which B and C both need.
- **Refresh re-resolves vs. pins the base** — re-resolve (run the ladder on
  every refresh): the view answers "what would my PR contain now"; a visibly
  moving base beats a silently stale one. Decided 2026-07-24.
- **Delivery: supersede #586** — this branch (merge of #586 + `main` +
  hardening) ships as a new PR whose body maps each of the four pending
  review findings to its resolution; #586 is closed with cross-references.
  Decided 2026-07-24.
- **UI trigger placement** — in-window segmented switcher chosen over a
  second sidebar badge (an outgoing line count would add per-worktree git
  cost and row clutter) and over repurposing the PR tag (it already opens
  the checks popover, and a PR-only trigger contradicts the no-PR ladder).
  The context menu rows are a low-cost secondary path; the +/− badge tap
  keeps opening working-tree mode, now one visible click away from Outgoing.

## Implementation notes & deviations (2026-07-24)

Implemented on branch `outgoing-changes-hardening` (#586 merged with `main`,
then hardened per this plan). Deviations from the plan text:

- **Default keybinding instead of "no default binding".** `AppShortcut` has no
  unbound representation, so `outgoing_changes` ships with `⌘⌥⇧Y` — the
  option-modified sibling of Show Diff's `⌘⇧Y` — and is rebindable like any
  configurable action.
- **`incompletePullRequest` error case added.** A cached pull request whose
  `baseRefName` has not loaded yet is a present-but-unresolvable source and
  errors out (strict-ladder rule) instead of falling through.
- The live pull-request read is wired in `supacodeApp.swift` via the existing
  `SupacodeAppStoreBox` pattern (`OutgoingChangesClient.live(pullRequestInfo:)`
  reading `store.withState`), the same shape `PullRequestRefreshCoordinator`
  uses for store access outside TCA effects.

Key files: `supacode/Clients/Git/GitClient.swift` (ladder, qualified refs),
`supacode/Clients/Git/GitClientTypes.swift` (`OutgoingBaseResolution`,
`OutgoingBaseResolutionError`), `supacode/Clients/ExternalDiff/OutgoingChangesClient.swift`
(resolver factory), `supacode/Features/DiffView/DiffWindowState.swift`
(`DiffMode`, resolver refresh, bounded loads),
`supacode/Features/DiffView/DiffWindowManager.swift` (`DiffWindowFocusPolicy`,
title sync), `supacode/Features/DiffView/DiffWindowContentView.swift`
(switcher, provenance), `supacode/App/AppShortcuts.swift`,
`supacode/Features/Repositories/Views/WorktreeRowsView.swift` (context menu).
Tests: `supacodeTests/GitOutgoingChangesTests.swift` (ladder + shadow-branch
regression), `supacodeTests/DiffWindowStateTests.swift` (mode switch, resolver
refresh, failure path), `supacodeTests/DiffWindowFocusPolicyTests.swift`,
`supacodeTests/AppFeatureCommandPaletteTests.swift`.

## Amendments

(none yet)
