# 016 — Amendment: Build/Test Time Optimization Wave (2026-08-05)

| | |
| --- | --- |
| **Status** | Planned |
| **Primary PRs** | TBD |
| **Related** | [003-ci-throughput-and-caching.md](003-ci-throughput-and-caching.md), [004-debug-identity-and-dev-loop.md](004-debug-identity-and-dev-loop.md) |

## Context

By August 2026, successful PR test jobs routinely exceeded ten minutes. The 60 successful
PR runs immediately preceding this work had these median step durations:

| Phase | Median |
| --- | ---: |
| Whole `build` job | 608 s |
| `setup-macos` | 91 s |
| `make lint` | 13 s |
| `make build-app` | 316 s |
| Parallel tests | 167 s |

Run `30919601917` (PR #677) was a high-tail sample at 866 s: setup took 122 s, the build
433 s, and tests 276 s. Test execution itself was not the dominant cost. The App test step
built the 210-file test target after the standalone App build; it then ran 2,264 tests.

The repository had also grown substantially since the first CI throughput wave:

| Snapshot | App Swift files / lines | Test Swift files / lines |
| --- | ---: | ---: |
| 2026-04-01 | 197 / 35,879 | 67 / 14,633 |
| 2026-08-05 | 419 / 85,169 | 210 / 56,768 |

## Baseline method

Use isolated, disposable DerivedData under `.build-benchmark/`, a fixed absolute path per
scenario, the existing pinned `SourcePackages`, and `-showBuildTimingSummary`. Report wall
time separately from summed task time. The core scenarios are:

1. clean App build with compilation caching disabled, to expose compiler/type-checker cost;
2. clean integrated App test, which proves both App compilation and test correctness;
3. a second clean-DerivedData run against a populated Xcode compilation CAS at the same
   path, modeling a correctly restored CI compilation cache;
4. no-change `make build-app`, modeling the local edit/build/install loop.

Initial local results on an M2 Pro / 12 logical CPUs / Xcode 26.6:

| Scenario | Wall time |
| --- | ---: |
| Clean App, no CAS | 47.7 s |
| Existing separate clean App + follow-up test | 114.8 s |
| Integrated clean App test, no CAS | 98.8 s |
| Integrated clean App test, fully warm same-path CAS | 50.9 s |

The separate-build comparison is the sum of a 47.7 s clean App build and a 67.1 s test
that reused its DerivedData. The integrated command was 14% faster locally while retaining
the same build and test coverage.

## Root causes and design decisions

### 1. The CI compilation cache is immutable but its key is effectively static

The `xcode-compilation-cache-v1` primary key includes `Package.resolved` and
`project.pbxproj`, but not the toolchain or a rotating save suffix. Ordinary Swift changes
therefore hit the same immutable `actions/cache` entry and never save newly compiled
objects. Run `30919601917` explicitly logged “primary key ... not saving cache”. The same
entry was also restored after the runner image moved from Xcode 26.5 to 26.6. That run
spent 66 s downloading/restoring a 1.90 GB CAS which could not contain compatible 26.6
compiler outputs.

The replacement key will:

- isolate exact Xcode build versions;
- use an immutable App/test source-state suffix so successful changed builds save their
  updated CAS without uploading duplicates for docs-only commits;
- restore the newest cache sharing the toolchain/project prefix;
- never fall back across Xcode build versions.

A similar rotating cache will preserve SwiftPM CLI build products. The current App build
spends about 33 s building the embedded CLI on a clean runner, and the parallel CLI tests
then contend for the same uncached `.build` directory.

### 2. CI performs two App build graphs

`make build-app` compiles the App, then `make test-app` invokes `xcodebuild test`, which
constructs another build graph to compile/link the test bundle and relink the host as
needed. A single integrated `xcodebuild test` is already a build correctness check and also
runs every App test. CI will stage the embedded CLI/docs once and use the integrated path,
while local `make build-app` remains an explicit standalone verification command.

CLI smoke and integration tests remain required. Their execution may stay parallel with
App tests when that reduces wall time without corrupting the shared SwiftPM build.

### 3. One Swift Testing assertion is a test-compilation hotspot

`-warn-long-function-bodies=500` and
`-warn-long-expression-type-checking=500` found only two App reducer bodies above 500 ms
(about 0.9 s and 0.6 s), but found a more material test hotspot:
`runStreamThrowsShellClientErrorOnNonZeroExit()` took 5.8 s to type-check, almost entirely
in two `#expect(collection.contains(where:))` macro expressions (3.1 s and 2.6 s).
Preserve the assertions while moving closure-heavy inference outside the macro expansion.
Apply the same treatment only to other measured expressions where a rerun proves a win;
do not split files or add modules based on line count alone.

## Goals

- Preserve the exact App build, all App tests, CLI smoke tests, and CLI integration tests.
- Reduce median PR wall time toward five to six minutes on `macos-26` runners.
- Improve clean and no-change local `make build-app` / `make test` time without weakening
  Debug correctness.
- Make regressions diagnosable from retained phase summaries rather than ad-hoc local logs.

## Non-goals

- GhosttyKit source build performance; CI and normal local builds use the pinned binary
  artifact/cache path.
- Test sharding that increases total compute before the single-job build graph and cache
  strategy have been exhausted.
- Full DerivedData caching; it is larger and more path-sensitive than Xcode's compilation
  CAS.
- Disabling compiler features, tests, lint rules, or signing/release checks to manufacture
  a faster result.

## Verification plan

- Repeat fixed-path local clean and warm-CAS scenarios after each material change.
- Confirm type-checker diagnostics no longer report the targeted expressions.
- Run `make check`, `make build-app`, all App tests, `make build-cli`,
  `make test-cli-smoke`, and `make test-cli-integration`.
- Push the branch and collect at least three GitHub Actions samples where practical;
  compare phase medians and cache hit/save behavior against the 60-run baseline.
- Record runner image and Xcode build identity so infrastructure changes are not mistaken
  for source regressions.
