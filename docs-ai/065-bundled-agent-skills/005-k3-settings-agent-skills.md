# 065.005 — Agent Skills Section on the Command Line Tool Page (K3)

## Context

K2 (#730) gave the `prowl` CLI status, install, and uninstall for every bundled skill × target
link, but a user who never opens a terminal still had no way to see that Prowl ships skills or
to link them. K3 is the last 065 slice: the Settings › Agents › Command Line Tool page gains an
**Agent Skills** section that exposes exactly the CLI's user-scope actions, backed by the same
shared installer so both surfaces always report the same status.

## Change

- `SkillInstallClient` (`supacode/Clients/SkillInstall/`) is the TCA dependency over the shared
  installer, shaped like `CLIInstallClient`: `bundledSkills()`, `status(skill, target)`,
  `install(skill, target)`, `uninstall(skill, target)`, `revealSkill(skill)`. `liveValue` reads
  `Bundle.main.resourceURL` and the user's home; `live(resourcesURL:userRoot:)` builds the same
  client over any roots so tests run against a temporary bundle and home, and `testValue` is an
  inert stub. `SymlinkInstallError` maps to `SkillInstallError.message` the way `CLIInstallError`
  does: a real file or directory is reported as occupying the slot and never deleted.
- `AgentSkillsFeature` (`supacode/Features/Settings/Reducer/`) is a child of `SettingsFeature`
  (`agentSkills: State?`), created by `AppFeature.setSelection(.commandLineTool)` and cleared
  on every other section, exactly like `agentProfiles` for `.profiles`. `.task` loads the
  `user`-audience skills and one `SkillLink` per **detected** target (`SkillTargetStatus.detected`);
  `installLink` covers Install, Repair, and Replace (all replace the slot with a link to this
  bundle), `removeLink` removes a symlink only, `revealSkillButtonTapped` opens the bundled
  folder in Finder. Every completion — success or failure — recomputes all rows and chips, because
  aliased targets (`~/.claude/skills` and `~/.codex/skills` symlinked to one folder) share one
  physical link. A failure sets an "Agent Skills Error" alert on the child and delegates a
  warning toast; a success delegates a success toast (`AppFeature` maps
  `agentSkills(.delegate(.linkChanged))` to `repositories.showToast`).
- `AgentSkillsSectionView` renders under Installation and Connection: one row per skill (name,
  id when it differs, description limited to three lines with the full text as a tooltip,
  Reveal), and one chip per detected target with the status wording of `prowl skills list`
  (Installed / Not installed / Linked elsewhere `→ destination` / Real file or directory / Broken
  link `→ destination`) and one action button (Remove / Install / Replace / — / Repair). A real
  file or directory shows only "Prowl never deletes it; remove it manually to link here." Empty
  states: the bundle could not be read (message from `ProwlSkillsError`), no installable skills,
  and no detected target (points at `prowl skills install --target claude|codex|agents`). Every
  button carries a tooltip; chips show their link path on hover.
- Docs: `docs/components/settings.md` gains an Agent Skills section (statuses, actions, aliased
  targets, empty states) and `docs/components/cli.md` notes that Settings offers the same
  user-scope actions with the same status as `prowl skills list`.

## Decisions and boundaries

- Success feedback is a toast plus the chip's own state change; only failures raise a modal
  alert. The CLI-install row alerts on success as well, but a per-link modal for up to three
  chips per skill would be noise, and the toast path is the same `AppFeature` mechanism.
- Detection and status come from the client's `SkillTargetStatus`, so the reducer never reads
  the home directory itself and undetected targets are simply absent (the CLI's `--target`
  creates them). Workflow-audience skills are filtered in the reducer, not the client, because
  the audience rule belongs to this surface.
- Load and status refresh are synchronous in the reducer (a handful of `lstat` calls plus one
  frontmatter parse), matching the CLI-install row's synchronous `installationStatus`; only
  install/uninstall run as effects.
- Not in K3: project scope, copy mode, third-party skills, auto-linking after updates, new
  targets, changes to the shared installer or the CLI contract. `ProwlCLIShared` is untouched.

## Verification

- TDD RED: 25 missing-symbol errors for `SkillInstallClientTests` before the client existed;
  21 for the `AppFeature` selection and toast tests before the wiring existed. GREEN: 11 client
  tests (all four statuses, foreign-link destination, install/replace/repair, conflict refused
  with the directory intact, uninstall of links only, aliased targets) and 10 `TestStore` tests
  (`user`-only rows, detected-only chips, install/remove/repair/replace transitions with full
  refresh, aliased refresh, conflict alert, bundle missing, reveal, unknown ids ignored), all
  over temporary roots; the `AppFeature` selection tests cover `agentSkills` creation and
  clearing and the toast mapping.
- `make check` passed (strict swift-format, SwiftLint, 44 script tests); `make build-app`
  passed with zero warnings and the Debug app bundles `Contents/Resources/skills/prowl-cli/SKILL.md`
  identical to the source; `make build-cli`, `make test-cli-unit` (129) and
  `make test-cli-integration` (102) passed unchanged.
- `make test`: 2,643 main app tests passed; one deferred-Ghostty-surface test
  (`WorktreeTerminalStateAgentProfileTests/deferredProfileAppliesFontSizeAdjustmentAfterSurfaceCreation`)
  failed with `.surfaceCreationFailed` while the display was asleep (`pmset -g log`) and passed
  when re-run with the display awake; the suite was re-run under `caffeinate` (see the PR for
  the final count).
- Visual: a copy of the Debug app launched with `CFFIXED_USER_HOME` (Foundation ignores a bare
  `HOME` override) and a dedicated `PROWL_CLI_SOCKET`, so its settings, home, and skill folders
  lived in a temporary directory. Screenshots of Settings › Agents › Command Line Tool show the
  section in every state: Not installed × 2 with `codex` undetected; Installed / Real file or
  directory / Broken link `→ /Volumes/Old/…` with Remove / no button / Repair; Linked elsewhere
  `→ …/DerivedData/…` with Replace; aliased `claude` + `codex` both Installed from one link; and
  the no-target explanation. The Mac was locked during the run, so button clicks could not be
  delivered to the isolated instance; the action path is covered by the `TestStore` tests over
  the live client. The live `~/.claude/skills`, `~/.codex/skills`, and `~/.agents` were neither
  read as inputs nor modified.

## Refs

- Slice: 065-K3
- Branch: `feat/bundled-skills-k3`
- PR: to fill in
- Depends on: [004-k2-skill-installer-cli.md](004-k2-skill-installer-cli.md)
