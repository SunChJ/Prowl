import AppKit
import Foundation
import Testing

@testable import supacode

struct RepositoryIconDetectorTests {
  // MARK: - Fixtures

  private func pngData(width: Int, height: Int) -> Data {
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )
    guard let bitmap, let data = bitmap.representation(using: .png, properties: [:]) else {
      Issue.record("Could not create PNG fixture")
      return Data()
    }
    return data
  }

  private var svgData: Data {
    let svg =
      #"<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">"#
      + #"<rect width="64" height="64" fill="tomato"/></svg>"#
    return Data(svg.utf8)
  }

  private struct ManifestEntry {
    var filename: String
    var size: String
    var scale: String?
  }

  private func appIconSetManifest(_ entries: [ManifestEntry]) -> Data {
    let images = entries.map { entry in
      var image = ["filename": entry.filename, "size": entry.size, "idiom": "mac"]
      if let scale = entry.scale {
        image["scale"] = scale
      }
      return image
    }
    guard let data = try? JSONSerialization.data(withJSONObject: ["images": images]) else {
      Issue.record("Could not encode manifest fixture")
      return Data()
    }
    return data
  }

  private let flutterPubspec = Data("name: demo\ndependencies:\n  flutter:\n    sdk: flutter\n".utf8)
  private let reactNativePackageJSON = Data(
    #"{"name":"demo","dependencies":{"react":"19.0.0","react-native":"0.80.0"}}"#.utf8
  )

  // MARK: - Apple

  @Test func appleCatalogPicksLargestReferencedRaster() throws {
    try withTemporaryProjectDirectory(
      entries: ["App.xcodeproj/"],
      contents: [
        "App/Assets.xcassets/AppIcon.appiconset/Contents.json": appIconSetManifest([
          .init(filename: "small.png", size: "16x16", scale: "1x"),
          .init(filename: "large.png", size: "512x512", scale: "2x"),
        ]),
        "App/Assets.xcassets/AppIcon.appiconset/small.png": pngData(width: 16, height: 16),
        "App/Assets.xcassets/AppIcon.appiconset/large.png": pngData(width: 1024, height: 1024),
      ]
    ) { root in
      let candidate = RepositoryIconDetector.detect(at: root)
      #expect(candidate?.evidence == .appleAssetCatalog)
      #expect(candidate?.imageURL.lastPathComponent == "large.png")
    }
  }

  @Test func appleCatalogFallsBackWhenLargestEntryFileIsMissing() throws {
    try withTemporaryProjectDirectory(
      entries: ["Package.swift"],
      contents: [
        "Sources/App/Assets.xcassets/AppIcon.appiconset/Contents.json": appIconSetManifest([
          .init(filename: "missing.png", size: "512x512", scale: "2x"),
          .init(filename: "present.png", size: "128x128", scale: "1x"),
        ]),
        "Sources/App/Assets.xcassets/AppIcon.appiconset/present.png": pngData(width: 128, height: 128),
      ]
    ) { root in
      #expect(RepositoryIconDetector.detect(at: root)?.imageURL.lastPathComponent == "present.png")
    }
  }

  @Test func appleCatalogWithMalformedManifestYieldsNothing() throws {
    try withTemporaryProjectDirectory(
      entries: ["App.xcodeproj/"],
      contents: [
        "Assets.xcassets/AppIcon.appiconset/Contents.json": Data("not json".utf8),
        "Assets.xcassets/AppIcon.appiconset/icon.png": pngData(width: 64, height: 64),
      ]
    ) { root in
      #expect(RepositoryIconDetector.detect(at: root) == nil)
    }
  }

  @Test func appleCatalogInsideDependencyDirectoryIsIgnored() throws {
    try withTemporaryProjectDirectory(
      entries: ["App.xcodeproj/"],
      contents: [
        "node_modules/pkg/Assets.xcassets/AppIcon.appiconset/Contents.json": appIconSetManifest([
          .init(filename: "icon.png", size: "64x64", scale: "1x")
        ]),
        "node_modules/pkg/Assets.xcassets/AppIcon.appiconset/icon.png": pngData(width: 64, height: 64),
      ]
    ) { root in
      #expect(RepositoryIconDetector.detect(at: root) == nil)
    }
  }

  @Test func nearerAppleCatalogWinsOverDeeperOne() throws {
    try withTemporaryProjectDirectory(
      entries: ["App.xcworkspace/"],
      contents: [
        "Assets.xcassets/AppIcon.appiconset/Contents.json": appIconSetManifest([
          .init(filename: "near.png", size: "64x64", scale: "1x")
        ]),
        "Assets.xcassets/AppIcon.appiconset/near.png": pngData(width: 64, height: 64),
        "Modules/Deep/Assets.xcassets/AppIcon.appiconset/Contents.json": appIconSetManifest([
          .init(filename: "deep.png", size: "1024x1024", scale: "1x")
        ]),
        "Modules/Deep/Assets.xcassets/AppIcon.appiconset/deep.png": pngData(width: 1024, height: 1024),
      ]
    ) { root in
      #expect(RepositoryIconDetector.detect(at: root)?.imageURL.lastPathComponent == "near.png")
    }
  }

  // MARK: - Android

  @Test func androidLauncherPrefersHighestDensity() throws {
    try withTemporaryProjectDirectory(
      entries: ["gradlew", "settings.gradle"],
      contents: [
        "app/src/main/res/mipmap-mdpi/ic_launcher.png": pngData(width: 48, height: 48),
        "app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": pngData(width: 192, height: 192),
      ]
    ) { root in
      let candidate = RepositoryIconDetector.detect(at: root)
      #expect(candidate?.evidence == .androidLauncher)
      #expect(candidate?.imageURL.path(percentEncoded: false).contains("mipmap-xxxhdpi") == true)
    }
  }

  @Test func androidAdaptiveOnlyProjectYieldsNothing() throws {
    try withTemporaryProjectDirectory(
      entries: ["gradlew"],
      contents: [
        "app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml": Data("<adaptive-icon/>".utf8)
      ]
    ) { root in
      #expect(RepositoryIconDetector.detect(at: root) == nil)
    }
  }

  // MARK: - Flutter / React Native

  @Test func flutterPrefersIOSRunnerCatalogOverAndroidLauncher() throws {
    try withTemporaryProjectDirectory(
      entries: [],
      contents: [
        "pubspec.yaml": flutterPubspec,
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json": appIconSetManifest([
          .init(filename: "Icon-App-1024x1024@1x.png", size: "1024x1024", scale: "1x")
        ]),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png":
          pngData(width: 1024, height: 1024),
        "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": pngData(width: 192, height: 192),
      ]
    ) { root in
      let candidate = RepositoryIconDetector.detect(at: root)
      #expect(candidate?.evidence == .appleAssetCatalog)
      #expect(candidate?.imageURL.path(percentEncoded: false).contains("ios/Runner") == true)
    }
  }

  @Test func flutterFallsBackToAndroidLauncher() throws {
    try withTemporaryProjectDirectory(
      entries: [],
      contents: [
        "pubspec.yaml": flutterPubspec,
        "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": pngData(width: 96, height: 96),
      ]
    ) { root in
      #expect(RepositoryIconDetector.detect(at: root)?.evidence == .androidLauncher)
    }
  }

  @Test func pureDartPackageWithoutFlutterYieldsNothing() throws {
    try withTemporaryProjectDirectory(
      entries: [],
      contents: [
        "pubspec.yaml": Data("name: pure_dart\nenvironment:\n  sdk: ^3.0.0\n".utf8),
        "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": pngData(width: 96, height: 96),
      ]
    ) { root in
      #expect(RepositoryIconDetector.detect(at: root) == nil)
    }
  }

  @Test func reactNativeUsesIOSCatalogThenAndroid() throws {
    try withTemporaryProjectDirectory(
      entries: [],
      contents: [
        "package.json": reactNativePackageJSON,
        "ios/Demo/Images.xcassets/AppIcon.appiconset/Contents.json": appIconSetManifest([
          .init(filename: "AppIcon.png", size: "1024x1024")
        ]),
        "ios/Demo/Images.xcassets/AppIcon.appiconset/AppIcon.png": pngData(width: 1024, height: 1024),
      ]
    ) { root in
      let candidate = RepositoryIconDetector.detect(at: root)
      #expect(candidate?.evidence == .appleAssetCatalog)
    }
  }

  // MARK: - Web

  @Test func webManifestIconWinsOverFavicon() throws {
    try withTemporaryProjectDirectory(
      entries: [],
      contents: [
        "package.json": Data(#"{"name":"site"}"#.utf8),
        "public/manifest.json": Data(
          #"{"icons":[{"src":"icons/icon-192.png","sizes":"192x192"},{"src":"icons/icon-512.png","sizes":"512x512"}]}"#
            .utf8
        ),
        "public/icons/icon-192.png": pngData(width: 192, height: 192),
        "public/icons/icon-512.png": pngData(width: 512, height: 512),
        "public/favicon.png": pngData(width: 32, height: 32),
      ]
    ) { root in
      let candidate = RepositoryIconDetector.detect(at: root)
      #expect(candidate?.evidence == .webAsset)
      #expect(candidate?.imageURL.lastPathComponent == "icon-512.png")
    }
  }

  @Test func htmlRelIconIsResolvedAgainstRoot() throws {
    try withTemporaryProjectDirectory(
      entries: [],
      contents: [
        "package.json": Data(#"{"name":"site"}"#.utf8),
        "index.html": Data(
          #"<html><head><link rel="icon" href="/assets/fav.png"></head></html>"#.utf8
        ),
        "assets/fav.png": pngData(width: 64, height: 64),
      ]
    ) { root in
      #expect(RepositoryIconDetector.detect(at: root)?.imageURL.lastPathComponent == "fav.png")
    }
  }

  @Test func staticFolderWithIndexHTMLAndFaviconQualifies() throws {
    try withTemporaryProjectDirectory(
      entries: [],
      contents: [
        "index.html": Data("<html></html>".utf8),
        "favicon.svg": svgData,
      ]
    ) { root in
      let candidate = RepositoryIconDetector.detect(at: root)
      #expect(candidate?.evidence == .webAsset)
      #expect(candidate?.imageURL.lastPathComponent == "favicon.svg")
    }
  }

  @Test func rootLogoIsLastResortForWebProjects() throws {
    try withTemporaryProjectDirectory(
      entries: [],
      contents: [
        "package.json": Data(#"{"name":"site"}"#.utf8),
        "logo.svg": svgData,
      ]
    ) { root in
      #expect(RepositoryIconDetector.detect(at: root)?.imageURL.lastPathComponent == "logo.svg")
    }
  }

  @Test func nonWebProjectIgnoresRootLogo() throws {
    try withTemporaryProjectDirectory(
      entries: ["go.mod"],
      contents: [
        "logo.svg": svgData
      ]
    ) { root in
      #expect(RepositoryIconDetector.detect(at: root) == nil)
    }
  }

  @Test func remoteAndDataIconReferencesAreRejected() throws {
    try withTemporaryProjectDirectory(
      entries: [],
      contents: [
        "package.json": Data(#"{"name":"site"}"#.utf8),
        "index.html": Data(
          #"<html><head><link rel="icon" href="https://cdn.example.com/fav.png"></head></html>"#.utf8
        ),
      ]
    ) { root in
      #expect(RepositoryIconDetector.detect(at: root) == nil)
    }
  }

  // MARK: - Validation

  @Test func undecodableImageIsRejected() throws {
    try withTemporaryProjectDirectory(
      entries: [],
      contents: [
        "package.json": Data(#"{"name":"site"}"#.utf8),
        "logo.png": Data("this is not a png".utf8),
      ]
    ) { root in
      #expect(RepositoryIconDetector.detect(at: root) == nil)
    }
  }

  @Test func oversizedRasterIsRejected() throws {
    try withTemporaryProjectDirectory(
      entries: [],
      contents: [
        "package.json": Data(#"{"name":"site"}"#.utf8),
        "logo.png": pngData(width: 5000, height: 16),
      ]
    ) { root in
      #expect(RepositoryIconDetector.detect(at: root) == nil)
    }
  }

  @Test func symlinkEscapingTheRepositoryIsRejected() throws {
    let fileManager = FileManager.default
    let outside = fileManager.temporaryDirectory
      .appending(path: "outside-\(UUID().uuidString).png")
    try pngData(width: 64, height: 64).write(to: outside)
    defer { try? fileManager.removeItem(at: outside) }
    try withTemporaryProjectDirectory(
      entries: [],
      contents: [
        "package.json": Data(#"{"name":"site"}"#.utf8)
      ]
    ) { root in
      try fileManager.createSymbolicLink(
        at: root.appending(path: "logo.png"),
        withDestinationURL: outside
      )
      #expect(RepositoryIconDetector.detect(at: root) == nil)
    }
  }

  @Test func emptyRepositoryYieldsNothing() throws {
    try withTemporaryProjectDirectory(entries: ["README.md"]) { root in
      #expect(RepositoryIconDetector.detect(at: root) == nil)
    }
  }
}
