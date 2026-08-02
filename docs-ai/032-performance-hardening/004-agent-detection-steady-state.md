# 032.004 — Agent Detection Steady-State CPU

## Context

[003-sidebar-agent-row-resolution](003-sidebar-agent-row-resolution.md) removed the
filesystem work from `SidebarListView.activeAgentRowDisplays` and dropped process CPU from
94–134% to 29–70%. A long-running instance still burned 45–66% of a core with agents
attached, so profiling continued against the same workload.

This amendment records eight fixes and, as much as the fixes themselves, the method that
found them: at each step the largest remaining cost was measured, attributed to a specific
symbol, and the fix aimed at that symbol only. Six of the eight were only visible after an
earlier one had shifted the profile, and three of them turned out to be the same defect
arriving through a different field.

Fixes 7 and 8 were added after the first six were verified. Fix 7 addresses the invalidation
source that the original "Still open" section could not name — it was found by sampling a
several-100% spike while it was happening, rather than by profiling steady state.

Measurements come from `sample(1)` over a Debug build. Sample counts are reported as a
percentage of one core (a 20-second window at 1 ms produces roughly 15,000 samples per
thread), and inclusive subtree costs are summed from the shallowest occurrence of a symbol
in each thread so nested frames are not double counted.

**A note on load.** Several intermediate samples were taken while the host ran at load
averages of 35–49 on 12 cores, and they are not usable: every number inflates under
starvation, and one such sample showed detection *above* its pre-fix baseline. Only samples
taken below roughly one runnable process per core are quoted here. Within-sample
composition ratios stayed consistent across both regimes, which is what made the elevated
samples worth keeping as a cross-check rather than discarding outright.

## What the profile showed

With the sidebar fixed, the steady-state cost split into two paths:

| path                                     | share                |
| ---------------------------------------- | -------------------- |
| `WorktreeTerminalState.detectAgentState` | 15.9% of a core      |
| `GraphHost.flushTransactions` (SwiftUI)  | 12.9–16.1% of a core |

Under the flush, only about 13% of the subtree was app-owned view bodies; the remaining 76%
was `AttributeGraph` revalidation. That ratio is the finding: the graph was being dirtied
too often, and no view was slow. Optimizing a `body` would have bought nothing.

## Fix 1 — Emissions driven by `rawState`

`ActiveAgentEntry.rawState` is the un-stabilized per-poll detection result. It oscillates on
every 300 ms poll while an agent animates, and it is surfaced only by `prowl agents`
(`AgentsCommandHandler.swift`); no view renders it. Because emission dedup compared whole
entries, each flicker pushed a new entry into `ActiveAgentsFeature.State.entries` and re-ran
`SidebarListView.body`, which recreated every `RepositorySectionView`.

`equalsIgnoringRawState` now gates emission. Measured with `Self._printChanges()` on a
working agent: `RepositorySectionView` re-evaluations over 8 seconds went from 99 to 0.

## Fix 2 — Sidebar re-render scope

Even with emissions reduced, `SidebarListView.body` read `state.activeAgents.entries`, so
any real entry change still re-ran the entire sidebar. The `entries` read moved into a new
`SidebarActiveAgentsOverlay`, which owns the panel and its row-display computation. An
entries change now re-evaluates that overlay alone.

After both fixes `RepositorySectionView` does not appear in the profile at all (0.01–0.10%).

## Fix 3 — Re-parsing unchanged transcript tails

Session fingerprint matching dominated detection:

```
detectAgentState                    15.9%
  AgentSessionResolver.resolve      13.0%
    resolveUncached                 13.0%
      bestMatch                     11.4%
        normalize                    6.7%
        transcriptStrings            2.5%
      recentCandidates               1.6%
      tailData (file I/O)            0.01%
```

I/O at 0.01% against 11.4% of comparison work is the whole story: the tails sat in the page
cache and the cost was recomputation. Every pane re-read, re-parsed, and re-normalized the
same bytes each time its 5-second session cache expired.

