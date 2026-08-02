# 055 — Agent Profile Runtimes: Action

| | |
| --- | --- |
| **Date** | 2026-08-01 |
| **Branch** | `feat/agent-profile-runtimes` |
| **Primary PR** | [#643](https://github.com/onevcat/Prowl/pull/643) |
| **Evidence** | [Runtime research and shipped matrix](research-agent-profile-runtimes.md) |

## Outcome

Agent Profiles now support every launch runtime represented by Prowl's current
agent catalog: Claude Code, Codex, Gemini CLI, Cursor Agent, Cline, OpenCode,
GitHub Copilot, Kimi Code, Factory Droid, Amp, Qoder CLI, Qwen Code, Grok
Build, Pi, and Oh My Pi. This is fifteen launch runtimes over fifteen
`DetectedAgent` families: Pi and Oh My Pi are now independent process,
heuristic, display, and session identities.

The implementation does not pretend that every CLI has the same contract.
Model, reasoning effort, execution mode, and Dedicated Home controls
are rendered only when the selected launch adapter can satisfy their Prowl
semantics. The full positive/negative matrix and the source checks used to
exclude false positives are recorded in the linked research document.

## Implementation

### Capability-based runtime adapters

- Removed native session resume from the generic adapter contract. All fifteen
  runtimes have launch adapters; Handoff obtains briefing input only from the
  live source agent or an explicit context-only choice.
- Kept launch metadata keyed by `AgentProfileRuntime`, with a one-to-one
  canonical detection mapping so Pi and Oh My Pi remain independent.
- Added explicit field capabilities and per-runtime invocation rendering for
  interactive, seeded-interactive, and headless intents. Unsupported intents,
  notably Amp's seeded interactive mode, fail as typed adapter errors.
- Replaced the one-sided unrestricted capability with adapter-declared
  execution-mode choices. Cline, Grok, and Oh My Pi render explicit guarded
  and least-restricted invocations; Droid, Amp, and Pi hide the field because
  their interactive CLIs cannot express both Prowl modes.
- Kept user Extra Arguments last-wins for ordinary options, but append managed
  home arguments after them so a bound Profile cannot be redirected away from
  the provisioned directory.

### Home relocation and session identity

- Replaced the single home-environment-variable assumption with
  `AgentProfileHomeRelocation`, which can render environment variables,
  multiple managed path arguments, reserved variable names, and a distinct
  native session/config root.
- Added verified isolation for Gemini, Cline, GitHub Copilot, Qoder CLI, Qwen
  Code, Pi, and Oh My Pi alongside the existing Claude Code and Codex support.
- Added rooted session layouts and pid-artifact lookup where those runtimes
  store native identity beneath the relocated root. Surface launch metadata
  now carries `sessionConfigRoot` independently from `dedicatedHome`.
- Added OMP's native `~/.omp/agent/sessions` marker and home-relative directory
  encoding independently from Pi's `~/.pi/agent/sessions` layout.
- Deliberately omitted Dedicated Home for Cursor, OpenCode, Kimi, Droid, Amp,
  and Grok after documentation/source inspection showed that available
  overrides relocate only part of their mutable state.

### Profile and workflow UX

- Expanded persisted runtime tokens without changing existing Claude/Codex
  encodings. OMP now reports its own `.omp` detection identity and keeps its
  icon without launch-metadata recovery.
- Made the Agent Profile editor conditional: unsupported model, reasoning,
  execution, and home controls are absent rather than present-but-ignored.
  Switching to a runtime without full home relocation clears the binding.
- Updated availability probes, toolbar/Command Palette launches, display
  metadata, and session launch identity to use the Profile runtime.
- Made Handoff's destination list explicitly derive from its current
  Claude/Codex policy, preventing generic Profile expansion from silently
  changing an independently verified workflow.

### Review follow-up: executable-probe cost

- Reproduced the review concern against the exact `ShellClient.runLogin`
  shape (`zsh -l`, source `.zshrc`, then `exec /bin/sh -c`). Across 20
  fifteen-runtime refreshes, the original 300-login-shell fan-out took 17.37s
  wall time and 51.43 CPU-seconds on the development machine. A 20-login-shell
  batched equivalent took 5.63s wall time and 1.96 CPU-seconds. Direct
  per-process energy sampling was unavailable because `powermetrics` requires
  superuser privileges; process count and CPU time establish the avoidable
  energy work without pretending to have measured watts.
- Replaced per-runtime shell tasks with one marker-delimited batch command.
  Positive answers remain final for the app session; negative answers use a
  five-minute TTL, preserving mid-session CLI installation detection without
  reloading shell startup files on every popover open. Concurrent startup and
  popover refreshes share one in-flight task.
- Kept the established Advanced-arguments trust boundary. Prowl does not parse
  every runtime's evolving flags or configuration. Unknown arguments on a
  Standard selection produce the neutral disclosure; an explicit
  Unrestricted picker selection retains its conservative warning even if a
  later last-wins Advanced flag may override the generated request. The exact
  final argv remains visible in Launch Preview.

## Research and live evidence

- Captured installed versions and local `--help` contracts for all fifteen
  runtimes, consulting official documentation where behavior was ambiguous.
- Installed the previously missing Qwen Code 0.21.2 through its official
  Homebrew distribution. It launched and was detected, but no paid provider
  credential was added, so authenticated task execution is marked Best Effort.
- Launched every runtime in a disposable Prowl tab and confirmed interactive
  startup. Cline was corrected to `cline --tui`; bare `cline` opens its Kanban
  UI and is not an agent-terminal launch.
- Performed source-level false-positive checks for partial home relocation and
  OMP's approval, session, and `PI_CODING_AGENT_DIR` behavior before finalizing
  the unsupported rows.
- Rechecked permission semantics against current help and official sources.
  Pi's default is intentionally unprompted; Cline and OMP expose inverse
  guarded flags; Grok requires independent permission and sandbox flags; Droid
  exposes a third-state autonomy scale; Amp's guarded behavior is settings-only.
- Re-ran guarded launches through `prowl`: Cline visibly disabled auto-approve,
  Grok accepted `--permission-mode default`, and OMP accepted
  `--approval-mode always-ask` and printed its native `omp --resume <id>` path.
  The installed baseline also reproduced the erroneous OMP-as-Pi identity. A
  simultaneous Debug instance could not mount Ghostty surfaces, so the fixed
  `.omp` payload is verified by production-path tests rather than claimed as a
  post-change live observation.
- Opened the latest Debug app through the native Settings UI and confirmed the
  Add Profile menu exposes all fifteen launch runtimes without creating or
  editing user Profiles.

## Test and build evidence

- Added or expanded focused tests for the complete runtime catalog, invocation
  mappings, capability gates, unsupported intents, relocation/session-root
  rendering, rooted session discovery, Pi/OMP identity, editor normalization,
  availability probes, and Handoff admission.
- The first focused TDD run failed at the expected missing runtime/capability
  assertions before implementation.
- The executable-probe review follow-up began with three expected RED tests;
  its final focused suite passed all five batching, cache, failure-degradation,
  and Advanced-argument disclosure tests.
- `make test` passed with **2154 tests and zero failures**. The five emitted
  dependency-scan warnings are pre-existing package declaration warnings.
- `make check` passed.
- `make build-app` passed with zero warnings and zero errors.
- `make build-cli` and `make test-cli-smoke` passed.
- `make test-cli-integration` passed all **64 tests**.

## Known limitations and follow-up seams

- Qwen authenticated task execution still needs a configured provider. The
  interactive launch, help contract, detection, and official configuration
  path were verified.
- Six runtimes intentionally lack full Dedicated Home, and several other
  fields remain hidden, as listed in the research matrix. Extra Arguments
  remain available for expert CLI-native customization without upgrading a
  partial flag into a stronger Prowl guarantee.
- Profile-based Handoff, cross-review, and other cross-agent orchestration are
  follow-up product waves. They can now require launch intent, optional Profile
  home binding, and explicit workflow context without relying on generic
  adapter presence or hidden source-session resume.

## Delivery

- `171e6a92` — capability-based runtime adapters, Profile integration, rooted
  session layouts, and regression coverage.
- `c1b7ff0c` — runtime research, shipped matrix, agent manual, and this durable
  design/action record.
- `cfb6ce75` — explicit guarded/least-restricted execution mappings and the
  independent Pi/OMP detection, heuristic, session, and CLI identities.
- `8e5e5876` — permission/resume research, shipped runtime matrix, user manual,
  and the durable 055.002 implementation record.
- [PR #643](https://github.com/onevcat/Prowl/pull/643) targets
  `onevcat/Prowl:main` as a non-draft pull request.
