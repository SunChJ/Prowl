# 065.003 — Bundled Skills Foundation (K1)

## Context

S0 confirmed that Prowl can distribute its own skills as direct directory symlinks, but the
shipped app still had no canonical skills bundle or shared registry. K1 establishes that
foundation for the later CLI installer, Settings UI, and 063 workflow materialization without
installing or modifying any skill in a user or project directory.

## Change

- `Makefile` now stages `skills/` into the ignored `Resources/skills/` directory through an
  `embed-skills` target using `rsync -a --delete`.
- `build-app`, `test`, `archive`, `benchmark-build`, and `bench` depend on `embed-skills`,
  matching the existing `embed-docs` lifecycle.
- `Resources/skills` is an Xcode folder reference in the app Resources build phase, so each
  shipped skill keeps its directory and `SKILL.md` layout under
  `Prowl.app/Contents/Resources/skills/<id>/`.
- `ProwlCLIShared` now exposes the Foundation-only `ProwlSkillAudience`, `BundledSkill`, and
  `ProwlSkills` registry. `bundled(resourcesURL:)` enumerates immediate skill directories in
  stable ID order, while `skill(id:resourcesURL:)` searches that enumeration instead of
  constructing an input-derived path.
- The minimal frontmatter parser reads required `name` and plain or `>-` folded `description`
  fields plus the nested `metadata.prowl-install` audience. Missing audience defaults to
  `user`; explicit `user` and `workflow` are accepted; any other value fails closed.
- `bundledForCLI(executableURL:environment:)` treats `PROWL_SKILLS_DIR` as a direct skills-root
  override. A present but invalid override does not fall back. Without the override, it resolves
  the executable symlink and locates `../skills` beside the bundled `prowl-cli` directory.
- `ProwlSkillsError` provides typed `BUNDLE_NOT_FOUND` and invalid-frontmatter failures for the
  later K2 command layer to map without parsing localized text.

## Decisions and boundaries

- K1 remains synchronous and Foundation-only. It adds no YAML dependency, installer, target
  detection, CLI command, socket behavior, Settings state, or write into an agent skill folder.
- Registry IDs are immediate directory names. Lookup filters the parsed registry, so values such
  as `../prowl-cli` cannot traverse out of the bundle.
- `PROWL_SKILLS_DIR` points directly at a skills root, whereas `bundled(resourcesURL:)` receives
  the app Resources root and appends `skills/`. The private common enumerator keeps this
  distinction explicit.
- Malformed audience metadata never defaults to `user`, preventing a typo from making a future
  workflow-only skill globally installable.

## Verification

- TDD RED: the focused SwiftPM suite failed with 21 expected missing-symbol errors before the
  shared registry types existed.
- TDD GREEN: `ProwlSkillsTests` passed 11 tests covering plain and folded descriptions, default
  and explicit audiences, invalid/missing frontmatter, stable sorting, safe ID lookup, override
  precedence and invalid-override behavior, executable-symlink resolution, and
  `BUNDLE_NOT_FOUND`.
- `make build-cli` and `make test-cli-smoke` passed.
- `make test-cli-integration` passed 97 integration tests.
- `make test` passed and the xcresult checks verified 2,621 main app tests plus 2 isolated shell
  cancellation tests with zero failures.
- `make check` passed, including strict Swift formatting, SwiftLint, and 44 script tests.
- `make build-app` passed with zero errors or warnings.
- The final Debug app contains
  `Contents/Resources/skills/prowl-cli/SKILL.md`; it is byte-for-byte identical to
  `skills/prowl-cli/SKILL.md`.

## Refs

- Slice: 065-K1
- Branch: `feat/bundled-skills-k1`
- PR: pending
- Depends on: [002-s0-skill-targets.md](002-s0-skill-targets.md)
