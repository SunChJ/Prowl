# 060 — Prowl CLI Targeting and Contract Governance: Plan

| | |
| --- | --- |
| **Status** | Proposed — pending product/API alignment |
| **Anchor date** | 2026-08-16 |
| **Primary PRs** | TBD |
| **Related** | [013 — Prowl CLI](../013-prowl-cli/000-plan.md), [046 — CLI Short Handles](../046-cli-short-handles/000-plan.md), [047 — Cross-Agent Handoff](../047-cross-agent-handoff/000-plan.md), [059 — Agent Transcript Snapshots](../059-agent-transcript-snapshots/000-plan.md), [`docs/components/cli.md`](../../docs/components/cli.md) |

## Background

Prowl's local CLI began with UUID-oriented, app-side target resolution. The original
contract goals were one grammar for humans and agents, typed parsing, a stable JSON
surface, and no hidden selector precedence. The implementation retains those useful
foundations, but capability growth split the public targeting language:

- `--pane <uuid|pN|N>` and `--tab <uuid|tN|N>` accept short handles.
- `--target` and positional auto-targets accept only pane/tab UUIDs or worktree
  id/name/path; `pN` and `tN` are not recognized there.
- `prowl agents read <pN|pane-uuid>` intentionally accepts a positional `pN` so a
  caller can directly consume text `prowl agents` output, but accepts no selector flags.
- `send` and `key` also overload positional argument count: one argument is payload for
  the focused pane, while two arguments make the first an auto-target.

Consequently, a user can run `prowl agents read p12`, but must write
`prowl read --pane p12`; `prowl read p12` does not resolve the pane. Worse, a generic
`p12` is still eligible to match a worktree named `p12`. This is an avoidable mismatch
between the handle Prowl displays and the target syntax users naturally try.

This entry governs the target-language correction and the contract/documentation
rebaseline required to keep it correct as the CLI expands. It does not itself change
runtime behavior. Until implementation lands, the shipped binary and
`docs/components/cli.md` describe current behavior.

## Current State

### Command surface

The current binary exposes these executable forms:

| Area | Forms | Target behavior |
| --- | --- | --- |
| Entry and discovery | `prowl [path]`, `prowl open [path]`, `prowl list`, `prowl agents` | `open` consumes a path; discovery commands are global. |
| Pane interaction | `focus`, `read`, `send`, `key` | Shared selectors; selected forms also accept an auto-target position. |
| Semantic agent inspection | `agents read <pN|pane-uuid>` | Required explicit agent pane; no focus/worktree/tab fallback. |
| Terminal lifecycle | `tab create`, `tab close`, `pane close` | Shared selectors; close requires one explicit selector. |
| Handoff | `handoff save`, `handoff to <agent>` | Shared selectors or an auto-target positional source; absent selector means the calling pane, not UI focus. |

`--json` and `--no-color` are common leaf-command output options. `send` adds
`--no-enter`, `--no-wait`, `--capture`, and `--timeout`; `key` adds `--repeat`; `read`
adds snapshot/stability options; close adds `--force`; and handoff adds briefing and
launch options.

### Current shared selector model

| Form | Current accepted values |
| --- | --- |
| `--pane` | pane UUID, `pN`, bare `N` |
| `--tab` | tab UUID, `tN`, bare `N` |
| `--worktree` | worktree id, name, or path |
| `-t` / `--target` | pane UUID, tab UUID, or worktree id/name/path |
| Existing positional auto-targets | pane UUID, tab UUID, or worktree id/name/path |

Selectors are mutually exclusive. The current implementation rejects a positional target
combined with any selector flag. This is stricter than older contract text that said a
flag would override the positional value.

No-selector behavior is intentionally command-specific:

- `focus`, `read`, `send`, `key`, and `tab create` resolve the current UI focus.
- `tab close` and `pane close` reject an omitted selector.
- `handoff` resolves the pane that spawned the CLI process; it never guesses UI focus.
- `agents read` requires an explicit agent pane.

### How the inconsistency arose

1. **013 — v1 CLI** established `TargetSelector`, typed CLI parsing, app-owned
   resolution, UUID JSON identity, and positional/flag auto-targets.
2. **Auto-target follow-up** added target-first forms such as
   `prowl send <uuid> "text"` and `prowl read <uuid>`.
3. **046 — short handles** correctly preserved UUID JSON identity and made handles
   process-scoped and non-reusable. To preserve a worktree named with a bare number,
   it restricted *both* bare numeric handles and prefixed `pN`/`tN` to `--pane` and
   `--tab`.
4. **059 — agent snapshots** deliberately made `agents read <pN|uuid>` a narrow,
   immediate semantic-inspection command. This was locally ergonomic, but made the
   global discrepancy visible.
5. **047 handoff hardening** changed selector-plus-positional parsing from precedence to
   rejection for target isolation. The code and tests changed, but the older input
   contract still describes precedence in several places.

The important correction is not to abandon short handles or UUIDs. It is to distinguish
an unambiguous prefixed handle from an ambiguous bare number.

## Goals

- Give every command that accepts a **generic target** one shared, documented target
  language.
