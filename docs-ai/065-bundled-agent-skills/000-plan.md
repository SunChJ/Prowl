# 065 — Bundled Agent Skills: Plan

| | |
| --- | --- |
| **Status** | Planned |
| **Anchor date** | 2026-08-22 |
| **Primary PRs** | #712 (plan), K1–K3 to fill in |
| **Related** | [063-agent-workflows](../063-agent-workflows/000-plan.md) (D1 `skill:` materialization, D1–D3 new skills), [060-prowl-cli-targeting-and-contract-governance](../060-prowl-cli-targeting-and-contract-governance/000-plan.md) (four-layer CLI rule), [013-prowl-cli](../013-prowl-cli/000-plan.md), `docs/components/cli.md`, `skills/prowl-cli/SKILL.md` |

## Background

Prowl's official agent skills live only in the source tree: `skills/prowl-cli/SKILL.md`
today, with `prowl-workflows` (063-D1), a reviewer skill (063-D2), and a handoff skill
(063-D3) planned. The shipped app bundles `docs/` (`Makefile` `embed-docs` →
`Contents/Resources/docs`, read through `SupacodePaths.bundledDocsDirectoryPath`) but not
`skills/`, so a user who wants Claude Code or Codex to drive Prowl has to clone the repo or
copy the skill by hand, and nothing keeps that copy current after an app update. The
`.claude/skills/prowl-cli → ../../skills/prowl-cli` symlink in this repo is exactly the
experience users should get: one link, always the version that matches the installed app.

063 needs the same files inside the bundle to materialize `skill:` references into a run
directory, and its Settings › Workflows page wants an “ask your agent to write one” prompt
that points at bundled `docs/` + `skills/`. C0 (#709) deliberately shipped the Command Line
Tool page without an agent-help entry because the generic “Ask Agent About Prowl” prompt is
user onboarding, not agent enablement; this entry is the missing piece.

## Goals

1. **Bundle** the official skills into the app (`Contents/Resources/skills/<id>/`) with a
   registry that the app, the `prowl` CLI, and the 063 runner all read.
2. **`prowl skills`** — list, install, uninstall, path — links bundled skills into agent skill
   folders (user scope: `~/.claude/skills`, `~/.codex/skills`, `~/.agents/skills`; project
   scope: the matching folders under a repository root) so updates propagate automatically.
3. **Settings › Agents › Command Line Tool › Agent Skills** — a section on the existing
   page listing the user-facing skills with per-target install status and Install/Remove
   actions, mirroring the CLI install row above it.
4. **One locator** (`ProwlSkills`) for 063: `skill(id:)` resolves to the bundled directory so
   workflows and kickoff prompts can reference skills without any install step.

**Non-goals (V1):** managing third-party or user-authored skills (this is Prowl's own skills
only, not a general skills manager); copy mode (symlink only — see open questions); writing
into an agent's skill folder without an explicit user action (no auto-linking of new skills
after an update); editing skills in-app; Settings UI for project scope (CLI only in V1);
touching git state in the user's repositories.

## Design / Approach

**Build & bundle.** `Makefile` gains `embed-skills` (rsync `skills/` → `Resources/skills/`,
`--delete`, same shape as `embed-docs`), wired into `build-app`, `test`, `archive`, `bench`,
`benchmark-build`; `Resources/skills` becomes a folder reference in `supacode.xcodeproj`
exactly like `Resources/docs`. Text resources only — signing/notarization unchanged.

**Registry (`ProwlSkills`, in `ProwlCLIShared` = `supacode/CLIService/Shared`).**
`BundledSkill { id (directory name), name, description, audience, directoryURL }` parsed
from `SKILL.md` frontmatter — a minimal YAML subset (`name:`, `description:` including the
`>-` folded block `prowl-cli` already uses, and a `metadata:` map), no YAML dependency.
`audience` comes from `metadata.prowl-install`: `user` (default when absent — installable
into agent skill folders) or `workflow` (063-D2/D3 role skills: materialized into a run
directory by the runner, never offered for global install). `bundled(resourcesURL:)` lists
skills; the app passes `Bundle.main.resourceURL`, the CLI resolves its own executable
(`/usr/local/bin/prowl` → symlink → `Prowl.app/Contents/Resources/prowl-cli/prowl`, so
`../skills` is a sibling); `PROWL_SKILLS_DIR` overrides for SwiftPM dev builds and tests.
Not run from a bundle and no override → `BUNDLE_NOT_FOUND`.

**Install targets (declarative, verified per runtime).** `SkillInstallTarget { id,
displayName, userDirectory, projectDirectory?, runtimes }`. V1 table — entries marked
*verify* are confirmed (directory, symlink following) by spike S0 before K2 builds on them:

| Target id | User dir | Project dir | Read by |
| --- | --- | --- | --- |
| `claude` | `~/.claude/skills` | `.claude/skills` | Claude Code (follows symlinked skill directories — this repo's `.claude/skills/prowl-cli` link loads) |
| `codex` | `~/.codex/skills` | *verify* | Codex (follows a symlinked skills root; per-directory symlink *verify*) |
| `agents` | `~/.agents/skills` | `.agents/skills` | cross-agent convention (agentskills.io); *verify* which installed runtimes honour it |

Other `AgentProfileRuntime` cases (gemini, copilot, cursor, opencode, amp, droid, …) join the
table as their skill directories are verified; unknown ones stay out rather than guessed.
A user target counts as *detected* when its parent (`~/.claude`, `~/.codex`, `~/.agents`)
exists; undetected targets are listed but never chosen by default, and an explicit
`--target` creates the directory.

**Install semantics (decided 2026-08-22, see Alternatives).** The link points straight at
the bundle: `ln -s <Prowl.app>/Contents/Resources/skills/<id> <targetDir>/<id>` (directory
symlink; creates `<targetDir>` if missing). The symlink install/verify logic is extracted
from `CLIInstallClient` (`supacode/Clients/CLIInstall/CLIInstallClient.swift`) into a shared
`SymlinkInstaller` used by both the CLI install and skills, with one status enum:
`notInstalled` / `installed(path)` (symlink → this bundle) / `installedDifferentSource(path)`
(symlink elsewhere — e.g. a Debug build in DerivedData — or a real directory) /
`broken(path)` (dangling symlink: the app moved or was removed). Conflict rules mirror the
CLI: an existing symlink is replaced (this doubles as Repair for `broken`), a real
file/directory is refused (`INSTALL_CONFLICT`); `uninstall` removes only symlinks. No admin
rights needed. Granularity is skill × target: every link is one explicit action, in the CLI
and in Settings; a skill added by an app update simply shows as Not installed.
Project scope: `--scope project` with `--path <repo>` or the cwd's git root; the CLI prints
one note that the link carries a machine-specific absolute path and that `.git/info/exclude`
is the user's call — Prowl never edits git state.

**CLI (per 060's four-layer rule: parser → contract → `docs/components/cli.md` → skill).**
```
prowl skills list [--json]                                   # skills × targets with status; workflow-audience skills tagged
prowl skills install [<skill>...] [--target <id>]... [--scope user|project] [--path <dir>]
prowl skills uninstall [<skill>...] [--target <id>]... [--scope user|project] [--path <dir>]
prowl skills path <skill>                                    # bundled directory, for scripts and workflows (any audience)
```
Plural `skills` matches `agents` and the planned `profiles`. `install` without skills = every
`user`-audience skill; without `--target` = all detected user targets; without `--scope` =
`user`. Naming a `workflow`-audience skill in `install` is an error. Local-only: never opens
the socket or launches the app. JSON `schema_version` `prowl.cli.skills.v1`; errors
`SKILL_NOT_FOUND`, `SKILL_NOT_INSTALLABLE`, `TARGET_NOT_FOUND`, `INSTALL_CONFLICT`,
`BUNDLE_NOT_FOUND`. Contract file `docs-ai/013-prowl-cli/contracts/skills.md`; `prowl-cli`
skill gains one line telling an agent that `prowl skills install prowl-cli` keeps it current.

**Settings.** No new sidebar item: the Command Line Tool page
(`supacode/Features/Settings/Views/CommandLineToolSettingsView.swift`) gains an **Agent
Skills** section under Installation and Connection, listing `user`-audience skills only
(`workflow`-audience skills belong to 063-D1's Workflows page). Row = name + description +
one status chip per detected target with Install/Remove (Repair for `broken`) + Reveal
bundled skill. State lives in an `AgentSkillsFeature` child of `SettingsFeature`,
initialised when `.commandLineTool` is selected (as `.profiles` initialises `agentProfiles`
in `AppFeature.setSelection`), backed by a `SkillInstallClient` dependency over the shared
installer with a temp-directory test value. Sidebar label stays “Command Line Tool” until
063-D1 reviews the Agents group as a whole.

**063 integration.** `embed-skills` and the registry move here from 063-D1; D1 depends on
K1 and uses `ProwlSkills.skill(id:)` to materialize `skill:` references and to build its
“ask your agent” prompt. D1–D3 skills appear in `prowl skills` and Settings by being added to
`skills/` with the right `metadata.prowl-install`; no per-skill code.

## Slices

Release placement: S0 and K1 ship in 063's R1 in parallel with A1 (K1 is small and D1
depends on it); K2 and K3 follow inside R1 so the R1 user can `prowl skills install`.

| Slice | Contents | Depends |
| --- | --- | --- |
| **S0** spike | Verify the target table: Codex per-directory symlink following and project dir, `.agents/skills` readers among installed runtimes, how each runtime treats a dangling symlink. Use a temporary `CODEX_HOME` / project, never the user's live skill folders. Record results in this plan. | — |
| **K1** | `embed-skills`, `Resources/skills` folder reference, `ProwlSkills` registry + frontmatter parser (incl. `metadata.prowl-install`), tests; 063 plan cross-link. | — |
| **K2** | Shared `SymlinkInstaller` extracted from `CLIInstallClient`, `prowl skills list\|install\|uninstall\|path`, contract, `cli.md`, `prowl-cli` skill line, smoke + integration tests (temp dirs, `PROWL_SKILLS_DIR`). | S0, K1 |
| **K3** | Agent Skills section on the Command Line Tool page, `AgentSkillsFeature` + `SkillInstallClient`, reducer tests, `docs/components/settings.md`. | K2 |

## Alternatives & decisions

Decisions below were taken in the 2026-08-22 plan review (#712):

- **Link target: bundle directly vs an app-maintained indirection**
  (`~/Library/Application Support/com.onevcat.prowl/skills` → current bundle). Direct: its
  failure modes (app moved, Debug-vs-Release source, dangling links) are the same set the
  `/usr/local/bin/prowl` symlink has carried without trouble; the indirection only buys
  self-healing after an app move, at the cost of a launch-time write, a two-hop status check,
  and a second mental model. Synced dotfiles (onevcat's `~/.claude/skills` and
  `~/.codex/skills` are symlinks into a synced folder) resolve on any Mac with Prowl at
  `/Applications`, which is the common case. Indirection stays an upgrade path if moves
  break installs in practice.
- **Project scope and git: note only vs auto `.git/info/exclude` vs no project scope.** Note
  only: Prowl is a per-user app and project scope is a personal preference, so its git
  hygiene is the user's; auto-editing `.git/info/exclude` surprises users and must find the
  main repo's `.git` under worktrees.
- **Audience: flat vs frontmatter `metadata.prowl-install` vs directory split.** Frontmatter:
  audience is the skill's own property; it keeps one registry root for 063's `skill:`
  resolution and lets a bare `prowl skills install` mean “install Prowl's skills”.
- **Settings: dedicated Skills page vs a section on Command Line Tool.** Section: with only
  `user`-audience skills shown (two by 063-D3), a page would be thin, the CLI page was
  thinner still, and “install the tool → how it connects → teach your agent to use it”
  reads as one story.
- **Granularity: skill × target vs per-target toggle with auto-linking of new skills.**
  Skill × target: one explicit action per link, same shape as the CLI; auto-linking would
  write into agent folders without a user action and fight Debug/Release builds.
- **Symlink vs copy** — symlink; copy stays an open question for users whose runtime
  refuses symlinks.
- **CLI reads the bundle next to itself vs asks the app over the socket** — local: works
  with the app closed and adds no protocol surface; `PROWL_SKILLS_DIR` covers dev/tests.
- **Registry in `ProwlCLIShared` vs app-only** — shared: the CLI and the workflow runner
  both need it; Foundation-only, no new dependency.
- **Prowl's skills only vs a general skills manager** — Prowl's only.
- **Naming** — `prowl skills` (plural), consistent with `agents` / `profiles`.

## Risks

- A runtime may not follow directory symlinks for skills → S0 verifies before K2; if any V1
  target refuses symlinks, copy mode is promoted from open question to K2 scope.
- Debug builds: links point into DerivedData and show as `installedDifferentSource` in a
  Release app (and vice versa). Acceptable; the status text names the other source.
- Runtimes move their skill directories → the table is declarative and small; unknown
  runtimes are omitted, never guessed.
- Project-scope symlinks leak absolute paths into a repo if committed → CLI note; no git
  mutation by Prowl.
- Synced skill folders carry the link to other Macs → resolves wherever Prowl is at the
  same path; otherwise `broken` until Prowl is installed there.

## Verification

- Unit: frontmatter parser (plain and `>-` descriptions, `metadata.prowl-install`), status
  tri-state + `broken` over temp directories, symlink replacement and real-directory refusal,
  CLI bundle resolution through a symlinked executable, `install` refusing
  `workflow`-audience skills.
- `make test-cli-smoke` (parsing) and `make test-cli-integration` (filesystem round trip in a
  temp `PROWL_SKILLS_DIR`, no socket needed); reducer tests for `AgentSkillsFeature`; the
  existing CLI install tests keep passing on the extracted `SymlinkInstaller`.
- `make check`, `make build-app`; release archive contains `Contents/Resources/skills/`.
- Manual: `prowl skills install`, start Claude Code and Codex in a fresh shell, `prowl-cli`
  is listed and triggers; Settings shows the same status as `prowl skills list`.

## Open questions

- Copy mode (`--copy`) in V1 or later? Needed only if S0 finds a symlink-averse runtime.
- Should 063-D1's Workflows “ask your agent” prompt instruct `prowl skills install` first?
- Settings project-scope UI (per-repository section in Repo Settings) — V2 if asked.

## Amendments

(append `- Updated 2026-MM-DD: ... — see [00N-topic.md](00N-topic.md)` lines here)
