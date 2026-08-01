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
Build, Pi, and Oh My Pi. This is fifteen launch runtimes over fourteen
`DetectedAgent` families because Pi and Oh My Pi intentionally share process
detection while remaining different Profile targets.

The implementation does not pretend that every CLI has the same contract.
Model, reasoning effort, unrestricted execution, and Dedicated Home controls
are rendered only when the selected launch adapter can satisfy their Prowl
semantics. The full positive/negative matrix and the source checks used to
exclude false positives are recorded in the linked research document.

## Implementation

### Capability-based runtime adapters

- Split Profile launch from side-effect-free session resume. All fifteen
  runtimes have launch adapters, while only Claude Code and Codex remain in
  the proven resume registry.
- Keyed launch metadata by `AgentProfileRuntime` so Pi and Oh My Pi preserve
  their executable, icon, availability probe, and option differences while
  still mapping to the `.pi` detection family.
- Added explicit field capabilities and per-runtime invocation rendering for
  interactive, seeded-interactive, and headless intents. Unsupported intents,
  notably Amp's seeded interactive mode, fail as typed adapter errors.
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
- Deliberately omitted Dedicated Home for Cursor, OpenCode, Kimi, Droid, Amp,
  and Grok after documentation/source inspection showed that available
  overrides relocate only part of their mutable state.

### Profile and workflow UX

- Expanded persisted runtime tokens without changing existing Claude/Codex
  encodings. OMP keeps its own icon even though live detection reports Pi.
- Made the Agent Profile editor conditional: unsupported model, reasoning,
  execution, and home controls are absent rather than present-but-ignored.
  Switching to a runtime without full home relocation clears the binding.
- Updated availability probes, toolbar/Command Palette launches, display
  metadata, and session launch identity to use the Profile runtime.
- Made Handoff's destination list explicitly derive from its current
  Claude/Codex policy, preventing generic Profile expansion from silently
  changing an independently verified workflow.

## Research and live evidence

- Captured installed versions and local `--help` contracts for all fifteen
  runtimes, consulting official documentation where behavior was ambiguous.
- Installed the previously missing Qwen Code 0.21.2 through its official
  Homebrew distribution. It launched and was detected, but no paid provider
  credential was added, so authenticated task execution is marked Best Effort.
- Launched every runtime in a disposable Prowl tab and confirmed the expected
  detection family. Cline was corrected to `cline --tui`; bare `cline` opens
  its Kanban UI and is not an agent-terminal launch.
- Performed source-level false-positive checks for partial home relocation and
  OMP's `PI_CODING_AGENT_DIR` behavior before finalizing the unsupported rows.
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
- `make test` passed with **2164 tests and zero failures**. The five emitted
  dependency-scan warnings are pre-existing package declaration warnings.
- `make check` passed.
- `make build-app` passed with zero warnings and zero errors.
- CLI sources and contracts were not changed, so the CLI-specific build,
  smoke, and socket integration gates were not required.

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
  home binding, and safe resume independently instead of relying on generic
  adapter presence.

## Delivery

- `171e6a92` — capability-based runtime adapters, Profile integration, rooted
  session layouts, and regression coverage.
- `c1b7ff0c` — runtime research, shipped matrix, agent manual, and this durable
  design/action record.
- [PR #643](https://github.com/onevcat/Prowl/pull/643) targets
  `onevcat/Prowl:main` as a non-draft pull request.