- Make `pN` and `tN` work wherever the existing generic auto-target language works:
  `--target`, target-first positional forms, and future generic-target commands.
- Preserve UUIDs as the stable JSON and scripting identity; short handles remain
  process-scoped interaction shorthand.
- Preserve the safety reasons for command-specific exceptions: explicit agent inspection,
  explicit close, and caller-pane handoff source resolution.
- Re-establish a complete, current, testable contract set covering the actual command
  surface and make the user manual, CLI help, and agent skill agree.
- Establish an ownership and verification workflow so later CLI growth cannot introduce
  another undocumented grammar fork.

### Non-goals

- Replacing UUIDs in JSON with handles, persisting handles, or making them valid across
  a Prowl restart.
- Adding a selector query language, title-based targeting, remote transport, streaming
  reads, or a new agent-control namespace.
- Changing `agents read` from an immediate semantic snapshot into a generic terminal
  reader.
- Changing handoff's caller-pane source rule or weakening explicit-close protections.
- Broadening this work into terminal layout, agent-session, or worktree lifecycle
  redesign.

## Proposed Targeting Model

### One lexical target reference language

For every existing or future generic auto-target position, define:

```text
GenericTarget ::= PaneUUID | TabUUID | PaneHandle | TabHandle | WorktreeRef
PaneHandle    ::= "p" PositiveInteger
TabHandle     ::= "t" PositiveInteger
WorktreeRef   ::= worktree id | name | path
```

Resolution is type-directed for prefixed handles, then preserves the current UUID and
worktree behavior:

1. `pN` resolves only as a pane handle.
2. `tN` resolves only as a tab handle.
3. A UUID tries pane, then tab.
4. Any other value resolves as a worktree id, name, or path.

A bare `N` is deliberately **not** a generic handle. It remains eligible as a worktree
reference, while typed flags retain their existing convenience:

```text
--pane <uuid|pN|N>
--tab  <uuid|tN|N>
```

The recommended compatibility policy is to reserve valid `pN` and `tN` spellings for
handles in generic contexts. A stale `pN` must fail as a stale pane handle; it must not
silently act on a worktree named `pN`. A worktree with such a name remains addressable
unambiguously as `--worktree p12`. This is a narrowly scoped behavior change that
prevents stale interactive handles from retargeting a command.

### Command grammar after the correction

The existing command shapes stay intact; only their `GenericTarget` slots expand:

```bash
prowl focus p12
prowl read p12 --last 120
prowl send p12 'git status --short'
prowl key p12 enter
printf '%s\n' 'git status --short' | prowl send --target p12
prowl handoff save p12 --brief -
prowl agents read p12
```

`prowl send p12` remains text input to the focused pane because `send` still lacks a
payload target/value boundary with one positional argument. The correct target-first
form is `prowl send p12 'text'`; stdin callers use `--target p12` or `--pane p12`.
This is an inherent and documentable arity rule, not a target-resolution exception.

`agents read` continues to accept a required pane-only positional argument and no
selector flags. It shares the same `PaneHandle` lexical definition, but remains a
semantic agent command rather than a generic terminal read.

### Resource-specific operations

The first implementation scope keeps current lifecycle command shapes:

```bash
prowl tab create --worktree MyApp --path /path/inside/MyApp
prowl tab close --tab t6 --force
prowl pane close --pane p12
```

Whether `tab create`, `tab close`, and `pane close` should additionally gain positional
target shorthand is intentionally deferred. Close commands currently require an explicit
selector as a safety posture; an explicit positional target could be safe, but it would
be a separate public-grammar expansion rather than a prerequisite for fixing handle
consistency.

## Contract and Documentation Governance

The current `docs-ai/013-prowl-cli/contracts/` directory is a living normative contract
set, but it no longer covers the whole shipped CLI or all current fields. This work must
rebaseline it in the same implementation change as the runtime behavior.

### Contract set to reconcile

1. Add a shared `targeting.md` contract that owns target syntax, handle lifetime,
   resolution order, no-target semantics, selector exclusivity, and the distinction
   between typed and generic references. Command contracts must link to it rather than
   duplicate target rules.
2. Reduce `input.md` to root command parsing and per-command argv/stdin arity. Correct
   its selector-plus-positional rule to match runtime rejection, and add the current
   `tab`, `pane`, `handoff`, and `agents read` grammar.
3. Update existing output contracts for shipped behavior:
   - `send.md`: document `--capture` and its incompatible combinations.
   - `read.md`: document `detection`, stable waiting, and all returned metadata.
   - `focus.md`, `key.md`, `list.md`, and `open.md`: reconcile fields, identifiers, and
     current error behavior against implementation tests.
4. Add contracts and schema coverage for commands that currently have only implementation
   and user-manual coverage: `agents`, `tab`, `pane`, and `handoff`. Keep the existing
   dedicated `agents-read.md` contract.
5. Update `schema.md` to enumerate every supported JSON wire response and either validate
   them in automated tests or explicitly narrow its status to a historical subset. The
   preferred outcome is complete executable schema validation.