`TranscriptFragmentCache` keys parsed, normalized fragments on the transcript's path and
modification date. One resolver-wide LRU retains at most 128 entries and 8 MiB of normalized
UTF-8 payload; observing a newer version removes older keys for the same path immediately.
Matching behavior is unchanged: identical fragments produce identical scores, while process
churn cannot multiply retention by the number of panes.

## Fix 4 — Normalization cost

`AgentSessionFingerprintMatcher.normalize` strips ANSI escapes, folds case, and collapses
whitespace. Component timing over 12 real transcript tails:

| component                        | cost     |
| -------------------------------- | -------- |
| grapheme split + join            | 102.5 ms |
| escape-stripping regex           | 49.9 ms  |
| lowercase                        | 10.4 ms  |
| byte scan proving no ESC present | 11.5 ms  |

**238 of 240 fragments contained no ESC byte at all**, yet the regex engine walked every one
of them to conclude nothing. A pattern anchored on ESC cannot match a string without one, so
an `utf8.contains(0x1B)` guard short-circuits it:

| implementation         | ms/round | vs original |
| ---------------------- | -------- | ----------- |
| original               | 101.6    | 1.00x       |
| + escape-absence guard | 64.1     | 1.58x       |
| + ASCII fast path      | 57.9     | 1.75x       |

The escape guard was the larger win and applies to all input. The ASCII fast path — a single
byte scan replacing Swift Regex and grapheme-level splitting — adds only 1.11x on top,
because 79% of transcript *bytes* are non-ASCII and defer to the general path. An initial
estimate of "detection 15.9% → ~5%" was too optimistic for exactly that reason.

Both paths are tested against a pristine copy of the original formulation over a hand-built
corpus and 2,000 seeded random ASCII inputs, so neither can drift from the semantics the
matcher was built on.

## Fix 5 — Animated pane titles

With detection reduced, the SwiftUI flush became the largest single cost. Three `prowl
agents` snapshots three seconds apart identified the trigger: **titles changed on 6 of 24
panes while agent status changed on none.**

```
"⠂ Read-only review of worktree and branch" → "⠐ Read-only review of worktree and branch"
"⠦ spx-h"                                   → "⠧ spx-h"
"[ . ] Action Required | spx-b"             → "[ ! ] Action Required | spx-b"
```

Agent TUIs animate a spinner glyph into the terminal title at roughly 10 Hz. `paneTitle` is
part of `ActiveAgentEntry`, so every frame failed the dedup from Fix 1, mutated `entries`,
and dirtied the graph — roughly 60 invalidations per second, none of them a state change.

This is the same defect as Fix 1 arriving through a different field. Closing one volatile
field did not close the class.

Title-only differences now emit at most once per second. Any user-visible change
(`displayState`, session, working directory) still emits immediately and carries the pending
title along, so a state transition is never delayed.

Coalescing alone would strand the final frame of a spinner that stops animating, since no
further title change would arrive to carry it. A suppressed entry is therefore retained and
flushed by the next detection poll once the interval elapses — no timer, and the stale
window is bounded to one poll. If the title returns to the value already visible before the
interval ends, the obsolete pending frame is discarded instead of being flashed later.

**Rejected:** stripping the glyphs instead. It would require maintaining a list of every
agent's spinner alphabet, and an unrecognized style would silently regress to per-frame
emission.

## Fix 6 — Directory walks repeated per pane

A 26-pane sample on a quiet machine (load average 3.93) showed where the fragment cache had
and had not helped. Normalizing by pane, because all agent panes poll at 300 ms regardless
of state:

| per pane            | before | after  |          |
| ------------------- | ------ | ------ | -------- |
| `transcriptStrings` | 0.124% | 0.000% | −100%    |
| `normalize`         | 0.335% | 0.099% | −70%     |
| `bestMatch`         | 0.569% | 0.322% | −43%     |
| `recentCandidates`  | 0.079% | 0.151% | **+92%** |
| detection total     | 0.794% | 0.676% | −15%     |

