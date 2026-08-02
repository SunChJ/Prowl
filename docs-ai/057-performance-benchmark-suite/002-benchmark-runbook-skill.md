# 057.002 — Benchmark Runbook Skill

## Context

The suite's value depends on being run at the right moments with the right comparison,
and that judgment was living only in one conversation. Benchmark monitoring is planned to
be delegated to agents, so the workflow needed a durable, explicitly-invoked home.

## Change

Added `.claude/skills/run-benchmark/SKILL.md`: an explicit-invocation-only runbook that

- classifies the user's intent from the branch diff and their words into hot-path A/B,
  new-optimization pinning, or a release-level sweep — and always confirms the guessed
  mode with the user before running, since a run takes minutes and can switch the
  checkout;
- runs the matching layers (`make bench` A/B against the merge-base, the 057 benchmark
  pattern for new optimizations, `make test` + trailing-series + live checks for
  releases);
- judges results with fixed noise bands (±20% noise, 1.5x regression, 2x major) and uses
  the never-changing reference implementation as a host-noise canary;
- writes an append-only markdown report to
  `~/Library/Logs/Prowl/measurements/reports/` — local to the one quiet machine the
  series assumes, but persistent across sessions.

## Refs

- PR #668
