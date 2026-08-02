# 056.008 — Shared Session Root Scans

## Context

After transcript fragments became reusable, fresh session resolution still enumerated the same
profile roots independently for every pane. The walk scales with transcripts on disk rather than
with the current candidate set, so panes in one project repeated identical filesystem work.

The first #658 implementation retained each unfiltered `(root, visitLimit)` result for two
seconds. That crossed a correctness boundary: a medium-confidence sole candidate retries after
one second, and both confirmation passes could therefore observe the same directory snapshot
even when the new agent's own transcript appeared between them.

## Change

- `AgentSessionResolver` shares an unfiltered root walk across panes, then applies each process's
  own start-time threshold. Truncated results remain fail-closed and the visit limit is part of
  cache identity.
- Fork integration #662 reduces reuse to one second. A burst of panes still shares one walk, but
  the narrow sole-candidate confirmation pass must re-enumerate and can observe a competing
  transcript before assigning the session.
- Cached transcript fragments retain their precomputed grapheme count and distinct trailing
  80-character suffix. Shorter fragments skip a suffix lookup that would repeat the full-string
  lookup exactly; score thresholds and Unicode `String` semantics are unchanged.

## Refs

- Original PR #658
- Fork integration PR #662
- Original implementation commit `d5825e55`

## Current state

Root-walk reuse removes redundant enumeration without turning two temporal confirmation passes
into one logical observation. The optimization still leaves per-candidate path parsing and any
required header reads in place; those costs were not broadened into this change.

The root cache is actor-isolated and bounded by the per-walk visit limit plus periodic expired-key
cleanup. Up to 64 expired roots can remain allocated until a later scan triggers cleanup; this is
a small, non-blocking retention follow-up rather than a correctness risk.

## Verification

- The confirmation-boundary regression failed against the two-second cache, then passed with the
  one-second lifetime.
- The focused root-scan, fragment-cache, profile, resolver, and normalization suites passed 65
  tests after integration with current `main`.
- `make check` and `make build-app` passed for #662 with no warnings.

