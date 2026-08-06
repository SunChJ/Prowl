import Foundation
import Testing

@testable import supacode

struct AgentScreenFixtureCorpusTests {
  @Test func initialCorpusCoversClaudeAndCodexLifecycleStates() throws {
    let fixtures = try AgentScreenFixtureCorpus.load()

    for agent in [DetectedAgent.claude, .codex] {
      let states =
        fixtures
        .filter { $0.agent == agent && !$0.isQuarantined }
        .map(\.expectedState)
      #expect(states.contains(.blocked))
      #expect(states.contains(.working))
      #expect(states.contains(.idle))
    }

    #expect(
      fixtures.contains {
        $0.agent == .claude
          && $0.isQuarantined
          && $0.expectedState == .unknown
          && $0.currentState == .idle
      }
    )
  }

  @Test func capturedFixturesMatchCurrentDetector() throws {
    let fixtures = try AgentScreenFixtureCorpus.load()

    #expect(!fixtures.isEmpty, "The captured screen corpus must not be empty.")
    for fixture in fixtures {
      #expect(
        fixture.text == AgentScreenFixtureCorpus.canonicalTail(fixture.text),
        "Fixture is not the canonical 24-non-empty-line detector tail: \(fixture.relativePath)"
      )

      let actualState = fixture.agent.detectState(in: fixture.text)
      let mismatchMessage =
        "Fixture \(fixture.relativePath) expected \(fixture.currentState.rawValue), got \(actualState.rawValue)"
      #expect(actualState == fixture.currentState, Comment(rawValue: mismatchMessage))

      if fixture.isQuarantined {
        #expect(
          fixture.expectedState != fixture.currentState,
          "Quarantined fixture no longer describes a misdetection: \(fixture.relativePath)"
        )
        #expect(
          fixture.metadata.issue != nil,
          "Quarantined fixture must link an issue: \(fixture.relativePath)"
        )
      } else {
        #expect(fixture.expectedState == fixture.currentState)
        #expect(fixture.metadata.issue == nil)
      }
    }
  }
}

