# 055.002 — Execution Policy Semantics and Pi/OMP Separation

| | |
| --- | --- |
| **Status** | Implemented |
| **Date** | 2026-08-01 |
| **Primary PR** | [#643](https://github.com/onevcat/Prowl/pull/643) |
| **Related** | [Plan](000-plan.md), [runtime research](research-agent-profile-runtimes.md), `docs/components/agent-profiles.md`, `docs/components/agent-detection.md`, `docs/components/handoff.md` |

## Context

The first adapter expansion treated a missing launch-wide bypass flag as proof
that an execution-mode picker should be hidden. That test was incomplete for
runtimes whose default is already auto-approved, or whose guarded mode requires
an explicit inverse flag. It also retained the historical assumption that Pi
and Oh My Pi are one detected agent even though their executables, permission
models, UI, default homes, session directories, and resume behavior have
diverged.

Both assumptions create product bugs. A Profile labelled Standard may launch a
default-unrestricted CLI, and an OMP pane may be attributed to Pi's session
store. Future handoff and cross-agent workflows would then inherit the wrong
runtime identity and capability set.

## Verified execution-policy findings

| Runtime | Runtime default | Guarded launch | Least-restricted launch | Profile decision |
| --- | --- | --- | --- | --- |
| Cline CLI | Auto-approve enabled | `--auto-approve false` | `--auto-approve true` | Show picker; render both modes explicitly |
| Factory Droid | Tiered autonomy; headless default is read-only | Bare / autonomy levels | Full bypass exists only on `droid exec` | Hide picker for interactive Profiles |
| Amp | No approval prompts unless settings enable its permission plugin | Settings/plugin only | Bare default | Hide picker; preserve runtime configuration |
| Grok Build | Ask permissions; sandbox is independently off by default | `--permission-mode default` | `--permission-mode bypassPermissions --sandbox off` | Show picker; render both permission and sandbox intent |
| Pi | No built-in permission prompts or sandbox | Extensions/tool filtering only | Bare default | Hide picker; preserve runtime configuration |
| Oh My Pi | `tools.approvalMode: yolo` | `--approval-mode always-ask` | `--approval-mode yolo` | Show picker; render both modes explicitly |

Runtime and managed policies remain authoritative. For example, OMP per-tool
`prompt`/`deny` rules and Grok deny rules or hooks still apply after a Profile
requests the least-restricted mode. Prowl must describe the launch request, not
promise that external policy can be bypassed.

## Change

1. Replace the one-sided `supportsUnrestrictedExecution` capability with an
   execution-mode selection capability. Adapters that expose the control must
   render both `.standard` and `.unrestricted` honestly; runtimes that cannot
   represent both hide the control.
2. Add inverse guarded-mode rendering for Cline and OMP, and add Grok's verified
   permission-plus-sandbox mapping. Keep Droid, Amp, and Pi on runtime-default
   behavior with no Profile permission selector.
3. Preserve the existing runtime-change normalization boundary. Switching
   runtimes clears model, reasoning, extra argv, environment overrides, and
   execution mode; tests will specifically cover transitions from a supported
   permission control to an unsupported one.
4. Add `DetectedAgent.omp` and make `AgentProfileRuntime` map one-to-one to Pi
   and OMP. Remove executable-name and icon fallbacks that only existed to
   recover OMP identity after it had collapsed into Pi.
5. Give OMP its own process aliases, screen-state entry point, default session
   marker (`~/.omp/agent/sessions`), home-relative session-directory encoder,
   rooted account-bound session layout, display identity, handoff token, and
   tests. Pi retains only Pi's own process, home, session layout, and UI rules.
6. Split the research matrix's ambiguous `Safe Prowl resume` column into native
   resume/fork support and handoff-safe source-briefing admission. Native
   `--resume` may append to the source session; Prowl admission additionally
   requires verified source immutability, output capture, confidence gates,
   timeout behavior, and failure fallback.

## Outcome and validation

- Focused tests first failed for the missing Cline/Grok/OMP execution mappings
  and independent OMP identity, then passed after implementation. The affected
  suite covered 201 tests; a dedicated OMP home-relative session-root test was
  added after the first green pass.
- Runtime switching now resets an existing Unrestricted selection before a
  runtime without execution-mode choices is displayed. Persisted stale state is
  also normalized by the launch plan.
- Classifier, session-path, rooted-session, screen-state, Active Agents, CLI
  payload, runtime catalog, and editor tests cover `DetectedAgent.omp` as an
  independent family.
- `make test` passed 2167 tests; `make check`, `make build-app`, `make build-cli`,
  `make test-cli-smoke`, and 64 CLI integration tests all passed.
- Live Prowl panes proved that Cline's guarded launch disables auto-approve,
  Grok accepts its guarded permission mode, OMP accepts `always-ask`, and OMP
  exposes native `--resume`. The installed baseline simultaneously reproduced
  the OMP-as-Pi bug. A second Debug instance could not mount Ghostty surfaces
  while the production app remained active, so the fixed `.omp` result is
  covered end-to-end by production-path tests rather than recorded as a false
  live positive.

## Refs

- [Pi coding-agent README](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/README.md)
- [Cline CLI reference](https://docs.cline.bot/cli/cli-reference)
- [Droid CLI reference](https://docs.factory.ai/reference/cli-reference)
- [Amp Owner's Manual](https://ampcode.com/manual)
- [Grok permissions](https://docs.x.ai/build/features/permissions) and [sandbox](https://docs.x.ai/build/features/sandbox)
- [Oh My Pi approval mode](https://github.com/can1357/oh-my-pi/blob/main/docs/approval-mode.md) and [session operations](https://github.com/can1357/oh-my-pi/blob/main/docs/session-operations-export-share-fork-resume.md)
