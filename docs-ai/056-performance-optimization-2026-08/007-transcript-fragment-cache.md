# 056.007 — Transcript Fragment Cache and Fingerprint Normalization

## Context

Agent session resolution periodically compares visible terminal text with recent transcript
tails. Before #650, every fresh resolution reread, parsed, normalized, and filtered the same
candidate tails even when their bytes had not changed. The tails were normally already in the
filesystem page cache, so repeated JSON parsing, ANSI stripping, Unicode case folding, and
whitespace normalization dominated the matching cost rather than file I/O.

The author sampled a 20-pane instance and attributed 15.9% of one core to agent detection,
13.0% to `AgentSessionResolver.resolve`, 11.4% to fingerprint matching, and 6.7% to normalization.
The review verified the repeated computation and cache boundaries but did not independently
reproduce those exact percentages.

## Change

- #650 caches normalized, length-filtered fragments by transcript path and modification date.
  An unchanged file reuses the exact values that the matcher would otherwise recompute; an
  appended file receives a new key, and an unreadable tail is never cached as a failure.
- The fork follow-up replaces per-process fragment caches with one resolver-wide LRU. Fragment
  parsing is a pure function of transcript bytes and does not depend on the consulting process,
  agent profile, config root, candidate set, or active screen, so sharing removes duplicate tails
  across panes without changing scoring.
- The shared cache retains at most 128 transcript entries and 8 MiB of normalized UTF-8 payload.
  Both limits are independent of process-cache cleanup, so ordinary process churn cannot retain
  one multi-megabyte cache per dead process. A single entry larger than the payload budget is
  returned to the current match but not retained.
- Observing a new modification date removes older cached versions of the same path immediately,
  including when the new tail is temporarily unreadable. Entry and byte-budget pressure evict
  the least recently used value.
- Fingerprint normalization skips the ANSI regex when the input contains no ESC byte. Fully ASCII
  strings use a byte scanner for CSI removal, ASCII case folding, and whitespace collapse; any
  non-ASCII byte falls back to the original Unicode-aware formulation.

## Refs

- Original PR #650
- Fork integration PR pending
- Original implementation commits `1e8933cb` and `c97cbb4`
- Fork follow-up commit `2c2eeddf`

## Current state

The resolver result cache still controls how often each process performs a fresh match. On a
fresh match, candidates consult the shared fragment LRU, so several panes scanning the same
history reuse one normalized value instead of retaining duplicates. Cache eviction can reduce the
optimization to the pre-cache computation cost under an unusually broad, disjoint candidate set,
but it cannot alter which candidate wins.

The 8 MiB limit measures normalized UTF-8 payload plus path bytes, not total allocator RSS. The
128-entry limit separately bounds array and string-object overhead. Transcript paths normally
reside on APFS, whose modification-time precision makes same-path/same-time content collisions
impractical for the append-only transcript workflow; deliberately preserving timestamps while
rewriting content is outside this cache contract.

## Verification

- The original normalization, fragment-cache, profile, and resolver suites passed 54 tests before
  the follow-up.
- Entry-count and byte-budget tests were added first and failed to compile until the cache exposed
  bounded construction. A new-version load-failure test then failed against the first LRU draft
  until superseded versions were removed before loading.
- Tests cover unchanged-file reuse, modification-date invalidation, unreadable-tail recovery,
  immediate same-path replacement, entry-count LRU, cumulative byte-budget LRU, oversized values,
  and matcher replay after the source files disappear.
- The normalization fast path is compared with a pristine copy of the original implementation
  across a hand-built Unicode/CSI corpus, 2,000 deterministic random ASCII strings, and every
  one- and two-byte ASCII combination.
- The final four focused suites passed 59 tests with no failures or warnings.
- `make check` passed before integrating the latest `main`.
- `make build-app` completed with no errors or warnings before integrating the latest `main`.
