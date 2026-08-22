# 065 — Bundled Agent Skills: Plan

| | |
| --- | --- |
| **Status** | Planned |
| **Anchor date** | 2026-08-22 |
| **Primary PRs** | (plan PR), K1–K3 to fill in |
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
3. **Settings › Agents › Skills** — per-skill rows with per-target install status and
   Install/Remove actions, mirroring the Command Line Tool install row (same tri-state idea).
4. **One locator** (`ProwlSkills`) for 063: `skill(id:)` resolves to the bundled directory so
   workflows and kickoff prompts can reference skills without any install step.

**Non-goals (V1):** managing third-party or user-authored skills (this is Prowl's own skills
only, not a general skills manager); copy mode (symlink only — see open questions); silently
installing into an agent without a user action; editing skills in-app; Settings UI for
project scope (CLI only in V1).

## Design / Approach

**Build & bundle.** `Makefile` gains `embed-skills` (rsync `skills/` → `Resources/skills/`,
`--delete`, same shape as `embed-docs`), wired into `build-app`, `test`, `archive`, `bench`,
`benchmark-build`; `Resources/skills` becomes a folder reference in `supacode.xcodeproj`
exactly like `Resources/docs`. Text resources only — signing/notarization unchanged.

**Registry (`ProwlSkills`, in `ProwlCLIShared` = `supacode/CLIService/Shared`).**
`BundledSkill { id (directory name), name, description, directoryURL }` parsed from
`SKILL.md` frontmatter (a minimal YAML subset: `name:`, `description:` including the `>-`
folded block `prowl-cli` already uses — no YAML dependency). `bundled(resourcesURL:)` lists
skills; the app passes `Bundle.main.resourceURL`, the CLI resolves its own executable
(`/usr/local/bin/prowl` → symlink → `Prowl.app/Contents/Resources/prowl-cli/prowl`, so
`../skills` is a sibling); `PROWL_SKILLS_DIR` overrides for SwiftPM dev builds and tests.
Not run from a bundle and no override → `BUNDLE_NOT_FOUND`.

**Install targets (declarative, verified per runtime).** `SkillInstallTarget { id,
displayName, userDirectory, projectDirectory?, runtimes }`. V1 table — entries marked
*verify* are confirmed (dir, symlink following) by spike S0 before K2 builds on them:

| Target id | User dir | Project dir | Read by |
| --- | --- | --- | --- |
| `claude` | `~/.claude/skills` | `.claude/skills` | Claude Code |
| `codex` | `~/.codex/skills` | *verify* | Codex |
| `agents` | `~/.agents/skills` | `.agents/skills` | cross-agent convention (agentskills.io); *verify* which installed runtimes honour it |

Other `AgentProfileRuntime` cases (gemini, copilot, cursor, opencode, amp, droid, …) join the
table as their skill directories are verified; unknown ones stay out rather than guessed.
A user target counts as *detected* when its parent (`~/.claude`, `~/.codex`, `~/.agents`)
exists; undetected targets are listed but never chosen by default.