The fragment cache worked exactly as designed — `transcriptStrings` and `tailData` both hit
0.00% — but the total moved only 15% because the filesystem walk nearly doubled per pane and
swallowed the gains. The walk scales with files on disk, not pane count: this host held
5,483 transcripts totalling 3.9 GB, and that number grows as the agents work.

Panes resolve independently but overwhelmingly share roots — every agent in one project
enumerates that project's transcript directory. One walk per root is now retained for one
second and replayed for whatever panes arrive inside that window. The stored list is
unfiltered so callers keep applying their own process-start threshold, which lets panes with
unrelated start times share a single enumeration. The lifetime deliberately does not exceed
the resolver's one-second narrow retry: a medium-confidence sole-candidate confirmation must
observe a fresh directory snapshot so a newly created competing transcript can block a false
attribution.

The visit limit is part of the cache key. A walk made under a looser limit may hold entries a
stricter caller would refuse to trust, so it must not answer for one; the existing
`truncatedScansYieldNoCandidates` test caught this when the key was the root alone.

The scoring loop also recomputed `String(normalized.suffix(80))` and walked graphemes for
`normalized.count` on every fragment of every match, for text that never changes. Both now
ride along in the cached fragment. That exposed a redundant search: for a fragment of 80
characters or fewer the suffix *is* the fragment, so the second `contains` reran the first
verbatim. Those fragments now skip it.

**Rejected:** replacing `String.contains` with a UTF8 byte search. String comparison is
canonically equivalent, so byte matching would miss text differing only in NFC/NFD
composition and would silently fail to resolve those sessions — a correctness hazard for
roughly 1% of a core.

## Fix 7 — Animated tab titles rebuilding the tab bar

The six fixes above left the profile in the shape the original "Still open" section
described: graph revalidation outweighing every app-owned `body`, plus a comparable AppKit
layout cost, with no named requester for either. Steady-state sampling could not close it.

What closed it was catching the failure at full size. A long-running instance reached several
100% of a core, and a 300-second `sample(1)` taken while it was happening produced
an attribution that a 20-second steady-state window had never shown:

| main thread (300 s window, 32 tabs) | %core  |
| ----------------------------------- | ------ |
| busy (non-idle leaves)              | 82.50% |
| `GraphHost.flushTransactions`       | 47.78% |
| `CA::Transaction::commit`           | 32.33% |
| ↳ AppKit view-tree layout           | 18.96% |
| `detectAgentState`                  | 2.39%  |

Detection — the subject of Fixes 1–6 — was 2.4% against 80% for invalidation and layout.

**Root cause.** `TerminalTabItem.title` is a `var` inside `TerminalTabManager.tabs`, an array
on an `@Observable` class. Observation granularity is per-property, not per-element: writing
one element's title invalidates every view that read `tabs`. The same spinner animation
behind Fix 5 therefore had a second consumer nobody had accounted for. At roughly 10 Hz per
working pane, the tab bar rebuilt every tab 20–30 times per second, and each rebuild also
marked the hosting view tree as needing layout — which is exactly the "most likely the same
defect" hypothesis the previous section recorded, confirmed.

`updateTitle` now drops no-op writes outright and holds a changed title that arrives inside a
one-second window, newest-wins. As with Fix 5, a spinner that stops animating would strand its
final frame, so a clock-driven trailing task lands it independently of agent detection. That
independence matters for non-agent programs, whose detection schedule can go cold while a
terminal title is still pending. A sequence that returns to the visible title discards its
obsolete pending frame, and `@ObservationIgnored` on the bookkeeping keeps coalescing from
defeating itself.

**A second defect in the same view.** `TerminalTabsRowView` looked each row up with
`manager.tabs.first(where:)` *inside* a `ForEach` over that same array — 1,024 comparisons per
rebuild at 32 tabs. It now reads `tabs` once and indexes it into a dictionary. This was
harmless at the rebuild rate the tab bar was designed for and quadratic at the rate the
spinner produced.

## Fix 8 — Working-directory resolution repeated per render

