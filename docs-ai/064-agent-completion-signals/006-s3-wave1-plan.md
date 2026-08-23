# 064.006 — S3 Wave 1 PR Plan

## Status

Planning and owner alignment. No implementation has started.

- Branch: `feat/agent-signal-hooks-s3a`
- Prerequisites: 063-A2, 064-S1, and 064-S2 are merged.
- Runtime baseline rechecked 2026-08-23: Claude Code 2.1.241; Codex CLI 0.149.0.
- S3 has no wave 2. Managed hooks are limited to runtimes that accept process-scoped
  flag/environment injection without global-config, dedicated-home, or project-file writes.

## S3 wave 1 PR breakdown

S3 wave 1 remains one R1 release slice, delivered as three sequential merge-safe PRs. The
slice is not complete until S3c passes its complete tier-A gate.

| PR | Runtime scope | Foundation / closure scope | Depends |
| --- | --- | --- | --- |
| **S3a** | Claude Code, Codex | Trusted launch-channel registration, native-hook ingress and payload normalization, self-check/channel lifecycle, launch-epoch integration, bundled CLI/resource locator | S2 |
| **S3b** | Copilot, Droid, Qoder | Plugin/settings adapters and fixtures on the S3a foundation | S3a |
| **S3c** | Pi, OMP, OpenCode | Extension/plugin adapters, Active Agents exact-channel badge, complete docs and tier-A live verification | S3b |

Every PR keeps `main` shippable. Partial runtime support may exist on `main` between these PRs,
but release documentation must not call S3 wave 1 complete before S3c.

## S3a objective

Make every Prowl Agent Profile launch of Claude Code or Codex automatically report supported
native runtime events into the existing S1/S2 signal bus, with honest `verified_live`
coverage and no global configuration writes.

S3a normalizes only runtime facts:

- Claude `SessionStart` -> `session-start`;
- Claude `Stop` and `StopFailure` -> `turn-ended`;
- Claude `PermissionRequest` and supported elicitation events -> `needs-input`;
- Claude `SessionEnd` -> `session-end`;
- Codex `agent-turn-complete` notify -> `turn-ended`.

A hook `turn-ended` never completes a dispatch or workflow step. S2 receipt priority and the
300 ms terminal-evidence coalescing window remain authoritative: a matching
`dispatch-complete` receipt wins; a turn edge without a receipt is `DISPATCH_INCOMPLETE`.

### Non-goals

- No Copilot, Droid, Qoder, Pi, OMP, or OpenCode adapters (S3b/S3c).
- No Gemini, Qwen, Grok, Cline, Kimi, Cursor, or Amp managed hooks.
- No Active Agents exact badge (S3c).
- No transcript/OSC producers, workflow watchdog changes, result capture, or full
  `last_assistant_message` storage.
- No public configured/degraded channel state, token persistence, cryptographic trust model,
  global config editing, or project-file writes.
- No redesign of `agents wait`, dispatch receipts, or the signal bus.

## Research findings and existing seams

### Reusable foundations

The repository already has the required downstream behavior:

- `AgentSignal.Source.hook` in
  `supacode/Domain/AgentDetection/AgentSignal.swift`;
- process generation, session freshness, evidence epochs, and per-source channels in
  `supacode/Features/Terminal/BusinessLogic/AgentObservationStore.swift`;
- exact caller attribution through socket peer PID ancestry in
  `supacode/CLIService/CLICommandContext.swift`;
- strict dispatch/evidence handling in
  `supacode/Features/Terminal/BusinessLogic/AgentDispatchStore.swift`;
- `verified_live` wait gating in `supacode/CLIService/AgentWaitCommandHandler.swift`;
- child-only launch carriers and the shared A2 launch boundary in
  `supacode/Domain/AgentProfile/AgentProfileLaunchPlan.swift` and
  `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`;
- an app-bundled CLI at `Resources/prowl-cli/prowl` in Debug and Release builds.

S3a adds producers and registration to these boundaries; it does not create a second signal
or launch path.

### Blocking implementation constraints

1. **One Profile launch epoch.** `bindAgentDispatch` currently calls
   `beginDispatchEpoch` after the Profile surface has launched. S3 registration must begin at
   the actual Profile launch boundary, so dispatch binding must adopt that epoch rather than
   minting another one and clearing early hook evidence.
2. **Early native events.** Claude `SessionStart` can reach Prowl before periodic detection has
   resolved the agent PID. A valid registered token and exact caller pane must be accepted as
   pending evidence, then bound when the first launch generation appears within the existing
   acquisition window. It must not be silently downgraded or lost.