private enum AgentScreenFixtureCorpus {
  static let recentNonEmptyLineLimit = 24
  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "Fixtures/AgentScreenDetection", directoryHint: .isDirectory)

  static func load() throws -> [AgentScreenFixture] {
    let fileManager = FileManager.default
    guard
      let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      throw CorpusError("Fixture root is unavailable: \(root.path())")
    }

    let urls = enumerator.compactMap { $0 as? URL }
    let screenURLs =
      urls
      .filter { $0.pathExtension == "txt" }
      .sorted { $0.path() < $1.path() }
    let metadataURLs = Set(urls.filter { $0.lastPathComponent.hasSuffix(".metadata.json") })

    var consumedMetadataURLs: Set<URL> = []
    let fixtures = try screenURLs.map { screenURL in
      let fixture = try loadFixture(at: screenURL)
      consumedMetadataURLs.insert(fixture.metadataURL)
      return fixture
    }

    let orphanedMetadata = metadataURLs.subtracting(consumedMetadataURLs)
    guard orphanedMetadata.isEmpty else {
      throw CorpusError(
        "Metadata without a matching screen fixture: \(orphanedMetadata.map(\.lastPathComponent).sorted())"
      )
    }
    return fixtures
  }

  static func canonicalTail(_ content: String) -> String {
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var remainingNonEmptyLines = recentNonEmptyLineLimit
    var startIndex = lines.startIndex

    for index in lines.indices.reversed() {
      guard !lines[index].trimmingCharacters(in: .whitespaces).isEmpty else { continue }
      remainingNonEmptyLines -= 1
      if remainingNonEmptyLines == 0 {
        startIndex = index
        break
      }
    }
    return lines[startIndex...].joined(separator: "\n")
  }

  private static func loadFixture(at screenURL: URL) throws -> AgentScreenFixture {
    let relativePath = relativePath(for: screenURL)
    let components = relativePath.split(separator: "/").map(String.init)
    let layout = try FixtureLayout(components: components, relativePath: relativePath)
    let metadataURL = screenURL.deletingPathExtension().appendingPathExtension("metadata.json")

    guard FileManager.default.fileExists(atPath: metadataURL.path()) else {
      throw CorpusError("Missing metadata for \(relativePath)")
    }

    let metadata = try JSONDecoder().decode(
      AgentScreenFixtureMetadata.self,
      from: Data(contentsOf: metadataURL)
    )
    try validate(metadata: metadata, layout: layout, relativePath: relativePath)

    return AgentScreenFixture(
      relativePath: relativePath,
      metadataURL: metadataURL,
      agent: layout.agent,
      expectedState: layout.expectedState,
      currentState: layout.currentState,
      isQuarantined: layout.isQuarantined,
      text: try String(contentsOf: screenURL, encoding: .utf8),
      metadata: metadata
    )
  }

  private static func validate(
    metadata: AgentScreenFixtureMetadata,
    layout: FixtureLayout,
    relativePath: String
  ) throws {
    guard metadata.schemaVersion == 1 else {
      throw CorpusError("Unsupported metadata schema for \(relativePath): \(metadata.schemaVersion)")
    }
    guard metadata.cliVersion == layout.cliVersion else {
      throw CorpusError("CLI version metadata does not match path for \(relativePath)")
    }
    guard metadata.captureSource == "prowl-read-detection" else {
      throw CorpusError("Invalid capture source for \(relativePath): \(metadata.captureSource)")
    }
    guard ISO8601DateFormatter().date(from: metadata.capturedAt) != nil else {
      throw CorpusError("Invalid capture timestamp for \(relativePath): \(metadata.capturedAt)")
    }
    guard metadata.terminal.columns > 0, metadata.terminal.rows > 0 else {
      throw CorpusError("Invalid terminal geometry for \(relativePath)")
    }
    guard !metadata.redactions.isEmpty else {
      throw CorpusError("Missing redaction summary for \(relativePath)")
    }
  }

  private static func relativePath(for url: URL) -> String {
    let path = String(url.path().dropFirst(root.path().count))
    return path.hasPrefix("/") ? String(path.dropFirst()) : path
  }
}

private struct AgentScreenFixture {
  let relativePath: String
  let metadataURL: URL
  let agent: DetectedAgent
  let expectedState: AgentRawState
  let currentState: AgentRawState
  let isQuarantined: Bool
  let text: String
  let metadata: AgentScreenFixtureMetadata
}

private struct AgentScreenFixtureMetadata: Decodable {
  struct Terminal: Decodable {
    let columns: Int
    let rows: Int
  }

  let schemaVersion: Int
  let capturedAt: String
  let cliVersion: String
  let captureSource: String
  let terminal: Terminal
  let redactions: [String]
  let issue: String?

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case capturedAt = "captured_at"
    case cliVersion = "cli_version"
    case captureSource = "capture_source"
    case terminal
    case redactions
    case issue
  }
}

private struct FixtureLayout {
  let agent: DetectedAgent
  let cliVersion: String
  let expectedState: AgentRawState
  let currentState: AgentRawState
  let isQuarantined: Bool

  init(components: [String], relativePath: String) throws {
    guard components.count == 4 || components.count == 6 else {
      throw CorpusError("Invalid fixture path layout: \(relativePath)")
    }
    guard let agent = DetectedAgent(rawValue: components[0]) else {
      throw CorpusError("Unknown runtime in fixture path: \(relativePath)")
    }
    self.agent = agent
    self.cliVersion = components[1]

    if components.count == 4 {
      guard let state = AgentRawState(rawValue: components[2]) else {
        throw CorpusError("Invalid expected state in fixture path: \(relativePath)")
      }
      self.expectedState = state
      self.currentState = state
      self.isQuarantined = false
    } else {
      guard components[2] == "known-misdetection",
        let expectedState = AgentRawState(rawValue: components[3]),
        let currentState = AgentRawState(rawValue: components[4])
      else {
        throw CorpusError("Invalid quarantine path layout: \(relativePath)")
      }
      self.expectedState = expectedState
      self.currentState = currentState
      self.isQuarantined = true
    }
  }
}

private struct CorpusError: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}
