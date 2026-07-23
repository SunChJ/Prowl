# 047.002 — Resume-Authored Semantic Handoff

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-07-18 |
| **Primary PRs** | #554 (artifact base); #603 (resume-authored handoff) |
| **Related** | [047 plan](000-plan.md), [048 runtime adapters](../048-agent-runtime-adapters/000-plan.md), [045 native-agent-session-detection](../045-native-agent-session-detection/000-plan.md), #473, `docs/components/handoff.md` |

## Context

#554 separated agent-authored semantic state in `current.md` from Prowl-generated
repository and terminal state in `context.md`. That preserves ownership, but a handoff command
could still create or archive a stale template when the outgoing agent had not manually updated it.

Prowl already attaches a pid-anchored `AgentSession` and detected launch arguments to each pane.
The runtime-adapter work in [048](../048-agent-runtime-adapters/000-plan.md) provides verified
direct-argv resume invocations for Claude Code and Codex. This amendment consumes that evidence
only at the existing handoff boundary.

## Decision

`prowl handoff save` and `prowl handoff to <agent>` now make a best-effort, source-authored
preparation request before Prowl saves generated context:

1. Require a detected Claude Code or Codex source with an attached `exact` or `high` confidence
   `AgentSession`. No cwd scan, transcript recency, screen text, or heuristic status can qualify.
2. Resume that session headlessly and **read-only** through `AgentRuntimeClient` with the target
   root as cwd. The prompt asks the source agent to reply with the complete updated `current.md`
   document — and nothing else — in a single reply, without running commands or editing files.
3. Prowl validates the reply (required semantic sections present, not the seeded template, chat
   preamble and code fences stripped) and transcribes it into `current.md`. An unusable reply or
   an error leaves the existing artifact untouched.
4. Record `preparation=completed`, `failed`, or `skipped` on the single `save` log line (or the
   `to` transition line). Prowl then performs its normal mechanical save; `to` continues with
   archive and destination launch.

One resume turn is bounded by a 2-minute timeout (`AgentRuntimeClient.resumeTimeout`); on expiry
the child process is terminated and preparation is `failed`. `--no-prepare` on `save` and `to`
skips the source turn entirely — the escape hatch for mechanical refreshes and for agents that
maintain `current.md` from inside their own session. A failed or unavailable preparation does not
fabricate prose or block the existing manual handoff workflow.

### Why reply-transcription instead of letting the agent write the file

A standard-mode headless resume usually cannot write files: `claude -p` cannot approve permission
prompts and `codex exec` may run in a read-only sandbox, so a "please edit current.md" request
would silently no-op while exiting 0. Having the agent reply with content and Prowl transcribe it
works in the default safe configuration of both CLIs, needs no permission escalation for the
resume (dangerous flags are never passed on resume, by construction), and makes
`preparation=completed` verifiable. The prose remains agent-authored; Prowl only checks shape and
writes it verbatim.

## Launch configuration

Argv observation drives the resume model and the receiving start:

- An explicit source `--model` remains only with the same adapter: it is reused for the source's
  own preparation resume, and never passed across vendors on `handoff to`.
- An explicitly observed unrestricted source mode maps between the two verified adapters for the
  **destination launch only**: Codex `--dangerously-bypass-approvals-and-sandbox` (or its `--yolo`
  alias) and Claude Code `--dangerously-skip-permissions` / `--permission-mode bypassPermissions`.
  The preparation resume itself is always standard-mode.
- Absence of a flag means unknown source intent. Prowl uses the destination adapter's standard
  configuration rather than assuming a source configuration default.

The Command Palette follows the same path. It captures the selected pane's session and observation,
prepares the source when safe — showing an in-progress toolbar toast during the turn and a warning
toast if preparation fails — persists the artifact, and starts the receiving tab through the
adapter rather than a hard-coded shell line.

## Safety boundaries

