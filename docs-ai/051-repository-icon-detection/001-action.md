# 051 — Repository Icon Detection: Action Log

| | |
| --- | --- |
| **Status** | Implemented (single delivery: automatic detection + Suggest an Icon) |
| **Anchor date** | 2026-07-25 |
| **Primary PRs** | — (filled on merge) |
| **Depends on** | [GlyphonKit](https://github.com/onevcat/GlyphonKit) `v0.1.0` |

## What shipped

Both halves of the plan landed together, per the delivery-sequencing
decision in [002-design-alignment.md](002-design-alignment.md):

1. **Automatic local icon detection** — newly added repositories and
   plain folders are scanned once, in the background, for a
   high-confidence product icon; a validated hit silently becomes the
   repository icon.
2. **Suggest an Icon…** — an explicit, cancellable, on-device SF Symbol
   recommendation flow in Repository Settings, backed by GlyphonKit.

## Implementation map

### Detection engine

- `supacode/Clients/Repositories/RepositoryIconDetector.swift` — probe
  order Flutter → React Native → Apple → Android → Web, each gated on
  its own positive project signal with fall-through. Apple resolves the
  largest valid raster referenced by the nearest
  `AppIcon.appiconset/Contents.json`; Android takes the highest-density
  `mipmap-*` launcher raster from well-known module layouts (adaptive
  XML is skipped); hybrid kinds probe `ios/` then `android/`; Web walks
  manifest icons → HTML `rel=icon` → `public/`/root favicons → root
  `logo.*`/`icon.*`, rejecting remote/data/query references.
- `supacode/Clients/Repositories/RepositoryIconDetectorScanner.swift` —
  single choke point for traversal and validation: BFS bounded by
  depth, a 5 000-entry budget, and a dependency-directory skip list;
  never follows symlinks; validates candidates (contained in the repo
  after symlink resolution, regular file, ≤ 5 MB, allowed format,
  ImageIO metadata probe within 16–4096 px, SVG sniff + real `NSImage`
  decode) before anything is imported.
- `supacode/Clients/Repositories/RepositoryIconDetectorClient.swift` —
  dependency wrapper; tests inject fixtures, `testValue` finds nothing.

### Lifecycle (RepositoriesFeature)

- `RepositoriesFeature+IconDetection.swift` — spawn/commit/cleanup:
  - Spawn in `openRepositoriesFinished` for repositories newly added in
    the current operation only (`wasAlreadyLoaded`, not restoring),
    capped at 8 per add, utility priority, per-repo cancel ID plus one
    umbrella ID. Workspace containers, suppressed repos, and repos with
    any icon are skipped. A scan that finds nothing ends silently.
  - Commit re-checks every guard (repo exists, setting enabled, icon
    still nil, not suppressed) and otherwise deletes the imported
    asset; success writes `RepositoryIconSource.detectedImage` into
    `@Shared(.repositoryAppearances)`.
  - Removal (`repositoryRemoved` / `removeFailedRepository`) cancels a
    pending scan, deletes the detected asset, clears the suppression
    flag, and preserves user icon/color — a re-added repo scans fresh.
  - Global toggle-off routes `cancelPendingIconDetections` from
    `AppFeature`'s `settingsChanged` through the umbrella cancel ID.

### Model & rendering changes

- `RepositoryIconSource.detectedImage(filename:)`, marker `@detected:`.
  Never tintable — a detected SVG keeps its intrinsic colors, unlike
  user-picked SVGs. `storedImageFilename` unifies file-backed cleanup.
- `RepositoryAppearance.iconDetectionSuppressed` with custom Codable
  (absent key defaults to false; false is omitted on encode). `isEmpty`
  counts the flag so suppression-only entries survive pruning.
- Clear Icon and an icon-removing Reset record suppression in
  `RepositorySettingsFeature`, so an in-flight scan can never resurrect
  a cleared icon.
- `GlobalSettings.detectRepositoryIconsAutomatically` (default true) +
  toggle in Appearance settings ("Repository Icons" section).

### Suggest an Icon (GlyphonKit)

- Dependency: GlyphonKit `upToNextMajor(from: 0.1.0)` added to
  `supacode.xcodeproj` (raw pbxproj, YiTong as the template).
- `supacode/Domain/RepositorySuggestionInput.swift` — input order
  README synopsis → manifest description (`package.json`,
  `pubspec.yaml`, `Cargo.toml`) → display name; the synopsis strips
  front matter, badges, fenced code, HTML, and link targets before a
  600-character cap (GlyphonKit's own prompt budget).
- `supacode/Clients/Repositories/RepositorySymbolSuggestionClient.swift`
  — actor-backed session cache per repository plus lazy one-time
  database load; `generate` maps `SymbolRecommendation` (symbol, 4
  alternates, reason, `usedAI`) into `RepositorySymbolSuggestions`.
- `RepositorySettingsFeature` — `SymbolSuggestionsPhase`
  (idle/loading/loaded/failed); Choose Symbol… opens the sheet and only
  surfaces a cached run; Suggest an Icon… opens it and starts (or
  resolves) a run; Regenerate bypasses the cache; closing the sheet
  cancels in-flight generation (GlyphonKit throws `CancellationError`
  within ~0.1 s) and resets a transient loading state.
- UI: `RepositorySymbolSuggestionsSection` renders the
  "Suggested for this repository" block inside the shared
  `TabIconPickerView` via a new optional injection slot; results show
  the primary + 4 alternates, the reason, and a source label —
  retrieval-only fallbacks are labeled `Keyword suggestions`. Tapping a
  suggestion fills the symbol field; nothing persists until Done.

### Open In additions

`WorktreeProjectKind` gains first-class `flutter` / `reactNative`
detection (manifest-positive signals, checked before Apple/Android) and
their documented editor preferences (Flutter: Android Studio → IntelliJ
→ VS Code family; RN: VS Code family → WebStorm → Android Studio).

## Verification

- `make check` clean; `make build-app` and the full `make test` suite
  green (see PR).
- New suites: `RepositoryIconDetectorTests` (fixture-driven probes,
  validation, symlink escape, skip list), 
  `RepositoriesFeatureIconDetectionTests` (spawn eligibility, commit
  guards, removal cleanup), `RepositorySettingsSuggestionsTests`
  (suggest/cache/regenerate/cancel), `RepositorySuggestionInputTests`
  (markdown cleaning, source order), plus extended
  `WorktreeProjectKindTests`, `RepositoryIconSourceTests`,
  `RepositoryAppearanceTests`, and updated
  `RepositorySettingsAppearanceTests` for suppression semantics.
- Real model output is not exercised in CI: GlyphonKit's pipeline is
  eval-guarded in its own repository (post-move train 0.921 / test
  0.844 meanPickScore), and Prowl's reducer tests treat the client as a
  fixture boundary.

## Follow-up (same day): more kinds and a generic tier

Requested by onevcat after the initial implementation:

- **Unity** became a `WorktreeProjectKind` for Automatic Open In
  (Rider → VS Code family). The signal is
  `ProjectSettings/ProjectVersion.txt` at the root **or one folder
  down** — SDK-style repos (e.g. UniWebView) keep the Unity project
  beside tooling manifests whose markers (Gemfile, root `.sln` files
  Unity generates) would otherwise win. No icon probe: Unity serializes
  its icon inside `ProjectSettings.asset`, which has no extractable
  image with acceptable confidence.
- **Icon Composer `.icon` bundles** are now the first Apple probe. The
  format is layered (background fill + glass layers + per-appearance
  variants), so single-layer extraction would misrepresent it; instead
  the bundle is flattened by the system QuickLook thumbnail pipeline
  (`.thumbnail` representation only — machines without the QL support
  fall through to the asset-catalog probe). Renderer is injected so
  tests stay off the system pipeline.
- **Tauri**: `src-tauri/tauri.conf.json` (v1 and v2 shapes) declares
  its bundle icons explicitly; the conventional flat `icon.png` is
  preferred. Detector-only — Tauri's best editor is the VS Code family,
  which the generic Open In fallback already reaches.
- **`package.json` `"icon"`** (VS Code extensions and friends) became
  step 0 of the web probe — an explicit declaration outranking every
  convention-based source.
- **Generic fallback tier** (product decision, superseding the plan's
  "defer root logo.*" stance): when no kind probe yields a candidate,
  accept `appicon`/`app-icon`/`icon`/`logo` × `svg`/`png`/`webp` at the
  root, `assets/`, or `.github/` — gated by a **near-square aspect
  check (≤ 1.5:1)** that rejects wordmark logos and social banners,
  which was the original precision concern behind deferring this tier.
- `RepositoryIconDetector.detect` became `async` (QuickLook render);
  the client surface was already async, so only tests changed shape.

## Deviations from the plan

- No pending-scan bookkeeping in `State`: cancellation uses a shared
  umbrella effect ID plus per-repo IDs instead of a tracked set, which
  keeps `openRepositoriesFinished` behavior invisible to unrelated
  reducer tests.
- "Disabling cancels pending work" is implemented as umbrella
  cancellation from `AppFeature` *and* a commit-time guard; a scan
  finishing in the gap discards its result and deletes the asset.
- Suggest an Icon while results already exist re-presents the existing
  run instead of regenerating (Regenerate is the explicit fresh-run
  path) — matches the session-cache decision.
