import Foundation
import Testing

@testable import supacode

extension PerformanceBenchmarks {
  /// Tracks absolute changed-screen classification cost over the same sanitized
  /// Claude/Codex capture corpus used by the end-to-end regression test.
  @Suite
  struct ScreenHeuristicsBenchmarks {
    @Test func capturedCorpusChangedFrameCost() throws {
      let fixtures = try Self.loadFixtures()
      let repeats = BenchmarkMeasurement.isFullMode ? 20 : 2
      var checksum = 0

      let median = BenchmarkMeasurement.repeatedMedian {
        var iterationChecksum = 0
        for _ in 0..<repeats {
          for fixture in fixtures {
            iterationChecksum &+= fixture.agent.detectState(in: fixture.text).rawValue.utf8.count
          }
        }
        checksum &+= iterationChecksum
      }

      #expect(checksum > 0)
      BenchmarkMeasurement.reportAbsolute(
        suite: "ScreenHeuristics",
        name: "captured-claude-codex-corpus",
        median: median,
        normalizingBy: repeats
      )
    }

    private static func loadFixtures() throws -> [(agent: DetectedAgent, text: String)] {
      let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures/AgentScreenDetection", directoryHint: .isDirectory)
      guard
        let enumerator = FileManager.default.enumerator(
          at: root,
          includingPropertiesForKeys: [.isRegularFileKey],
          options: [.skipsHiddenFiles]
        )
      else {
        throw ScreenHeuristicsBenchmarkError.fixtureRootUnavailable
      }

      return
        try enumerator
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "txt" }
        .sorted { $0.path() < $1.path() }
        .map { url in
          let relativePath = String(url.path().dropFirst(root.path().count))
          guard let runtime = relativePath.split(separator: "/").first,
            let agent = DetectedAgent(rawValue: String(runtime))
          else {
            throw ScreenHeuristicsBenchmarkError.invalidFixturePath(relativePath)
          }
          return (agent, try String(contentsOf: url, encoding: .utf8))
        }
    }
  }
}

private enum ScreenHeuristicsBenchmarkError: Error {
  case fixtureRootUnavailable
  case invalidFixturePath(String)
}