3. **Prompt/config carriers.** `AgentProfileLaunchPlan.terminalInput` currently replaces only
   the final prompt argv value. Claude settings JSON is a non-final argument and can exceed the
   canonical PTY limit. Shell rendering must support typed argv-index -> environment-carrier
   replacement without putting hook JSON or tokens into initial input/history.
4. **Every A2 path.** Registration belongs in `WorktreeTerminalManager` so typed CLI launches
   and menu/palette compatibility launches share preparation, exact returned surface identity,
   rollback, and cleanup. Manually typing `claude` or `codex` into a shell is not covered.
5. **Fail-open observation.** A native hook must emit no stdout, make no runtime decision, use
   a bounded socket attempt, and exit successfully even when Prowl rejects or cannot receive
   the event. Hook failure may remove an optimization; it must never block or alter the agent.
6. **Codex internal work.** Codex can emit notify events for internal memories work. The
   decoder/registration must reject a cwd outside the effective launch directory, including
   `~/.codex/memories`.

## Proposed S3a design

### 1. Adapter-owned capability and deterministic base plan

Add a small `AgentSignalHookCapability`/launch-template model exposed by runtime adapters.
Claude and Codex render their own native flags before a positional prompt. The base
`AgentProfileLaunchPlan` remains deterministic and preview-safe: it contains a hook template,
covered events, absolute bundled CLI path, socket transport setup, and carrier descriptors,
but no random execution token.

Production planner callers pass an injected resource descriptor instead of having the pure
planner read the filesystem. Settings preview uses the same descriptor and redacted carrier
rendering.

Runtime-specific rendering:

- Claude: exactly one effective `--settings <json>` source with command hooks. Existing normal
  user/project/local settings continue to merge additively. If a Profile already supplies an
  explicit `--settings`, merge it only when it is safely readable/parseable; otherwise retain
  the user's launch and omit managed hooks with honest degradation.
- Codex: one structured TOML `-c notify=[...]` override containing the bundled CLI absolute
  path and hidden native-hook arguments. Never pass `--dangerously-bypass-hook-trust`.

### 2. Execution-scoped token and child-only transport

Immediately before surface creation, `WorktreeTerminalManager` generates an opaque UUID
channel token and patches only the execution copy of the launch plan:

- the surface receives opaque carrier values;
- `env(1)` copies the token and exact `PROWL_CLI_SOCKET` path into the launched agent process;
- `env -u` removes the carriers from the child environment;
- the pane shell never receives the public hook token variable, so a later manually launched
  runtime does not inherit the channel.

After exact tab/surface creation succeeds, the manager begins one Profile launch epoch and
registers `{token, surface, runtime, launch cwd, covered events, epoch}`. Surface creation
failure creates no registration. Target-resolution rollback, process replacement, and surface
close revoke it.

The token is a correctness capability, not a hostile-process secret. It never appears in CLI
arguments, prompt text, output payloads, logs, or persisted Profile/run state.

### 3. Hidden native-hook bridge over the existing signal command

Add a hidden `prowl agents _hook <runtime> <native-event>` leaf. It is bundled-internal, not a
user command or targetable API.

- Claude mode reads bounded stdin JSON.
- Codex mode reads the final bounded argv JSON payload.
- Pure decoders validate the native event, extract a bounded session/thread id and small
  event-specific detail, ignore unknown future fields, and never copy the full last assistant
  message.
- The bridge reads the token from its inherited environment and sends an internal hook context
  through the existing `agents.signal` envelope/socket route.
- Public `prowl agents signal` cannot provide hook context and remains
  `source=cooperative_cli`.
- The app validates token, exact caller pane, configured runtime/native event, launch cwd, and
  current/pending process generation before constructing `.hook(...)`.

The hook bridge uses the app-bundled CLI path, not `PATH` or `/usr/local/bin/prowl`, suppresses
all output, does not auto-launch Prowl, and has bounded connect/read/write behavior. Delivery
failure exits zero so observation cannot interfere with the runtime.

### 4. Channel verification and lifecycle

Keep registration state inside `AgentObservationStore`; do not add a parallel store.
Internally a registration may be pending, verified, or degraded, but the existing public
channel model remains:

- unverified/degraded: no `verified_live` channel is exposed, so `auto` wait may use honest
  heuristic fallback;