| Condition | Result |
| --- | --- |
| No source session, ambiguous mapping, or confidence below `high` | Skip automatic preparation; preserve the normal save/archive/launch workflow. |
| Unsupported source or destination adapter | Skip source preparation; `handoff to` still rejects unsupported interactive launch and supports `--no-launch`. |
| `--no-prepare` | Skip the source turn; mechanical save/archive/launch only. |
| Resume command exits unsuccessfully or times out (2 min) | Mark preparation failed in `log.md`; retain existing agent prose and continue mechanical handoff. |
| Reply fails validation (empty, template echo, missing sections) | Same as failure: never overwrite `current.md` with an unusable reply. |
| Source session resumes successfully | Prowl transcribes the agent's reply verbatim into `current.md`; it never authors semantic prose itself. |
| Cross-agent handoff with source model | Omit the model. Preserve only the verified unrestricted execution intent, and only for the destination launch. |

This is an identity-safety boundary, not proof that a source conversation has stopped. Prowl does
not claim to own or fork a live agent session; it issues one headless resume request only when the
pid-anchored resolver already established a safe session identity.

## Implementation

- `AgentRuntimeAdapterRegistry` owns adapter-specific launch observation, structured start/resume
  invocation creation, and source-to-destination configuration inheritance. `AgentResumeRequest`
  carries only a same-adapter model — no execution mode — so resume invocations cannot render
  dangerous flags. Codex resume passes `--output-last-message <reply file>`; Claude Code's `-p`
  prints the final reply on stdout.
- `AgentRuntimeClient.resume` returns the reply text (preferring the reply file over stdout),
  bounded by the 2-minute timeout with child-process termination on expiry.
- `HandoffStore.preparedArtifact(fromAgentReply:)` normalizes and validates replies;
  `applyPreparationReply` transcribes them. `HandoffStore.save` takes the preparation outcome and
  records it on its single log line.
- `PaneAgentState` retains argv-derived launch observation only while the detected process PID is
  unchanged. This prevents a stale dangerous-mode flag from leaking to a later process.
- `HandoffCommandHandler` receives the resolved source session and observation, requests
  preparation (reply text) before save/archive, transcribes via the store, and passes
  `AgentStartRequest` to the composition root. `HandoffInput.prepare` carries `--no-prepare`.
- `TerminalClient` exposes selected-pane session/launch observation for the Command Palette, whose
  reducer uses the same preparation request, runtime client, and transcription path.

## Verification

- `AgentRuntimeAdapterTests` covers Codex/Claude start and resume argv (read-only resume, reply
  file, `--yolo` observation), cross-agent model isolation, same-adapter model inheritance,
  reply-file preference, direct shell execution, and the resume timeout.
- `HandoffStoreTests` covers reply validation: fence/preamble stripping, template echo and
  missing-section rejection, and transcription leaving unusable replies unapplied.
- `PaneAgentStateTests` covers PID-scoped retention of launch observation.
- `HandoffCommandHandlerTests` covers verified-source reply transcription before persistence,
  unusable-reply failure, `--no-prepare` skip, single-log-line recording, medium-confidence
  rejection, destination configuration, archive, and launch behavior.
- `AppFeatureHandoffTests` covers the Command Palette's source preparation with progress/dismiss
  toasts, reply transcription, destination argv, and preserved cross-agent execution policy.

## Alternatives and decisions

- **Do not render prose in Prowl.** The source session holds the reasoning that is absent from
  repository state and terminal excerpts. Transcribing a validated reply verbatim is mechanical
  persistence, not authorship.
- **Do not let the resume write files.** File writes require permission escalation in headless
  mode and make success unverifiable; reply-transcription works in both CLIs' default safe
  configuration. Rejected: passing `--dangerously-*` flags to the resume, or scoped allow-lists
  whose semantics differ per CLI version.
- **Do not add a second session scanner.** The existing pid-anchored resolver rejects ambiguity;
  reintroducing cwd-based matching would reintroduce sibling-pane attribution risk.
- **Do not block handoff when preparation is unavailable.** A manual, existing `current.md` is
  still valuable, and an unavailable resume path must not silently remove the documented
  `--no-launch` workflow.
- **Keep Stop hooks separate.** #473 may eventually provide a last assistant message, but that
  message is neither a safe session identity nor a structured handoff document.