[003](003-sidebar-agent-row-resolution.md) made index *construction* cheap and cached the
index against the repository set. The query side stayed hot: every lookup still normalized the
directory being asked about, and `PathPolicy.normalizeURL` is a `fileExists` check plus
`resolvingSymlinksInPath()` — one `getattrlist` per path component. The sidebar re-runs
whenever any agent's state changes, so unchanged directories were re-normalized every frame.

`WorktreeDirectoryIndexCache` now memoizes resolutions keyed by the directory as asked for. A
resolution is a pure function of that directory and the canonical index. Repository-set changes
and the one-second canonical-path revalidation both clear the memo before a lookup can reuse it,
so a symlink retarget has the same bounded stale window as the index itself. A pane can `cd`
anywhere, so the memo is capped at 256 entries rather than assumed bounded by pane count. The
overlay resolves each render batch after validating the repository signature once; CLI and
single-lookup callers retain their throwaway-index behavior.

Measured at 0.11–0.16% of a core before the fix and 1.13% in the post-fix sample — the figure
went *up* in absolute terms because the sample that produced it carried a far heavier
workload. This fix is small, and an earlier commit message overstated it by quoting a
14-millisecond window; the amended message records the real figures.

## Verification

Structural results are load-independent and hold regardless of agent count:

- `RepositorySectionView` effectively absent from the profile (0.09–0.20%), against 99
  re-evaluations per 8 seconds before Fix 1.
- Session resolution fell from 82% to 61–71% of `detectAgentState`; `normalize` from 42% to
  9–17%; `bestMatch` from 72% to 24–37%.
- `transcriptStrings` and `tailData` at 0.00–0.03%.

Three samples taken after the fixes were rebased onto v2026.7.25 bracket the absolute cost.
Per-pane figures divide by pane count, because every agent pane polls at 300 ms regardless of
state; the baseline column is a 25-pane run at load average 4.38 carrying Fixes 1–4 only.

| per pane           | baseline (load 4.4) | 26 panes (load 16.9) | change |
| ------------------ | ------------------- | -------------------- | ------ |
| `detectAgentState` | 0.368%              | 0.241%               | −34%   |
| `resolve`          | 0.286%              | 0.160%               | −44%   |
| `bestMatch`        | 0.172%              | 0.090%               | −48%   |
| `normalize`        | 0.054%              | 0.030%               | −43%   |
| `recentCandidates` | 0.110%              | 0.066%               | −40%   |

The comparison run carried four times the host load and three working agents against the
baseline's one, both of which raise detection cost, so these are lower bounds rather than
estimates. `recentCandidates` at −40% is the figure Fix 6 was written for: it had regressed
+92% per pane when the fragment cache landed, and the shared walk put it below its
pre-regression level.

**Fix 5 is not observable from outside the app.** `prowl agents` reports `tab.title` and
`pane.title` from the live `ListRuntimeSnapshot`, and the payload never exposes
`ActiveAgentEntry.paneTitle`, so CLI polling measures the spinner's source rate — confirmed at
9.8 changes/second per working pane, and ~1/second on idle and blocked panes — not the
emission rate coalescing governs. `AgentEntryTitleCoalescingTests` is the verification;
the live profile is only consistent with it, showing every app-owned view body at or below
0.30% of a core beneath a 5.74% flush.

Absolute CPU comparisons proved harder to state honestly than expected. Agent count, the
working/blocked mix, host load, and files on disk all moved between runs, and each shifts
the number independently. `scripts/measure-agent-detection-cpu.sh` records the agent mix, load
average, and per-symbol attribution together for this reason — a CPU percentage without its
workload is not a measurement.

Both measurement scripts select the sole running `Prowl Debug.app` process by default. When
several Debug builds run, `PROWL_PID` is required so a capture cannot silently target the wrong
instance. Output directories are unique per process and created with user-only permissions;
invalid numeric inputs, missing processes, and failed required sampling steps return failure
instead of leaving an apparently successful partial measurement.