- verified: channel state is `verified_live` with the adapter-declared covered events;
- process replacement/surface close: registration and verified coverage are removed;
- a same-process Claude session replacement rotates signal freshness while retaining the
  launch channel, provided a valid new `SessionStart` establishes the new session;
- cooperative signals update only their own channel and never erase hook liveness.

Claude's first valid native event, normally `SessionStart`, verifies its configured hook set.
A 60-second active/non-blocked grace may record an internal degraded diagnostic; blocked
workspace trust pauses the diagnostic grace, and any later valid event recovers. This timer
never changes wait behavior by itself.

Codex has no startup notify. Transport/resource preflight is diagnostic only; the first valid
`agent-turn-complete` is the only end-to-end verification and covers only `turn-ended`.

## TDD implementation order for S3a

Logic-layer work follows strict RED -> GREEN; bridge/runtime behavior adds isolated live
verification where unit tests cannot prove third-party behavior.

### Phase 0 — freeze fixtures and transport policy

- Capture current Claude/Codex versions and help in the work note.
- Use scratch homes/directories only; never edit live user/global config.
- Add representative official native payload fixtures, including optional/unknown fields,
  malformed data, oversized strings, Codex memories cwd, and paths with spaces/non-ASCII.
- Resolve the owner decision under **Open owner decisions** before production rendering.

### Phase 1 — pure models, renderers, and decoders

RED/GREEN coverage:

- Claude settings JSON generation and native event mapping;
- existing settings collision parsing (`--settings value` / `--settings=value`);
- Codex TOML argv rendering and exact top-level `notify` collision detection;
- no hook trust bypass;
- Claude stdin and Codex final-argv decoding;
- unknown native events and malformed/oversized payloads fail closed;
- session/thread extraction, cwd validation, and last-message exclusion;
- interactive/prompt/headless argument order keeps the positional prompt final.

Primary files/tests:

- `supacode/Domain/AgentRuntime/AgentRuntimeAdapter.swift`;
- new focused shared hook model/decoder files;
- `supacodeTests/AgentRuntimeAdapterTests.swift`;
- new `AgentNativeHookPayloadTests`.

### Phase 2 — deterministic plan and generalized carriers

RED/GREEN coverage:

- typed arbitrary-argument carrier rendering in `AgentInvocation`/`AgentProfileLaunchPlan`;
- hook JSON/token/socket values absent from terminal initial input and preview;
- carrier cleanup works unchanged under zsh, bash, and fish;
- long prompt + long hook JSON remains below canonical PTY limits;
- Profile environment overrides cannot replace reserved Prowl hook variables;
- unavailable bundled CLI degrades without mutating the user's launch.

Primary files/tests:

- `supacode/Domain/AgentProfile/AgentProfileLaunchPlan.swift`;
- `supacode/Support/SupacodePaths.swift`;
- `supacodeTests/AgentProfileTests.swift`;
- `supacodeTests/AppFeatureAgentProfileTests.swift`.

### Phase 3 — launch epoch, registration, and rollback

RED/GREEN coverage:

- one launch epoch shared by hook registration and dispatch binding;
- valid early `SessionStart` queues before detector generation and binds afterward;
- first timely process generation attaches; late/replacement generation revokes;
- wrong token, pane, runtime, native event, cwd, session, or generation cannot verify;
- target-resolution rollback, split/tab failure, process replacement, and surface close clean
  registrations and pending events;
- typed CLI and menu/palette compatibility launches both register exact resulting surfaces;
- unprompted Profile launch gets hooks; manual shell launch does not.

Primary files/tests:

- `supacode/Features/Terminal/BusinessLogic/AgentObservationStore.swift`;
- `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`;
- `supacode/App/supacodeApp.swift`;
- `supacodeTests/AgentEvidenceEpochTests.swift`;
- `supacodeTests/AgentObservationTests.swift`;
- `supacodeTests/WorktreeTerminalStateAgentProfileTests.swift`;
- `supacodeTests/CLILifecycleCommandHandlerTests.swift`.

### Phase 4 — hidden CLI ingress and schema contract

RED/GREEN coverage:

- hidden parser is absent from normal help/completion;
- public `agents signal` wire/receipt behavior remains cooperative and unchanged;
- native hook input round-trips over a real framed Unix socket with kernel peer PID ancestry;
- stale/missing token and outside-pane callers fail closed in the app while the hook process
  itself stays silent and exits zero;
- bounded payload and socket deadlines; listener loss and malformed responses do not affect
  the runtime;
- hook response sources validate as `hook_claude` / `hook_codex` without exposing a token.