**Install semantics.** `install` = `ln -s <bundle>/skills/<id> <targetDir>/<id>` (directory
symlink; creates `<targetDir>` if missing). Status mirrors `CLIInstallClient`:
`notInstalled` / `installed(path)` (symlink → this bundle) / `installedDifferentSource(path)`
(symlink elsewhere — e.g. a Debug build in DerivedData — or a real directory) / `broken(path)`
(dangling symlink: the app moved or was removed; offer Repair). `uninstall` refuses anything
that is not a symlink we recognise, like the CLI uninstall does. No admin rights needed.
Project scope: `--scope project` with `--path <repo>` or the cwd's git root; the CLI prints a
note that a committed symlink carries a machine-specific absolute path (git hygiene is the
user's call — see open questions).

**CLI (per 060's four-layer rule: parser → contract → `docs/components/cli.md` → skill).**
```
prowl skills list [--json]                                   # skills × targets with status
prowl skills install <skill>... | --all [--target <id>]... [--scope user|project] [--path <dir>]
prowl skills uninstall <skill>... | --all [--target <id>]... [--scope user|project] [--path <dir>]
prowl skills path <skill>                                    # bundled directory, for scripts and workflows
```
Plural `skills` matches `agents` and the planned `profiles`. `install` without `--target`
uses all detected user targets; without `--scope` uses `user`. Local-only: never opens the
socket or launches the app (the app need not be running). JSON `schema_version`
`prowl.cli.skills.v1`; errors `SKILL_NOT_FOUND`, `TARGET_NOT_FOUND`, `INSTALL_CONFLICT`
(non-symlink exists), `BUNDLE_NOT_FOUND`. Contract file
`docs-ai/013-prowl-cli/contracts/skills.md`; `prowl-cli` skill gains one line telling an
agent that `prowl skills install prowl-cli` keeps it current.

**Settings.** `SettingsSection.skills` and `SkillsSettingsView` under the Agents group
(order: Profiles, Skills, Command Line Tool; 063-D1 inserts Workflows after Profiles).
`SkillsFeature` (TCA) owns `skills`, `targets`, `statuses[skill][target]`, `alert`;
`SkillInstallClient` dependency wraps the shared installer (`bundledSkills`, `targets`,
`status`, `install`, `uninstall`) with a temp-directory test value. Rows: name + description,
one status chip per detected target with Install/Remove (Repair for `broken`), Reveal bundled
skill in Finder, Copy path. `AppFeature.setSelection(.skills)` initialises/clears the state
like `.profiles`. The Command Line Tool page stays CLI-only.

**063 integration.** `embed-skills` and the registry move here from 063-D1; D1 depends on
K1 and uses `ProwlSkills.skill(id:)` to materialize `skill:` references and to build its
“ask your agent” prompt. D1–D3 skills appear in `prowl skills` and Settings by being added to
`skills/`; no per-skill code.

## Slices

| Slice | Contents | Depends |
| --- | --- | --- |
| **S0** spike | Verify the target table: directories, symlinked skill directories honoured by Claude Code and Codex, `.agents/skills` readers. Record results in this plan. | — |
| **K1** | `embed-skills`, `Resources/skills` folder reference, `ProwlSkills` registry + frontmatter parser, tests; 063 plan cross-link. | — |
| **K2** | `prowl skills list\|install\|uninstall\|path`, shared installer + status model, contract, `cli.md`, `prowl-cli` skill line, smoke + integration tests (temp dirs, `PROWL_SKILLS_DIR`). | S0, K1 |
| **K3** | Settings › Agents › Skills page, `SkillsFeature` + `SkillInstallClient`, reducer tests, `docs/components/settings.md`. | K2 |

## Alternatives & decisions

- **Symlink vs copy** — symlink: one source of truth that follows app updates, and it is
  what the CLI install already does. Copy stays an open question for dotfile-sync users.
- **CLI reads the bundle next to itself vs asks the app over the socket** — local: works
  with the app closed and adds no protocol surface; `PROWL_SKILLS_DIR` covers dev/tests.
- **Separate Skills page vs a section on Command Line Tool** — separate page: the list
  grows to four skills × several targets by 063-D3, and the CLI page should stay about the
  CLI.
- **Registry in `ProwlCLIShared` vs app-only** — shared: the CLI and the workflow runner
  both need it; Foundation-only, no new dependency.
- **Prowl's skills only vs a general skills manager** — Prowl's only; general managers
  (`npx skills`, per-runtime marketplaces) exist and are not this app's job.
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

## Verification

- Unit: frontmatter parser (plain and `>-` descriptions), status tri-state + `broken` over
  temp directories, uninstall refusing real directories, CLI bundle resolution through a
  symlinked executable.
- `make test-cli-smoke` (parsing) and `make test-cli-integration` (filesystem round trip in a
  temp `PROWL_SKILLS_DIR`, no socket needed); reducer tests for `SkillsFeature`.
- `make check`, `make build-app`; release archive contains `Contents/Resources/skills/`.
- Manual: `prowl skills install prowl-cli`, start Claude Code and Codex in a fresh shell, the
  skill is listed and triggers.

## Open questions

- Copy mode (`--copy`) in V1 or later? Needed only if S0 finds a symlink-averse runtime or
  users sync dotfiles across machines.
- Project scope git hygiene: leave to the user (CLI note) or offer `.git/info/exclude`?
- Should the Command Line Tool install success alert nudge “install the prowl-cli skill”?
- Should 063-D1's Workflows “ask your agent” prompt instruct `prowl skills install` first?
- Settings project-scope UI (per-repository Skills section in Repo Settings) — V2 if asked.

## Amendments

(append `- Updated 2026-MM-DD: ... — see [00N-topic.md](00N-topic.md)` lines here)
