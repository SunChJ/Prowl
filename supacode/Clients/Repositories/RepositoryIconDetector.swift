import AppKit
import Foundation
import ImageIO

/// A validated icon file found inside a repository, plus the project
/// evidence that made it trustworthy. The detector never mutates the
/// repository or settings — committing a candidate is the reducer's job.
nonisolated struct RepositoryIconCandidate: Equatable, Sendable {
  enum Evidence: Equatable, Sendable {
    case appleAssetCatalog
    case androidLauncher
    case webAsset
  }

  let imageURL: URL
  let evidence: Evidence
}

/// Evidence-based local probe for a repository's own product icon.
///
/// Kinds are tried in a fixed order — Flutter, React Native, Apple,
/// Android, Web — and each kind requires its own positive project
/// signal before probing, falling through when it yields no valid
/// candidate. Traversal is bounded (depth, entry budget, skip list,
/// no symlinks) so the scan stays cheap even in huge repositories,
/// and every candidate is validated (contained in the repo, regular
/// file, bounded size, decodable) before being returned.
nonisolated enum RepositoryIconDetector {

  static func detect(at rootURL: URL, fileManager: FileManager = .default) -> RepositoryIconCandidate? {
    let scanner = Scanner(rootURL: rootURL, fileManager: fileManager)
    let names = scanner.entryNames(of: rootURL)
    guard !names.isEmpty else { return nil }

    if names.contains("pubspec.yaml"), WorktreeProjectKind.pubspecDeclaresFlutter(in: rootURL),
      let candidate = probeHybridShells(scanner: scanner)
    {
      return candidate
    }
    if names.contains("package.json"),
      names.contains("ios") || names.contains("android"),
      WorktreeProjectKind.packageJSONDependsOnReactNative(in: rootURL),
      let candidate = probeHybridShells(scanner: scanner)
    {
      return candidate
    }
    if names.contains(where: {
      $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace")
    }) || names.contains("package.swift") || names.contains("project.swift"),
      let imageURL = probeAppleCatalog(under: scanner.rootURL, scanner: scanner)
    {
      return RepositoryIconCandidate(imageURL: imageURL, evidence: .appleAssetCatalog)
    }
    if names.contains("settings.gradle") || names.contains("settings.gradle.kts")
      || names.contains("build.gradle") || names.contains("build.gradle.kts")
      || names.contains("gradlew"),
      let imageURL = probeAndroidLauncher(under: scanner.rootURL, scanner: scanner)
    {
      return RepositoryIconCandidate(imageURL: imageURL, evidence: .androidLauncher)
    }
    if names.contains("package.json") || names.contains("index.html"),
      let imageURL = probeWebAsset(scanner: scanner)
    {
      return RepositoryIconCandidate(imageURL: imageURL, evidence: .webAsset)
    }
    return nil
  }

  // MARK: - Hybrid (Flutter / React Native)

  /// Both hybrid kinds resolve the same way: the iOS shell's asset
  /// catalog first, then the Android shell's launcher raster.
  private static func probeHybridShells(scanner: Scanner) -> RepositoryIconCandidate? {
    let iosShell = scanner.rootURL.appending(path: "ios", directoryHint: .isDirectory)
    if let imageURL = probeAppleCatalog(under: iosShell, scanner: scanner) {
      return RepositoryIconCandidate(imageURL: imageURL, evidence: .appleAssetCatalog)
    }
    let androidShell = scanner.rootURL.appending(path: "android", directoryHint: .isDirectory)
    if let imageURL = probeAndroidLauncher(under: androidShell, scanner: scanner) {
      return RepositoryIconCandidate(imageURL: imageURL, evidence: .androidLauncher)
    }
    return nil
  }

  // MARK: - Apple

  /// Finds `AppIcon.appiconset` catalogs under `directory` (nearest to
  /// the root first, then lexicographic) and returns the largest valid
  /// raster referenced by the first catalog that yields one.
  private static func probeAppleCatalog(under directory: URL, scanner: Scanner) -> URL? {
    let catalogs = scanner.findDirectories(named: "appicon.appiconset", under: directory, maxDepth: 6)
    for catalog in catalogs {
      if let imageURL = largestValidImage(inAppIconSet: catalog, scanner: scanner) {
        return imageURL
      }
    }
    return nil
  }

  private static func largestValidImage(inAppIconSet catalog: URL, scanner: Scanner) -> URL? {
    let manifestURL = catalog.appending(path: "Contents.json", directoryHint: .notDirectory)
    guard let data = scanner.boundedContents(of: manifestURL, limit: 1024 * 1024),
      let manifest = try? JSONDecoder().decode(AppIconSetManifest.self, from: data)
    else {
      return nil
    }
    let ranked =
      manifest.images
      .compactMap { entry -> (filename: String, pixels: Int)? in
        guard let filename = entry.filename, !filename.isEmpty else { return nil }
        return (filename, pixelArea(size: entry.size, scale: entry.scale))
      }
      .sorted { lhs, rhs in
        lhs.pixels == rhs.pixels ? lhs.filename < rhs.filename : lhs.pixels > rhs.pixels
      }
    for entry in ranked {
      let imageURL = catalog.appending(path: entry.filename, directoryHint: .notDirectory)
      if scanner.validatedImage(at: imageURL) != nil {
        return imageURL
      }
    }
    return nil
  }

  /// `size` is `"WxH"`, `scale` is `"Nx"`; a single-size catalog entry
  /// may omit the scale. Unparseable entries rank last, not out.
  private static func pixelArea(size: String?, scale: String?) -> Int {
    guard let size else { return 0 }
    let dimensions = size.lowercased().split(separator: "x").compactMap { Double($0) }
    guard dimensions.count == 2 else { return 0 }
    let scaleFactor = scale.flatMap { Double($0.lowercased().replacing("x", with: "")) } ?? 1
    return Int(dimensions[0] * scaleFactor * dimensions[1] * scaleFactor)
  }

  // MARK: - Android

  private static let androidDensityDirectories = [
    "mipmap-xxxhdpi", "mipmap-xxhdpi", "mipmap-xhdpi", "mipmap-hdpi", "mipmap-mdpi",
  ]
  private static let androidLauncherFilenames = [
    "ic_launcher.png", "ic_launcher.webp", "ic_launcher_round.png", "ic_launcher_round.webp",
  ]

  /// Probes well-known module layouts (`<module>/src/main/res` and
  /// `src/main/res`) for a standard launcher raster, highest density
  /// first. Adaptive-icon XML has no raster to import and is skipped.
  private static func probeAndroidLauncher(under directory: URL, scanner: Scanner) -> URL? {
    var resDirectories: [URL] = [
      directory.appending(path: "src/main/res", directoryHint: .isDirectory)
    ]
    for module in scanner.subdirectoryNames(of: directory) {
      resDirectories.append(
        directory.appending(path: "\(module)/src/main/res", directoryHint: .isDirectory)
      )
    }
    for resDirectory in resDirectories where scanner.directoryExists(resDirectory) {
      for density in androidDensityDirectories {
        for filename in androidLauncherFilenames {
          let imageURL =
            resDirectory
            .appending(path: density, directoryHint: .isDirectory)
            .appending(path: filename, directoryHint: .notDirectory)
          if scanner.validatedImage(at: imageURL) != nil {
            return imageURL
          }
        }
      }
    }
    return nil
  }

  // MARK: - Web

  /// Source order: web app manifest, explicit HTML `rel=icon`, then
  /// conventional favicon/logo files. A static folder (no
  /// `package.json`) qualifies only via a root `index.html`.
  private static func probeWebAsset(scanner: Scanner) -> URL? {
    let root = scanner.rootURL
    let publicDirectory = root.appending(path: "public", directoryHint: .isDirectory)
    let searchDirectories = [root, publicDirectory]

    for directory in searchDirectories {
      for name in ["manifest.webmanifest", "site.webmanifest", "manifest.json"] {
        let manifestURL = directory.appending(path: name, directoryHint: .notDirectory)
        if let imageURL = largestValidManifestIcon(at: manifestURL, baseDirectory: directory, scanner: scanner) {
          return imageURL
        }
      }
    }
    for directory in searchDirectories {
      let htmlURL = directory.appending(path: "index.html", directoryHint: .notDirectory)
      if let imageURL = linkedIcon(inHTMLAt: htmlURL, baseDirectory: directory, scanner: scanner) {
        return imageURL
      }
    }
    for directory in [publicDirectory, root] {
      for name in ["favicon.svg", "favicon.png", "favicon.ico"] {
        let imageURL = directory.appending(path: name, directoryHint: .notDirectory)
        if scanner.validatedImage(at: imageURL) != nil {
          return imageURL
        }
      }
    }
    for name in ["logo.svg", "logo.png", "icon.svg", "icon.png"] {
      let imageURL = root.appending(path: name, directoryHint: .notDirectory)
      if scanner.validatedImage(at: imageURL) != nil {
        return imageURL
      }
    }
    return nil
  }

  private static func largestValidManifestIcon(
    at manifestURL: URL,
    baseDirectory: URL,
    scanner: Scanner
  ) -> URL? {
    guard let data = scanner.boundedContents(of: manifestURL, limit: 512 * 1024),
      let manifest = try? JSONDecoder().decode(WebManifest.self, from: data),
      let icons = manifest.icons
    else {
      return nil
    }
    let ranked =
      icons
      .compactMap { icon -> (src: String, pixels: Int)? in
        guard let src = icon.src, !src.isEmpty else { return nil }
        return (src, declaredPixelArea(sizes: icon.sizes, source: src))
      }
      .sorted { lhs, rhs in
        lhs.pixels == rhs.pixels ? lhs.src < rhs.src : lhs.pixels > rhs.pixels
      }
    for icon in ranked {
      let references = resolveWebReferences(icon.src, baseDirectory: baseDirectory, scanner: scanner)
      for imageURL in references where scanner.validatedImage(at: imageURL) != nil {
        return imageURL
      }
    }
    return nil
  }

  /// `sizes` is space-separated `"WxH"` tokens or `"any"` (scalable —
  /// ranked like a large raster so SVG icons win over small PNGs).
  private static func declaredPixelArea(sizes: String?, source: String) -> Int {
    let scalableRank = 512 * 512
    guard let sizes, !sizes.isEmpty else {
      return source.lowercased().hasSuffix(".svg") ? scalableRank : 0
    }
    var best = 0
    for token in sizes.lowercased().split(separator: " ") {
      if token == "any" {
        best = max(best, scalableRank)
        continue
      }
      let dimensions = token.split(separator: "x").compactMap { Int($0) }
      if dimensions.count == 2 {
        best = max(best, dimensions[0] * dimensions[1])
      }
    }
    return best
  }

  /// Extracts the first `<link rel="icon" …>` (or `shortcut icon`)
  /// href from a bounded read of the HTML. A regex scan is enough —
  /// this is an existence probe, not a browser.
  private static func linkedIcon(inHTMLAt htmlURL: URL, baseDirectory: URL, scanner: Scanner) -> URL? {
    guard let data = scanner.boundedContents(of: htmlURL, limit: 256 * 1024),
      let html = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    let linkTag = /<link\b[^>]*>/.ignoresCase()
    let relAttribute = /rel\s*=\s*["'](?:shortcut\s+)?icon["']/.ignoresCase()
    let hrefAttribute = /href\s*=\s*["']([^"']+)["']/.ignoresCase()
    for match in html.matches(of: linkTag) {
      let tag = String(match.output)
      guard tag.contains(relAttribute),
        let href = tag.firstMatch(of: hrefAttribute).map({ String($0.output.1) })
      else {
        continue
      }
      let references = resolveWebReferences(href, baseDirectory: baseDirectory, scanner: scanner)
      for imageURL in references where scanner.validatedImage(at: imageURL) != nil {
        return imageURL
      }
    }
    return nil
  }

  /// Maps a manifest/HTML reference onto candidate local files. Remote
  /// URLs, data URIs, and query-string tricks are rejected outright;
  /// root-relative paths are tried against the repo root and `public/`.
  private static func resolveWebReferences(
    _ reference: String,
    baseDirectory: URL,
    scanner: Scanner
  ) -> [URL] {
    let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains(":"), !trimmed.contains("?"), !trimmed.contains("#")
    else {
      return []
    }
    if trimmed.hasPrefix("/") {
      let relative = String(trimmed.dropFirst())
      return [
        scanner.rootURL.appending(path: relative, directoryHint: .notDirectory),
        scanner.rootURL.appending(path: "public/\(relative)", directoryHint: .notDirectory),
      ]
    }
    return [baseDirectory.appending(path: trimmed, directoryHint: .notDirectory)]
  }
}

/// `AppIcon.appiconset/Contents.json` shape — decoded fields only.
nonisolated private struct AppIconSetManifest: Decodable {
  struct Entry: Decodable {
    let filename: String?
    let size: String?
    let scale: String?
  }

  let images: [Entry]
}

/// Web app manifest shape — decoded fields only.
nonisolated private struct WebManifest: Decodable {
  struct Icon: Decodable {
    let src: String?
    let sizes: String?
  }

  let icons: [Icon]?
}
