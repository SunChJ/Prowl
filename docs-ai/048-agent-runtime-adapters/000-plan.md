# 048 — Agent Runtime Adapters: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-07-18 |
| **Primary PRs** | #603 |
| **Related** | [045 native-agent-session-detection](../045-native-agent-session-detection/000-plan.md), [047 cross-agent-handoff](../047-cross-agent-handoff/000-plan.md), #473 |

## Background

Prowl currently detects agent identity through `DetectedAgent`, resolves a native session through
`AgentSessionProfile`, and retains that session in `PaneAgentState`. Those are observation-only
layers. `AgentSessionProfile` is a static path-parser registry, not a lifecycle adapter.

The handoff launch path has a second, independent list in `HandoffAgentSupport` and hard-codes an
interactive shell line in `HandoffCommandHandler.kickoff(for:)`. The composition root passes that
string as `initialInput` to `WorktreeTerminalState.createTab`. This works today for Claude Code and
Codex, but it cannot build a resume invocation, express an execution policy, safely render argv,
or evolve into a configurable launch surface.

`ProcessDetection.processArguments(pid:)` already reads a lossless argv array, but
`ForegroundProcess` keeps only a whitespace-joined `cmdline`. Consequently Prowl cannot distinguish
an explicitly requested source model or dangerous-mode flag from defaults loaded by agent config.

Installed CLI validation on 2026-07-18 established the v1 command contracts:

```bash
codex exec resume <session-id> <prompt>
claude -p --resume <session-id> <prompt>
```

Both support `--model`. Codex exposes
`--dangerously-bypass-approvals-and-sandbox`; Claude Code exposes
`--dangerously-skip-permissions`. Those two flags form the only cross-agent execution-policy
mapping in this wave.

## Goals

- Introduce one protocol-backed runtime adapter contract for agent launch observation, interactive
  session start, and headless session resume.
- Implement Codex and Claude Code adapters with direct argv construction and a testable execution
  policy model.
- Expose a stable, cancellable headless-resume operation for a native `AgentSession`; reject
  unresolved and `medium`-confidence sessions.
- When `handoff save` or `handoff to` has a safe native source session, resume
  the source agent headlessly to author `current.md` before Prowl captures and
  archives generated state.
- Replace handoff's hard-coded `claude "…"` / `codex "…"` command generation with the adapter
  contract, including safe shell rendering for a newly created terminal tab.
- Preserve an explicitly observed unrestricted source mode across Codex ↔ Claude handoff. Keep the
  target model explicit or same-adapter inherited; never pretend model identifiers are portable
  across vendors.
- Leave a configuration boundary that a future handoff panel or repository setting can drive
  without exposing raw command strings.

### Non-goals

- Supporting start/resume for every detected agent, or inferring compatibility from an unverified
  CLI executable.
- Reading agent configuration files or claiming that the absence of a flag proves a safe default.
- Cross-vendor model-name translation, UI, persistence, or a user-facing mode selector.
- Resuming a live source process. Source-session ownership and safe handoff sequencing remain the
  responsibility of the later summary coordinator.

## Design / approach

### Catalog and adapter boundary

Keep the CLI-facing recognized-token catalog separate from runtime execution. The catalog continues
to identify every `DetectedAgent` token; `AgentRuntimeAdapterRegistry` returns an execution adapter
only for Claude Code and Codex. The registry, not `HandoffAgentSupport`, is the source of truth for
whether Prowl can start or resume an agent.

```swift
protocol AgentRuntimeAdapter: Sendable {
  var agent: DetectedAgent { get }
  func observe(arguments: [String]) -> AgentLaunchObservation
  func makeStartInvocation(_ request: AgentStartRequest) throws -> AgentInvocation
  func makeResumeInvocation(_ request: AgentResumeRequest) throws -> AgentInvocation
}
```

`AgentInvocation` is an executable plus an argv array, never a pre-quoted shell string. It has one
reviewed POSIX-shell renderer for terminal injection. `AgentRuntimeClient` executes resume
invocations directly through `ShellClient` and a login-shell PATH lookup, rather than feeding a
headless command into an interactive terminal.

### Shared runtime configuration

`AgentLaunchConfiguration` separates target-owned configuration from source observation:

- `model: String?` is an agent-specific model id. It can be inherited only when source and target
  use the same adapter; a cross-agent start uses its target default or later explicit configuration.
- `executionMode` is `.standard` or `.unrestricted`. `.unrestricted` maps to Codex
  `--dangerously-bypass-approvals-and-sandbox` and Claude Code
  `--dangerously-skip-permissions`.