## Verification of Fixes 7 and 8

Measured on a live instance after installing the fixed build, against 28 tabs with 6 agents
working and 1 blocked. A 20-second `sample(1)`, 13,138 samples at 1 ms:

| main thread                   | spike (32 tabs) | after (28 tabs) | change |
| ----------------------------- | --------------- | --------------- | ------ |
| busy (non-idle leaves)        | 82.50%          | 11.70%          | −86%   |
| `GraphHost.flushTransactions` | 47.78%          | 3.86%           | −92%   |
| `CA::Transaction::commit`     | 32.33%          | 2.09%           | −94%   |
| ↳ AppKit `_layoutViewTree`    | 18.96%          | 1.54%           | −92%   |
| `detectAgentState`            | 2.39%           | 3.82%           | —      |
| directory resolution          | —               | 1.13%           | —      |

The main thread is 88.30% idle. `detectAgentState` did not grow; it stopped being buried, and
is now the largest named main-thread cost.

Unlike Fix 5, Fix 7 **is** observable from outside the app. `prowl list` reports `tab.title`
from the live snapshot, which reads the same `tabs` array the tab bar observes. Polling it
7.9 times per second for 30 seconds across 28 tabs:

| animating tab                | changes/s |
| ---------------------------- | --------- |
| `[ . ] Action Required \| …` | 0.96      |
| `[ ! ] Action Required \| …` | 0.96      |
| `⠴ plugins-d`                | 0.93      |
| `⠹ spx-j`                    | 0.93      |
| three further panes          | 0.73      |

Every animating tab sits at or below the one-second interval, against a measured source rate
of 9.79 changes/second per working pane. Seven animating tabs produced 6.01 writes/second
where the source would have produced roughly 68. Blocked panes animate too — their
`[ . ]`/`[ ! ]` alternation was among the fastest — so a mostly-blocked roster is not a quiet
one.

Sustained process CPU, differenced from `ps -o time=` over awake time only:

| window                 | agent mix             | %core |
| ---------------------- | --------------------- | ----- |
| 25.6 min               | 6 working, 1 blocked  | 18.3% |
| 63 min (sleep-excised) | 1 working, 10 blocked | 24.5% |

**Caveats.** The comparison run carried 28 tabs against the spike's 32, and the post-fix
sample is a 20-second window against the spike's 300. Dividing CPU time by wall-clock
understates cost whenever the host sleeps — two clamshell sleeps occurred during this session
and the figures above exclude them. `scripts/capture-cpu-spike.sh` was written to catch a
recurrence unattended; across four runs it never fired, but its coverage was thin enough
(sleep, plus runs terminated early) that this is not evidence of absence.

## Still open

The invalidation source that the previous revision could not name was Fix 7, and the AppKit
layout cost fell with it — confirming that the two were one defect billed to two subsystems,
as hypothesized. What remains is smaller and differently shaped:

- `detectAgentState` at 3.82% is now the largest named main-thread cost. Fixes 3, 4 and 6
  reduced it 34–48% per pane; the remainder is the 300 ms poll cadence itself, which every
  agent pane runs regardless of state.
- A residual `flushTransactions` at 3.86% with `propagate_dirty` at 0.33%. Far below the
  ratio that motivated Fixes 1, 2, 5 and 7, and no longer the dominant path.

Neither is worth attacking without first establishing that the current cost is a problem.

## Refs

The original contributions were reviewed independently and, where needed, integrated through a
fork-owned follow-up that preserves the author's commits:

| Fix | Original PR | Fork result | Final scope |
| --- | --- | --- | --- |
| 1–2 | #647 | #654 | Raw-only emission dedup, sidebar observation isolation, and live CLI raw state |
| 3–4 | #650 | #657 | Resolver-wide bounded fragment LRU and normalization equivalence guards |
| 5 | #660 | #664 | Pane-title emission coalescing with stale-pending cancellation and full-field protection |
| 6 | #658 | #662 | Shared one-second root scans plus scoring derivation reuse |
| 7 | #649 | #656 | Clock-driven tab-title trailing delivery and one indexed tab lookup per render |
| 8 | #659 | #663 | Bounded resolution memo, symlink revalidation, and one signature check per row batch |

