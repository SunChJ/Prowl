# 051.002 — Design Alignment

## Context

On 2026-07-25, the repository-icon plan was reviewed through a decision-by-decision
interview before implementation. This record supersedes the conflicting provisional choices in
`000-plan.md`; no production code has been changed.

## Confirmed product decisions

### Automatic local icon detection

| Topic | Decision |
| --- | --- |
| Default | **Enabled** for new installations. |
| Scope | Only roots added after the setting is enabled: Git repositories and plain folders. Never scan Project Workspace containers or retroactively scan existing roots. |
| Feedback | Silent. A detected icon appears naturally; no toast, badge, or failure notice. |
| Model use | Never run Foundation Models during add. No validated local candidate means text-only identity. |
| Global disable | Applies to future additions only; it does not remove existing detected icons. |
| Clear Icon | Removes the icon and records an explicit suppression. There is no Re-detect command. Only removing and re-adding the root starts another automatic attempt. |
| Repository removal | Clear detected image assets and automatic/suppressed detection state, but preserve user-selected icon, color, and title. |

### Classification and candidate resolution

`WorktreeProjectKind` becomes the first-stage project classifier for both Automatic Open In and
icon probing. It must not itself assert icon validity: each kind delegates to a validating probe.

| Order | Project kind / source | Resolution rule |
| --- | --- | --- |
| 1 | Flutter | Detect as a first-class kind; choose iOS AppIcon, then Android launcher. |
| 2 | React Native | Detect as a first-class kind; choose iOS AppIcon, then Android launcher. |
| 3 | Apple | Probe referenced `AppIcon.appiconset` images. |
| 4 | Android | Probe only complete raster launcher assets; adaptive icon XML is deferred. |
| 5 | Web | Probe source order: manifest icon, explicit HTML `rel=icon`, `public/favicon.*`, then root `logo.*` / `icon.*`. |

The detector tries kinds in the table order and falls through when a higher-priority kind has no
valid candidate. For multiple valid candidates in the same platform, choose the path nearest to
the repository root; break ties by normalized relative-path lexicographic order. Within one
Apple icon catalog, choose the largest valid referenced raster.

Flutter requires its own positive project signal; React Native requires a package dependency and
native layout. Static Web folders without `package.json` are recognized only when root
`index.html` is accompanied by a qualifying Web icon asset.

Detected SVGs preserve their intrinsic colors. This is a separate rendering mode from existing
user-selected SVGs, which continue to follow the repository tint setting.

### Automatic Open In additions

The new classifications also improve Automatic Open In:

| Kind | Preferred actions before generic fallback |
| --- | --- |
| Flutter | Android Studio → IntelliJ → VS Code family |
| React Native | VS Code family → WebStorm → Android Studio |

### Explicit SF Symbol suggestions

The Repository Icon menu gains **Suggest an Icon…** and keeps it available for empty, detected,
and manually selected icons alike. It opens Choose Symbol and does not persist anything until the
user selects a result.

| Topic | Decision |
| --- | --- |
| Results | Show Glyphon's best choice, four alternates, and reason in a `Suggested for this repository` section. |
| Input order | Clean visible README synopsis → root manifest description → repository display name. Do not concatenate all sources blindly. |
| Disclosure | The result view states the actual source, for example `Based on README`. |
| Model failure/unavailability | Show retrieval-only candidates labelled `Keyword suggestions`; never imply they are model recommendations. |
| Availability | Suggest an Icon remains available even when an icon already exists; choosing a result is an explicit replacement. |
| Automatic use | Never call the model during add and never auto-apply a model result. |

## Shared package prerequisite — met (2026-07-25)

The extraction completed on the Glyphon side. Prowl consumes:

| | |
| --- | --- |
| Package | [github.com/onevcat/GlyphonKit](https://github.com/onevcat/GlyphonKit), public, MIT |
| Dependency | `.package(url: "https://github.com/onevcat/GlyphonKit.git", from: "0.1.0")`, product `GlyphonKit` |
| Module | `import GlyphonKit`; the facade type keeps the name `Glyphon` |
| API used by 051 | `Glyphon()`, `recommend(from:)` → `SymbolRecommendation` (`symbol`, 4 `alternates`, `reason`, `usedAI`), `search(_:limit:)`, `AIAvailability.current` |
| Fallback contract | `usedAI == false` marks a retrieval-only result → label as `Keyword suggestions` |
| Cancellation | `recommend` throws `CancellationError` within ~0.1 s of Task cancellation, verified on-device |
| Fidelity | Pipeline moved verbatim; post-move eval train 0.921 / test 0.844 meanPickScore, 100% acceptable, within run-noise band |
| Notes | Input capped internally at 600 characters (matches the README-synopsis budget); ~3 s/query on an M-series Mac; extraction record in Glyphon repo `docs/ai/003-core-package-extraction/outcome.md` |

## Second-round decisions (2026-07-25, interview continued)

A follow-up session resumed the interview and closed the remaining branches.

### Model-wait presentation (previously the open question)

Selecting **Suggest an Icon…** opens Choose Symbol immediately. The picker sheet gains a
`Suggested for this repository` section that shows an inline loading state while the model
runs; the sheet stays closable and ordinary symbol selection remains available throughout.
Results replace the loading state in place. Neither a menu-side wait nor a separate progress
dialog is used.

### Menu structure

The Repository Icon menu keeps **Choose Symbol…** and adds **Suggest an Icon…**; both open the
same picker sheet. Only Suggest an Icon… starts generation automatically. When the sheet is
opened via Choose Symbol…, the Suggestions section is idle and offers an explicit **Suggest**
button. A model call therefore always corresponds to an explicit user action, and the feature
is discoverable from both the menu and the sheet.

### Suggestion result lifecycle

| Topic | Decision |
| --- | --- |
| Closing the sheet mid-generation | Cancels the in-flight model call. |
| Successful results | Cached in memory per repository for the app session; never persisted to disk. |
| Reopening the sheet | Shows cached results immediately with their source label; the Suggest button becomes **Regenerate**. |
| App relaunch | Cache starts empty; suggestions regenerate on demand. |

### Delivery sequencing

051 ships as a single delivery after the shared package exists: extract Glyphon's pipeline
into the shared recommender package first, then implement automatic detection and the
suggestion flow together in Prowl. A split that shipped model-free automatic detection first
was proposed and rejected: even though detection has no model dependency, one coherent
delivery is preferred over touching Repository Settings twice. 051 was therefore blocked on
the package extraction, which proceeded as separate Glyphon-side work using the prepared
handoff prompt. The prerequisite is now met — see the section below for the published
coordinates.

## Implementation consequences

- `RepositoryAppearance` needs distinct manual, detected, and suppressed state so delayed results
  cannot overwrite a clear or manual choice.
- `RepositoryIconSource` / rendering needs a non-template detected-SVG representation without
  changing existing user SVG tint behavior.
- Removal must selectively clean automatic artifacts/state while preserving manual appearance.
- The detector must remain bounded, cancellable, path-contained, and image-validated before it
  copies a candidate through `RepositoryIconAssetStore`.