- `AgentLaunchObservation` marks values as observed only when explicit argv proves them. No
  dangerous flag means `executionMode` is unknown, not `.standard`, because agent config can alter
  effective permissions.

A future UI or repository-level handoff rule supplies an explicit `AgentLaunchConfiguration`; the
runtime adapter remains responsible only for validating and rendering it.

### Detection and inheritance

Promote raw argv onto `ForegroundProcess` and parse it through the adapter during agent detection.
Store the resulting `AgentLaunchObservation` beside the session in `PaneAgentState`. Handoff uses
an explicitly observed unrestricted mode for the destination by default. Otherwise it starts the
destination with its standard adapter configuration. It never propagates a raw source command line
or a source model string to another vendor.

### Invocation flow

1. `HandoffCommandHandler` produces a handoff prompt, an agent token, and an inherited runtime
   configuration; it no longer formats a shell command.
2. The composition root resolves an adapter, builds an `AgentStartRequest`, renders its invocation,
   and gives the resulting shell line to the existing tab-creation path. Tab creation, cwd choice,
   focus, and launch-result resolution remain unchanged.
3. `HandoffCommandHandler` passes a verified source `AgentSession`, a
   handoff-authoring prompt, and the target cwd to `AgentRuntimeClient.resume`
   before saving or archiving. The client accepts only `exact` or `high`
   confidence and runs a direct argv invocation with cancellation propagation.
4. Unsupported adapters return structured errors. Existing `--no-launch` behavior stays available
   for detected agents without a runtime adapter.

## Verification

- Test adapters first: Codex and Claude start/resume argv, explicit model selection, unrestricted
  mapping, and shell quoting for whitespace, quotes, and newline-containing prompts.
- Test observation separately: explicit model/unrestricted flags are captured; absent flags remain
  unknown; enabling a dangerous flag without selecting it does not claim unrestricted execution.
- Test `AgentRuntimeClient` with a recording `ShellClient`: direct argv, cwd, exact/high admission,
  medium rejection, and propagated command failures.
- Update handoff handler and app-composition tests to prove the destination tab receives an adapter
  invocation and an observed unrestricted source maps across Codex and Claude.
- Run focused Swift tests, CLI smoke/integration tests, `make check`, and `make build-app`; manually
  verify the installed Codex and Claude versions before the later summary feature consumes resume.

## Alternatives and decisions

- **Do not extend `AgentSessionProfile`.** Session discovery is read-only evidence. Mixing command
  construction into its filesystem profiles would make every future adapter both harder to audit and
  harder to test.
- **Do not store raw shell commands.** A structured executable and argv protects prompt quoting and
  lets headless and terminal launch use the same adapter result.
- **Do not infer effective defaults.** Only explicit source argv can safely influence inheritance;
  defaults may come from user config, policy, or a changing CLI version.
- **Do not introduce a generic autonomous mode yet.** Codex sandbox/approval combinations and
  Claude permission modes are not semantically equivalent from `--help` alone. V1 supports only
  the verified unrestricted mapping; later modes require per-agent evidence and an explicit policy.

## Amendments

- 2026-07-18: [047.002](../047-cross-agent-handoff/002-resume-authored-handoff.md)
  extends the adapter foundation with source-authored handoff preparation. It
  preserves a source model only for same-adapter resumes, maps explicitly
  observed unrestricted execution across Codex and Claude Code, and records
  completion, failure, or skipped preparation in the handoff log.
- 2026-07-18 (review hardening, same PR): resume became read-only by
  construction. `AgentResumeRequest` dropped its execution mode and carries only
  a same-adapter model; the resumed agent replies with the artifact content
  (Codex `--output-last-message`, Claude Code `-p` stdout) and Prowl validates
  and transcribes it. `AgentRuntimeClient.resume` returns the reply text and is
  bounded by a 2-minute timeout with child termination. Codex `--yolo` is
  recognized as explicit unrestricted observation. Details in
  [047.002](../047-cross-agent-handoff/002-resume-authored-handoff.md).
- 2026-07-20: adapters now carry a user-facing `displayName`, and
  `AgentRuntimeAdapterRegistry.launchableAgents` is the list UI entry points derive
  handoff targets from (first consumer: the Command Palette). Scope note: the
  registry is the source of truth for launch/resume *capability*; token
  recognition stays with the CLI-shared catalog, guarded by an app-side parity
  test. See [047.003](../047-cross-agent-handoff/003-plan-calibration.md).