6. Update `docs/components/cli.md` as the concise current user reference and
   `.agents/skills/prowl-cli/SKILL.md` as the safety-oriented automation guide. Both must
   use the shared target language and distinguish current-process handles from UUIDs.
7. Correct help text inconsistencies, including the `prowl agents --help` synopsis that
   currently implies a required subcommand despite `prowl agents` being valid.

### Durable ownership rule

- `ProwlCLI` ArgumentParser declarations are the executable source for command spelling
  and option inventory.
- `contracts/targeting.md` and command contracts are the normative public semantic source.
- `docs/components/cli.md` is the human-oriented reference derived from those contracts.
- The `prowl-cli` skill is an opinionated safety guide, never an independent behavior
  specification.

A new command or public flag is incomplete until all four layers have been updated and
validated together.

## Implementation Plan

### Phase 0 — Align the public policy

Confirm the prefixed-handle reservation policy, the lifecycle shorthand boundary, and
whether the current focused-pane fallback remains acceptable for non-destructive commands.
Freeze the target-language contract before changing resolver behavior.

### Phase 1 — Centralize generic handle resolution

- Extend `TargetResolver.resolveAuto` to recognize `pN` and `tN` before UUID/worktree
  resolution, using the same handle validation as typed pane/tab selectors.
- Keep typed `--pane` / `--tab` behavior unchanged, including their bare-number support.
- Keep app-side target resolution; the CLI parser continues to transport a normalized
  `TargetSelector` without inspecting live state.
- Ensure a stale prefixed handle returns a typed target-not-found error and cannot fall
  through to a worktree selector.

### Phase 2 — Prove command parity and safety

Add parser, resolver, handler, and socket integration coverage for the target matrix:

| Form | Expected target interpretation |
| --- | --- |
| `read p12`, `focus p12` | pane `p12` |
| `send p12 'text'`, `key p12 enter` | pane `p12` |
| `send --target p12` with stdin | pane `p12` |
| `handoff save p12` / `handoff to codex p12` | source pane `p12` |
| `agents read p12` | semantic snapshot of pane `p12` |
| `--pane 12`, `--tab 12` | existing typed bare-handle behavior |
| generic `12` | worktree behavior, never an inferred handle |
| stale `p12` / `t12` | target-not-found, never a worktree fallback |
| positional target + selector flag | `INVALID_ARGUMENT` |

Maintain tests for close requiring an explicit selector and for handoff's caller-pane
fallback. Add a targeted check that cross-resource close selectors retain their documented
behavior until a separately approved lifecycle grammar change.

### Phase 3 — Rebaseline contracts, manuals, and help

Land all contract changes listed above with the runtime change, update examples to use both
UUID-safe automation and short same-session handoffs, and add a checked command synopsis
or help snapshot so option changes are mechanically visible in review.

### Phase 4 — Validate the release surface

- Run focused Swift Testing suites for target resolution, command parsing, command handlers,
  and CLI integration.
- Run `make build-cli`, `make test-cli-smoke`, and `make test-cli-integration`.
- Run `make check`, `make test`, and `make build-app`.
- Manually verify one isolated Prowl session: text `list` → `pN` → generic read/send/key,
  JSON `list` → UUID automation, stale-handle failure, and explicit close behavior.
- Record actual outcomes in `001-action.md` after implementation.

## Risks and Compatibility

| Risk | Mitigation |
| --- | --- |
| Existing worktree named `p12` or `t6` changes generic auto-target behavior | Reserve prefixed forms; document `--worktree` as the unambiguous spelling and include release notes. |
| A stale handle silently reaches a different target | Do not fall back from prefixed handles; fail explicitly. |
| New CLI talks to an older running app | Resolver lives app-side, so retain the established transport/version failure guidance and ship CLI with the matching app. |
| Documentation re-drifts after this correction | Single target contract, help snapshot/check, and a four-layer completion rule for public CLI changes. |
| Over-expanding shorthand weakens destructive-command safety | Keep close selector requirements in this scope; decide positional close shorthand separately. |

## Decisions Requiring Alignment

1. **Prefixed-handle compatibility:** adopt the recommended reservation policy, or retain
   worktree fallback for `pN`/`tN` and accept stale-handle ambiguity.
2. **Lifecycle shorthand:** keep explicit selector-only close commands, or accept a
   positional target as an equally explicit future form.
3. **Focused-target defaults:** retain current convenience for non-destructive terminal
   operations, or require explicit target selection whenever the caller is outside its
   own pane.
4. **Contract enforcement:** require automated JSON-schema validation for every wire
   command now, or use narrower typed contract tests plus a future schema expansion.
5. **Compatibility communication:** treat the `pN`/`tN` reservation as a documented
   behavior correction in the next release, or introduce a deprecation/warning period.

## Definition of Done

The work is complete only when a user can learn one target grammar and accurately predict:

```bash
prowl agents read p12
prowl read p12
prowl send p12 'status'
prowl key p12 enter
prowl focus p12
```

All five address the same live pane; UUID JSON workflows remain stable; explicit close and
handoff safety rules remain deliberate exceptions; every command and flag has one current
contract; and tests make future divergence visible before release.