Related changes outside the eight numbered fixes are #646 (per-surface screen-scan memoization),
#648/#655 (the cached worktree directory index that Fix 8 extends), and #645/#653 (opt-in Debug
TCA action logging). The August review and final per-PR boundaries are recorded in
[056-performance-optimization-2026-08](../056-performance-optimization-2026-08/000-plan.md). This
measurement narrative and its two reusable scripts originate in #661 and are integrated through
#665.

## Tests

- `AgentEntryEmissionDedupTests` — `rawState` and bookkeeping churn do not re-emit.
- `AgentEntryTitleCoalescingTests` — spinner frames coalesce, visible changes bypass the
  interval, a settled title is flushed by the next poll, obsolete pending frames are discarded,
  and every non-coalesced field (including Profile attribution) still forces emission.
- `AgentScreenScanCacheTests` — unchanged screens are not re-scanned.
- `TranscriptFragmentCacheTests` — reuse, append invalidation, unreadable-tail recovery,
  entry/payload LRU bounds, superseded-key removal, and precomputed count and suffix.
- `AgentSessionRootScanCacheTests` — walks are shared within the window, redone after it,
  refreshed before sole-candidate confirmation, shared across differing thresholds, and kept
  separate per root.
- `AgentSessionFingerprintNormalizeTests` — both optimized paths reproduce the original
  formulation over a corpus and 2,000 seeded random inputs.
- `TerminalTabTitleCoalescingTests` — 16 tests: frames inside the interval never reach `tabs`,
  clock-driven trailing delivery lands the newest title, coalescing is per-tab, obsolete pending
  frames are discarded, a locked or custom title preserves its contract, and cleanup drops all
  coalescing state.
- `WorktreeDirectoryIndexTests` — the memo is proven by revoking the symlink a first lookup
  resolved through: an answer that survives that can only have been memoized. Plus
  invalidation on a repository-set change and eviction past the 256-entry cap.

`TerminalTabManager` and `WorktreeTerminalState` coalesce on separate clocks, so
`AgentEntryTitleCoalescingTests` stamps its titles through a fixture clock spaced past the tab
interval. Without it the tab layer withholds a title the entry test expects to see, and the
two mechanisms cannot be exercised independently. Whichever of the two coalescing branches
merges second needs this fixture change.

## Lessons

**Measure after each fix, not once at the start.** Fixes 3–6 were invisible in the original
profile; each became the top cost only after the one before it landed.

**A cheap check that proves an expensive one unnecessary beats optimizing the expensive one.**
The ESC-absence guard outperformed the hand-written ASCII scanner it was meant to support.

**Fixing one volatile field does not fix the class.** `rawState`, `paneTitle`, and
`TerminalTabItem.title` were one defect found three times, each through a different consumer.
A field's presence in an equatable identity — or in an observed collection — is what matters,
not what it means. After closing two of them the third was still costing 80% of a core.

**Sample the failure, not the steady state.** Six fixes of steady-state profiling could not
name the invalidation source; one 300-second sample taken *while* the spike was happening
named it immediately, at 47.78%. A cost that is intermittent is invisible in a window that
averages over its absence, which is what `scripts/capture-cpu-spike.sh` exists to avoid.

**Observation granularity is per-property, not per-element.** Mutating one element of an
`@Observable` array invalidates every reader of that array. A 10 Hz write to one tab's title
rebuilt all 32 — and a `first(where:)` lookup that was harmless at the designed rebuild rate
became quadratic at the spinner's.

**Attribute the flush before optimizing views.** 76% `AttributeGraph` internals against 13%
app view bodies said "dirtied too often", not "views too slow".

**Estimates from composition can mislead.** "15.9% → ~5%" assumed the ASCII fast path would
carry most inputs; measuring showed 79% of bytes were non-ASCII.
