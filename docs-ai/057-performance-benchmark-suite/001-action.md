# 057 — Performance Benchmark Suite: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-02 | Independent reproduction of the #644/#652 scan benchmark, the #650/#657 normalize ratios, and the #649/#656 title-coalescing rate (0.99 changes/s live) confirmed the wave's headline claims | (scratchpad, results recorded in 000-plan) |
| 2026-08-02 | Four ratio-assertion benchmark suites plus shared measurement support added under `supacodeTests/` | PR TBD |
| 2026-08-02 | `make bench` (Release + testability, pinned arch, serial), `make measure-cpu`, `make capture-spike`, `make measure-titles` added | PR TBD |
| 2026-08-02 | `scripts/measure-title-coalescing.sh` added; verified live (animating tab 0.90/s, static tabs 0, exit 0) | PR TBD |

## Outcome & current state (as of 2026-08-02)

- `supacodeTests/BenchmarkMeasurement.swift` — serialized root suite `PerformanceBenchmarks`,
  interleaved median timing, runtime `-O` detection via an `assert` side effect, and the
  JSONL reporter (active only under `PROWL_BENCH_REPORT=1`).
- `supacodeTests/LineCountScanBenchmarks.swift`, `FingerprintNormalizeBenchmarks.swift`,
  `WorktreeDirectoryIndexBenchmarks.swift`, `SessionScoringBenchmarks.swift` — each pins a
  shipped hot path against a verbatim pre-optimization reference implementation, asserting
  output equivalence before timing.
- `make bench` runs the suite under `-configuration Release` + `ENABLE_TESTABILITY=YES`
  into `build/bench-derived-data`, appending records to
  `~/Library/Logs/Prowl/measurements/bench/bench.jsonl` keyed by git SHA.
- First optimized run (M-series, quiet host): sparse scan 115x, all-newline scan 37x,
  normalize 1.55x, warm scoring 7.3x, directory index 24x — all far above the asserted
  floors (3x / 2x / 1.3x / 3x / 2x).
- Debug `make test` runs the three C-call/I/O-bound ratios (sparse scan, index, scoring)
  and skips the two Swift-vs-Swift ratios, which assert only under `make bench`.

## Deviations from plan

- **`SWIFT_OPTIMIZATION_LEVEL=-O` override abandoned** for `make bench`: applied globally
  it broke SPM `PackageFrameworks` linking. Replaced with the Release configuration plus
  `ENABLE_TESTABILITY=YES` (already recorded in 000-plan's alternatives).
- **Two existing test files needed `#if DEBUG` guards** (`CommandIconMapTests`,
  `CLISocketServerTests`): they exercise Debug-only members (`debugAllEntries`,
  `debugFileDescriptors`) and cannot compile in a Release test build.
- **`GhosttyRuntime` gained an explicit `@MainActor`**: under Release whole-module builds,
  the test target's deserialization of the app swiftmodule lost the default-isolation
  inference for its `isolated deinit` and failed with "containing class is not isolated
  to an actor". The explicit attribute is semantically identical and serializes correctly.
- **Benchmarks must run with parallel testing disabled**: with the scheme's parallel
  clones, every benchmark executed twice (two runner processes); `make bench` passes
  `-parallel-testing-enabled NO` and pins `-destination platform=macOS,arch=$(uname -m)`.

## Open questions

- The reference `Data.reduce` reader measures ~84 ms per 2 MiB inside the Release test
  bundle against ~8.5 ms in a standalone `-O` SwiftPM binary. The ratio direction is
  unaffected, but absolute `reference*` values in the bench log are not comparable to the
  docs-ai/056 standalone baselines; `shipped*` values are close (0.73 ms vs 0.36–0.54 ms,
  which includes per-call metadata reads).
- A generic `platform=macOS` destination ran every test twice in this project (observed
  with two runner PIDs before pinning the arch and disabling parallel clones). Whether
  `make test-app` pays the same duplication for the full suite is worth checking
  separately; it is out of this entry's scope.
