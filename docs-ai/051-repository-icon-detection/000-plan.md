# 051 — Repository Icon Detection on Add: Plan

| | |
| --- | --- |
| **Status** | In progress — prerequisite met: [GlyphonKit](https://github.com/onevcat/GlyphonKit) `v0.1.0` published |
| **Anchor date** | 2026-07-25 |
| **Primary PRs** | — |
| **Related** | [025-repo-identity-appearance](../025-repo-identity-appearance/000-plan.md), [040-automatic-open-in](../040-automatic-open-in/000-plan.md), [044-foundation-model-branch-names](../044-foundation-model-branch-names/000-plan.md), issue #525 |

## Background

Prowl supports a manually selected per-repository icon, but repositories without one remain
text-only. Issue #525 proposes a useful default: inspect a repository once when it is added,
and use a local project icon only when the evidence is strong. This is deliberately not the
GitHub owner-avatar fallback proposed in #524: users commonly work under one or two owners,
so repeated avatars add visual noise without identifying the project.

The existing automatic **Open In** path is relevant but not sufficient on its own.
`WorktreeProjectKind` performs one shallow listing and resolves one primary ecosystem for
`OpenWorktreeAction`; its ordered markers are intentionally biased towards a suitable editor.
It recognizes Apple, Android, .NET, Java, Go, Rust, C++, PHP, Ruby, Python, and generic web
projects. It does not establish that an image asset is an application icon, handle hybrid
projects such as Flutter, or retain enough evidence for a confidence decision.

`RepositoryAppearance` already persists an SF Symbol or imported local image, and
`RepositoryIconAssetStore` already copies an image into Prowl-owned per-repository storage.
The detector should build on those rendering and persistence paths; it must not render from
an untrusted project file in place.

The supplied PR #583 is unrelated: it is a read-only mobile remote-control bridge. The
relevant prior work is issue #525 and closed PR #524.

## Goals

- Make a newly added repository easier to identify with a meaningful, local, high-confidence
  icon when one exists.
- Keep add/open interaction responsive. Detection never blocks repository loading, selection,
  terminal creation, or the main actor.
- Preserve user agency: a manual image, SF Symbol, clear/reset, or global opt-out always wins.
- Read only local files, make no network requests, and never modify the repository.
- Attempt automatic detection only for repository IDs newly added in the current operation;
  startup, reload, and existing repositories never trigger a scan.

### Non-goals

- Remote owner avatars, code-host API calls, favicon downloads, telemetry, and generated
  placeholder icons.
- Automatically choosing a repository color. Color changes sidebar, shelf, and canvas chrome
  and have lower semantic confidence than a verified project icon.
- Foundation Model inference in the add path. It is advisory work, not a prerequisite for
  adding or opening a project.
- Treating every `package.json`, `logo.svg`, or generated asset as product identity.

## Findings and design constraints

| Area | Observed implementation | Decision consequence |
| --- | --- | --- |
| Project classification | `supacode/Domain/WorktreeProjectKind.swift` uses a synchronous top-level listing and one ordered result. | Keep its editor behavior intact; introduce icon-specific evidence rather than overloading a single enum case. |
| Add lifecycle | `openRepositories` resolves roots, persists them, loads repositories, then focuses the first new repository. | Start detection only after `openRepositoriesFinished`; do not await it in the add effect. |
| Icon persistence | `RepositoryIconSource` supports SF Symbols and copied user images; `RepositoryIconAssetStore` imports a source URL atomically. | Reuse the store after validation, but do not let the detector bypass it. |
| Image validity | The asset store intentionally accepts arbitrary picker input and rendering later uses `NSImage(contentsOf:)`. | The detector needs stricter validation before copying: regular local file, contained path, supported raster/vector format, bounded bytes and pixels, and successful decode. |
| Existing model service | Prowl's `FoundationModelLLMService` is a one-call, 3-second plain-text service. | It is not a safe substitute for Glyphon's two-stage constrained-symbol pipeline. |
| Glyphon | `Sources/Glyphon` already separates retrieval from UI, bundles a 905 KB symbol index, and reports roughly 2.9 s/query for the tuned two-model-call flow. | Model suggestions may be useful only as cancellable, explicit settings recommendations. |

## Design / Approach

### 1. Deterministic, evidence-based asset detection

Add a small, testable detector that returns an optional candidate and its evidence rather than
mutating settings. It may collect multiple project signals, while `WorktreeProjectKind` remains
the single-choice editor preference resolver.

The first automatic release accepts only these high-confidence paths:

1. An Apple asset catalog's `AppIcon.appiconset/Contents.json`, decoded as a manifest and
   resolved to a contained, referenced image. Choose the largest valid referenced raster rather
   than guessing from arbitrary catalog files.
2. An Android project proven by an Android manifest or Android Gradle plugin plus a standard
   launcher raster in a `mipmap-*` directory. Adaptive XML and arbitrary drawable resources
   are not enough by themselves.
3. Flutter only when `pubspec.yaml` and one of its platform application-icon layouts agree;
   reuse the platform-specific evidence above.

A root-level `logo.*`, `icon.*`, or web favicon is a lower-confidence follow-up, not an
initial automatic rule. Such names frequently refer to templates, documentation, or tooling.
They can be enabled only after a fixture corpus shows acceptable precision.

Traversal is bounded and deterministic: scan a small fixed depth and entry budget, skip
`.git`, dependency/build directories (`node_modules`, `Pods`, `.build`, `DerivedData`,
`build`, `dist`, `target`, and `vendor`), never follow an escaping symlink, and stop at the
first candidate tier with a validated result. The detector validates image metadata before
copying to avoid a decompression bomb or an unusable file.

### 2. Non-blocking lifecycle and persistence

After a repository has appeared in state, launch at most a small bounded number of utility
priority detection tasks. Repository rendering and terminal focus proceed immediately. A
result commits only if all of these remain true at commit time:

- the repository still exists and automatic detection remains enabled;
- the result belongs to the original normalized repository root and request generation;
- no manual icon or explicit user clear superseded the request; and
- no icon is already present.

The appearance model needs durable origin/outcome information (manual, detected, suppressed)
in addition to the renderable icon. The current optional `RepositoryAppearance.icon` alone
cannot distinguish an intentional clear from an untouched repository when an asynchronous
result races with the settings UI. This information also prevents a removed-and-re-added
repository with retained appearance data from being scanned again unexpectedly.

A validated candidate is copied through `RepositoryIconAssetStore` and persisted as a normal
`RepositoryIconSource.userImage`; Prowl never retains an absolute path into the repository.
Removal, replacement, and rendering continue through the existing paths.

### 3. Settings and user control

Add a global Appearance setting, **Detect project icons automatically**, enabled by default.
Its help text must state that detection is local, happens only when adding future repositories,
and never replaces a manual icon. Disabling it cancels pending work and leaves already detected
icons unchanged. Repository Settings should identify a detected icon and make **Clear Icon**
an explicit suppression, not an invitation for a pending detector to restore it.

No model preference is needed for the first release because the model is never called
automatically. A user who does not request a recommendation supplies no README content to a
model.

### 4. Separate, reviewable Foundation Model recommendation

A later Repository Settings action may offer **Suggest an SF Symbol from README**. It is
explicitly user-invoked, cancellable, shows a progress state, presents one or more candidates,
and changes nothing until the user chooses **Use**.

The input should be a bounded visible-text synopsis, not a raw "first N words" slice:
read a limited local README, discard front matter, badges, and fenced code, then cap to roughly
600 Unicode characters. A root package description can supplement it. This behaves predictably
for CJK text and matches Glyphon's current prompt budget.

Glyphon's tuned recipe is the right technical reference: guided English keyword extraction,
semantic-root retrieval, a dynamically constrained candidate choice, greedy sampling, and a
validated plain-text fallback for schema guardrail refusals. It has important constraints:
the on-device model is unavailable on some Macs, its context window is finite, and the tuned
flow is materially too slow for automatic add.

Do not import the current Glyphon package into Prowl yet. Although its `Glyphon` target has no
target-level third-party dependency, the package also declares RevenueCat and bundles its own
symbol dataset. First establish the Prowl recommendation API and its evaluation fixtures; then,
if the API stabilizes, extract a narrow `SFSymbolRecommender` package containing only symbol
metadata, retrieval, and the Foundation Models pipeline. Review Apple's SF Symbols/data
redistribution terms before publishing any bundled metadata as open source.

## Alternatives & decisions

| Option | Decision | Why |
| --- | --- | --- |
| GitHub owner avatar fallback | Rejected | Repeats identities across a user's repositories and needs network rendering/cache behavior. |
| Synchronous full-tree scan on add | Rejected | Large repositories and generated directories would make add latency unpredictable. |
| Reuse `WorktreeProjectKind` as the detector | Rejected | Its one primary kind is correct for editor choice, not sufficient evidence for icon provenance. |
| Auto-apply README/LLM result | Rejected | Model latency and semantic uncertainty violate the non-blocking, low-noise requirement. |
| Directly depend on Glyphon now | Deferred | Package boundary, binary/resource cost, API ownership, and SF Symbols redistribution review need a deliberate extraction. |

## Verification plan

- Unit-test marker and manifest fixtures: valid Apple/Android/Flutter candidates, malformed
  manifests, missing files, path traversal, symlink escape, oversized/undecodable images, and
  ambiguous hybrid repositories.
- Reducer tests: only newly added IDs schedule work; disabled settings, removal, manual set,
  and manual clear prevent stale commits; no existing repository is revisited on reload.
- Performance test with a large synthetic tree: main-actor add path remains independent of the
  scan; traversal obeys depth/entry limits and cancellation stops work promptly.
- Manual smoke test: add a fixture project, observe immediate opening followed by a valid icon;
  disable the setting and confirm a second project stays text-only.
- Before extracting or publishing a recommender package, run Glyphon's held-out evaluation and
  a Prowl-specific corpus of anonymized project descriptions; model-score deltas below its
  documented run-to-run noise are not treated as regressions.

## Amendments

- 2026-07-25: Pre-implementation interview decisions are recorded in
  [002-design-alignment.md](002-design-alignment.md), which supersedes conflicting provisional
  choices above. A second round resolved the remaining open question (inline loading in the
  picker sheet), the menu structure (Choose Symbol… plus Suggest an Icon…, both opening one
  sheet with an in-sheet Suggest button), suggestion caching (session-scoped in-memory cache
  with Regenerate), and delivery sequencing (extract the shared recommender package first,
  then ship automatic detection and the suggestion flow together).
- 2026-07-25 (follow-up): onevcat approved additional probes — Icon Composer `.icon`
  bundles, Tauri bundle icons, `package.json` `"icon"`, a Unity project kind for Open In,
  and a generic near-square `icon`/`logo` fallback tier. The generic tier supersedes this
  plan's "defer root logo" stance; the aspect-ratio gate addresses the precision concern
  that motivated the deferral. See the follow-up section in
  [001-action.md](001-action.md).
