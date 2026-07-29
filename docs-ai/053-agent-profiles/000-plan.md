# 053 — Agent Profiles: Plan

| | |
| --- | --- |
| **Status** | Planned |
| **Anchor date** | 2026-07-29 |
| **Primary PRs** | pending |
| **Related** | [047 cross-agent handoff](../047-cross-agent-handoff/000-plan.md), [048 agent runtime adapters](../048-agent-runtime-adapters/000-plan.md), [049 Agents toolbar entry](../049-agents-toolbar-entry/000-plan.md), closed prototype [#617](https://github.com/onevcat/Prowl/pull/617) |

## Background

Prowl can safely start only Claude Code and Codex today. The runtime adapter already owns
structured model and execution-mode argv, while the no-agent form of the toolbar Agents capsule
was deliberately reserved for a quick launcher. There is no persisted profile, user-facing
launcher, or account selection yet.

A closed, unmerged prototype (#617) proved that `CLAUDE_CONFIG_DIR` and `CODEX_HOME` allow two
logins to run side by side, but also exposed the important constraint: each variable relocates the
runtime's *entire* home, not only credentials. Profiles must therefore describe a complete,
explicit runtime context rather than an account-name string or a raw shell command.

## Goals

- Let users define named profiles for the two verified runtimes: Claude Code and Codex.
- Launch a selected profile as a fresh interactive agent in a new, selected tab of the current
  worktree, with no initial prompt.
- Persist an optional model, reasoning level, and explicit execution mode per profile.
- Give every profile a private runtime home, so users can keep separate CLI logins, skills,
  plugins, and runtime instruction files (`CLAUDE.md` / `AGENTS.md`) per profile.
- Make multiple same-brand accounts practical: profile-bound login/status controls and
  deterministic path routing select a preferred profile for a worktree launch.
- Keep profile identity stable so a later handoff wave can select a profile rather than a bare
  agent token.

### Non-goals

- Change the current Hand Off UI, `prowl handoff` contract, or inherited-configuration behavior.
- Put API keys, OAuth tokens, or `auth.json` contents in Prowl JSON, logs, analytics, or SwiftUI
  state; V1 uses CLI-managed authentication inside a profile runtime home.
- Accept arbitrary executable paths, shell fragments, or free-form CLI flags in a profile.
- Modify a running pane when a profile or route changes, or intercept a user manually typing
  `claude` / `codex` in an existing shell.
- Support detected-but-unverified runtimes, shared-config symlink automation, profile import/export,
  or a custom visual editor for skills and instruction files.

## Product shape

### Profiles and settings

Add an **Agents** section to Settings. It owns an ordered collection of global profiles and path
routes in `UserGlobalSettings`, not repository settings: account and agent preferences are private
to the local user and must not become repository configuration.

A profile contains a stable UUID, display name, enabled state, runtime, optional model, optional
reasoning level, and the existing explicit execution mode. V1 exposes the verified common effort
levels **Low**, **Medium**, and **High**; `nil` means the runtime default. The adapters render the
same intent differently: Claude Code uses `--effort`, while Codex uses its typed
`model_reasoning_effort` config override. `.unrestricted` remains available but is visually marked
as dangerous and requires explicit confirmation when it is saved; it is never inferred from another
profile or a source pane.

The editor also offers **Sign In**, **Refresh status**, and **Reveal Profile Files**. Sign In starts
a new terminal tab with the profile environment already attached, then runs that runtime's normal
login command. Status probes treat CLI output, not exit status, as authoritative: both CLIs can
return non-zero while signed out and Codex may report on stderr. A missing profile home is simply
“Not signed in”; it must not invoke Codex first.

### Launch and routing

When the selected pane has no detected agent and at least one enabled profile exists, the Agents
capsule becomes the launcher rather than a disabled placeholder. Its popover places the current
worktree's **Recommended** profile first, followed by all enabled profiles. Selecting one creates a
new tab in that worktree and starts the runtime interactively with no prompt. It must not inject
text into the focused shell: Prowl cannot prove that shell is idle or safe to replace.

Routes map a standardized local path prefix to a profile UUID. The longest directory-boundary match
wins; an optional per-runtime default covers unmatched repositories. Resolution is read-only and
creates no directories. A route only chooses the initial recommendation—explicitly selecting another
profile always wins. The selected profile is recorded on the new surface at launch, so later route
edits never relabel or mutate an active pane.

### Runtime home and credentials

Each profile derives its home from its UUID below Prowl's data directory, never from its display
name or a user-supplied path. Launch preparation creates the runtime's directory before spawning the
shell (Codex refuses a nonexistent `CODEX_HOME`), checks that the resolved path remains inside the
profile-home base, and applies restrictive owner-only permissions.

The home is intentionally opaque to Prowl. The relevant environment variable is added only to the
new terminal surface—`CLAUDE_CONFIG_DIR` for Claude Code or `CODEX_HOME` for Codex—so the launched
agent and its children see the selected context. Prowl does not parse, copy, or display credential
files. Users manage runtime-supported files in that home; this is where profile-specific skills,
plugins, and instruction files live. Project-owned instructions remain project-owned.

Raw API-key entry is deferred. If it is added later, it must use a Keychain reference and an
agent-only launch boundary, never a persisted value or a key placed in a long-lived terminal shell
environment.

## Implementation approach

1. Introduce a Codable `AgentProfile` domain model plus route resolver and normalization tests.
   Restrict its runtime enum to Claude Code and Codex, validate nonempty names/unique UUIDs, and
   discard routes to unavailable profiles during normalization. Extend
   `supacode/Features/Settings/Models/UserGlobalSettings.swift` and its shared key without breaking
   existing JSON that lacks the new fields.
2. Separate interactive starts from prompted starts in
   `supacode/Domain/AgentRuntime/AgentRuntimeAdapter.swift`. A structured start intent must be
   `.interactive` or `.prompt(String)`, never an empty prompt sentinel. Extend
   `AgentLaunchConfiguration` with optional reasoning effort and have each verified adapter own its
   argv/config mapping and validation.
3. Resolve a profile into one launch specification: profile UUID, typed start request, and
   environment patch. Extend `supacode/Clients/Terminal/TerminalClient.swift` and the surface
   creation path in `supacode/Features/Terminal/Models/WorktreeTerminalState.swift` so that a new
   tab receives the patch through `GhosttySurfaceView(environment:)`; do not prepend environment
   assignments to shell input. Record the launch profile per surface alongside the existing
   detection state.
4. Add a small Settings reducer/view for profile editing, status/login actions, and route editing.
   Keep file operations behind an injected profile-home dependency so tests never touch real login
   directories.
5. Extend `supacode/Features/Repositories/Views/AgentsToolbarButton.swift` and its wiring in
   `supacode/Features/Repositories/Views/WorktreeDetailView.swift`. The detected-agent state keeps
   its current Hand Off action; the no-agent state lists profiles and dispatches one profile-launch
   action through `AppFeature`.
6. After implementation, update the matching current-behavior documentation and write
   `001-action.md` with the actual PR/test evidence.

## Lessons carried forward from #617

| Finding | Profile decision |
| --- | --- |
| Per-surface environment variables isolate two CLI logins. | Apply the environment only at the new-surface launch boundary. |
| `CODEX_HOME` must exist before Codex starts. | Provision the derived home before launch or login. |
| A relocated home contains settings and skills as well as auth. | Treat a profile home as a complete context, not an auth-file holder. |
| Linking shared configuration can silently diverge when a CLI rewrites a symlink. | Do not auto-link or repair shared configuration in V1; make profile files explicit. |
| Account/path changes must not alter a live pane. | Record profile ID at surface creation; routes affect later starts only. |
| Auth status output is stream- and exit-code-sensitive. | Parse known output from both streams behind a testable client. |

## Handoff boundary

Profiles are a V1 **start** feature, matching the boundary set in 049. Their stable ID and resolved
launch specification are intentionally reusable by handoff, but V1 leaves its target list as the
existing agent list.

A later handoff integration must carry the selected profile through both paths: the HUD's injected
request and the CLI/fallback handler. Updating only
`supacode/Features/HandoffHud/Reducer/HandoffHudFeature.swift` would make the fallback silently
lose the profile because `supacode/CLIService/HandoffCommandHandler.swift` currently rebuilds an
inherited configuration. That wave should extend the structured handoff request/registry boundary;
it must not read “whatever profile is current” after the request begins.

## Verification

- Domain tests: profile normalization, UUID stability, invalid/missing routes, longest path-boundary
  routing, and no persisted secret material.
- Adapter tests in `supacodeTests/AgentRuntimeAdapterTests.swift`: no-prompt interactive argv,
  model/effort mapping, standard vs. dangerous mode, and shell quoting.
- Settings and profile-home tests: legacy decode, save/reload, owner-only derived directories,
  missing-home status, stdout/stderr/non-zero login status, and no real credential access.
- Reducer/terminal tests: no-agent launcher availability, correct worktree/cwd/environment patch,
  one new tab per selection, and stable surface profile identity after route edits.
- Manual: sign into two Claude Code or Codex profiles, launch each side by side, and confirm each
  CLI reports its own identity; then change a route and confirm only a later launch changes.

## Alternatives and decisions

- **Profile homes over raw credentials.** This preserves the CLI's supported authentication flow and
  avoids turning Prowl into a secret manager. Keychain-backed API keys need a different, carefully
  scoped execution design.
- **New tab over current-shell injection.** It protects in-progress shell work and gives the agent a
  coherent environment from process start.
- **Profile routes over per-repository persisted account names.** A global, longest-prefix resolver
  gives automatic work/personal selection without leaking local identities into repository config.
- **No automatic shared-config symlinks.** The convenience is real, but the ambiguity and silent
  divergence observed in #617 make it the wrong V1 default.
- **Handoff follow-up rather than partial integration.** A profile-aware handoff must be correct in
  both normal and fallback execution paths; postponing it is safer than making the two disagree.

## Amendments
