# 032.004 — Agent Detection Steady-State CPU

## Context

[003-sidebar-agent-row-resolution](003-sidebar-agent-row-resolution.md) removed the
filesystem work from `SidebarListView.activeAgentRowDisplays` and dropped process CPU from
94–134% to 29–70%. A long-running instance still burned 45–66% of a core with agents
attached, so profiling continued against the same workload.

This amendment records six fixes and, as much as the fixes themselves, the method that
found them: at each step the largest remaining cost was measured, attributed to a specific
symbol, and the fix aimed at that symbol only. Four of the six were only visible after an
earlier one had shifted the profile, and two of them turned out to be the same defect
arriving through a different field.

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
modification date. Entries not consulted in a round are pruned, which bounds a cache whose
keys would otherwise grow with every append. Matching behavior is unchanged: identical
fragments produce identical scores.

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
window is bounded to one poll.

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
enumerates that project's transcript directory. One walk per root is now retained for two
seconds and replayed for whatever panes arrive inside that window. The stored list is
unfiltered so callers keep applying their own process-start threshold, which lets panes with
unrelated start times share a single enumeration.

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

## Still open

With detection reduced by roughly a third, the SwiftUI flush is again the larger of the two
paths, and the ratio that motivated Fixes 1, 2 and 5 has not changed shape:

| under `flushTransactions` (5.74% total) | %core |
| --------------------------------------- | ----- |
| `AG::Subgraph::update`                  | 0.81% |
| `AG::Graph::propagate_dirty`            | 0.58% |
| `AG::Graph::UpdateStack::update`        | 0.41% |
| largest single app view body            | 0.30% |

Graph revalidation still outweighs every app-owned `body`, so something continues to dirty the
graph more often than user-visible state changes. The remaining emission source is not
identified: titles and `rawState` are both accounted for, and no view is slow enough to matter.
Narrowing it further needs in-app instrumentation (`Self._printChanges()` or an emission
counter), not `sample(1)`, because the profile can show that invalidation happens but not what
requested it.

A second cost sits entirely outside the SwiftUI path: `CA::Transaction::flush_as_runloop_observer`
measured 6.70% of a core here and 11.77% on a starved host. Despite the CoreAnimation symbol
names it is not layer rendering. The commit runs AppKit's display-cycle observer, which
performs constraint-based layout of the whole window:

```
CA::Transaction::commit                        4.27%
  run_commit_handlers → NSDisplayCycleFlush     4.19%
    -[NSWindow layoutIfNeeded]                  3.85%
      -[NSWindow _layoutViewTree]               3.77%
        -[NSView _layoutSubtreeWithOldSize:]    ×33 nested frames
```

The recursion is 33 `NSView` levels deep and still carries 18% of its root cost at the deepest
frame, over a window holding 32 tabs across 29 worktrees. Almost no app-owned frame appears
anywhere inside it — the cost is tree traversal, not any view's own layout. Two candidates were
ruled out by measurement: `NSProgressIndicator`, the sidebar's per-worktree spinner, at 0.01%
(12 were animating), and terminal surface rendering, which does not appear on the path.

This is most likely the same defect as the graph invalidation above rather than a second one.
An invalidation that dirties the SwiftUI graph also marks the hosting view tree as needing
layout, and the two costs then bill separately — roughly 5.7% in graph revalidation plus 3.8%
in AppKit layout, together larger than agent detection. Finding the single invalidation source
would address both; optimizing either subtree in isolation would not.

## Tests

- `AgentEntryEmissionDedupTests` — `rawState` and bookkeeping churn do not re-emit.
- `AgentEntryTitleCoalescingTests` — spinner frames coalesce, visible changes bypass the
  interval, a settled title is flushed by the next poll.
- `AgentScreenScanCacheTests` — unchanged screens are not re-scanned.
- `TranscriptFragmentCacheTests` — reuse, invalidation on append, unreadable tails are not
  cached, pruning is bounded, precomputed count and suffix.
- `AgentSessionRootScanCacheTests` — walks are shared within the window, redone after it,
  shared across differing thresholds, and kept separate per root.
- `AgentSessionFingerprintNormalizeTests` — both optimized paths reproduce the original
  formulation over a corpus and 2,000 seeded random inputs.

## Lessons

**Measure after each fix, not once at the start.** Fixes 3–6 were invisible in the original
profile; each became the top cost only after the one before it landed.

**A cheap check that proves an expensive one unnecessary beats optimizing the expensive one.**
The ESC-absence guard outperformed the hand-written ASCII scanner it was meant to support.

**Fixing one volatile field does not fix the class.** `rawState` and `paneTitle` were the
same defect. A field's presence in an equatable identity is what matters, not what it means.

**Attribute the flush before optimizing views.** 76% `AttributeGraph` internals against 13%
app view bodies said "dirtied too often", not "views too slow".

**Estimates from composition can mislead.** "15.9% → ~5%" assumed the ASCII fast path would
carry most inputs; measuring showed 79% of bytes were non-ASCII.