Primary files/tests:

- `ProwlCLI/Commands/AgentsSignalCommand.swift` plus a hidden hook command;
- `supacode/CLIService/Shared/InputModels.swift`;
- `supacode/CLIService/AgentSignalCommandHandler.swift`;
- `ProwlCLIContracts/Resources/cli-output-schema.json`;
- `ProwlCLITests/AgentsCommandParsingTests.swift`;
- `ProwlCLITests/ProwlCLIIntegrationTests.swift`;
- `supacodeTests/CLIAgentSignalCommandHandlerTests.swift`;
- `supacodeTests/CLISocketServerTests.swift`.

### Phase 5 — current docs and live acceptance

Update:

- `docs-ai/013-prowl-cli/contracts/agents-signal.md`;
- `docs/components/agent-detection.md`;
- `docs/components/cli.md`;
- `docs/components/agent-profiles.md` as needed;
- `skills/prowl-cli/SKILL.md` only where orchestration guidance changes;
- 064 plan/research/action records with verified runtime versions and behavior.

Live isolated Debug gates use a custom socket and freshly embedded CLI:

Claude:

1. Scratch existing user/project hook plus Prowl CLI settings both fire exactly once; live
   settings files remain unchanged.
2. `SessionStart` produces `verified_live` coverage.
3. `Stop` resolves generic idle wait with `source=hook_claude`.
4. A harmless permission request produces `needs-input` before user response.
5. Dispatch completion receipt still wins over the adjacent Stop hook.
6. Fresh workspace trust never creates false coverage before acceptance; a later valid event
   recovers.

Codex:

1. `agent-turn-complete` resolves with `source=hook_codex` and no trust-bypass flag.
2. Internal memories cwd is ignored.
3. The exact owner-approved notify replacement/collision policy is observed.
4. A manually launched Codex remains honestly heuristic/cooperative.

Both:

- bundled absolute CLI works with `/usr/local/bin/prowl` unavailable;
- custom socket/token survives the native hook environment;
- invalid token, listener loss, and helper failure never alter runtime behavior;
- created test resources and isolated app/socket state are removed afterward.

Repository gates:

```bash
make build-cli
make test-cli-smoke
make test-cli-integration
make check
make test
make build-app
```

## Acceptance invariants

- Only an app-issued, live launch registration plus exact caller-pane ancestry can produce
  `source=hook` / `verified_live`; `--origin` and `PROWL_PANE_ID` never can.
- Native hook signals are observation evidence only; dispatch/workflow completion remains a
  separate explicit protocol.
- One Profile launch owns one evidence epoch shared by hook registration and optional dispatch.
- No hook configuration is written to user global settings, dedicated homes, or repositories.
- Hook failure is fail-open for the runtime and fail-closed for trust/verification.
- Unverified coverage never suppresses heuristic `auto` fallback.
- The base Profile and preview remain deterministic; execution tokens are memory-only and
  surface-scoped.
- No token, user environment value, full assistant result, credential, or provider config is
  logged or persisted by Prowl.

## Open owner decisions

### 1. Codex `notify` ownership — blocking

Codex exposes one legacy `notify: array<string>` command. A CLI `-c notify=[...]` override
replaces the effective user notifier for that Prowl-launched process; it cannot append another
notifier. Native lifecycle hooks would require `--dangerously-bypass-hook-trust`, which Prowl
will not pass, and Codex exposes no reliable side-effect-free command for resolving and
chaining the complete effective notifier.

Recommended policy:

- permit Prowl's process-scoped notify override for ordinary Prowl Agent Profile launches and
  document that the user's global Codex notifier does not run in that launched session;
- if the Profile's own `extraArguments` explicitly set top-level `notify`, preserve that
  explicit Profile intent, omit Prowl's managed Codex hook, and expose no `verified_live`
  coverage;
- never inspect/rewrite the user's global Codex config and never pass hook trust bypass.

This decision must be resolved through `/grill-me` before S3a implementation.

## Residual risks

- Claude workspace trust can indefinitely delay every hook; fallback must remain honest.
- Codex legacy `notify` may be deprecated in favor of native hooks; keep its renderer/decoder
  isolated behind the adapter capability.
- Third-party payloads and flag semantics can drift. Fixture tests pin supported shapes, while
  live gates record the exact shipping versions.
- Early-event buffering and dispatch epoch adoption touch S2 correctness boundaries; focused
  lifecycle tests and full dispatch regression gates are mandatory before merge.
