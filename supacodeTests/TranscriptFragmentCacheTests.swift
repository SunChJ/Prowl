import Foundation
import Testing

@testable import supacode

/// Fingerprint matching re-reads the same transcript tails every time a pane's
/// session cache expires. `TranscriptFragmentCache` replays the parsed result
/// for unchanged files; these tests pin both the reuse and the bounding.
struct TranscriptFragmentCacheTests {
  private func key(_ path: String, _ secondsSinceEpoch: TimeInterval) -> TranscriptFragmentCache.Key {
    TranscriptFragmentCache.Key(path: path, modifiedAt: Date(timeIntervalSince1970: secondsSinceEpoch))
  }

  @Test func reusesFragmentsForAnUnchangedFile() {
    var cache = TranscriptFragmentCache()
    var loads = 0
    let target = key("/tmp/a.jsonl", 100)

    let first = cache.fragments(for: target) {
      loads += 1
      return ["parsed fragment"]
    }
    let second = cache.fragments(for: target) {
      loads += 1
      return ["should not be reached"]
    }

    #expect(loads == 1)
    #expect(first == ["parsed fragment"])
    #expect(second == ["parsed fragment"])
  }

  @Test func reloadsWhenTheFileIsAppendedTo() {
    var cache = TranscriptFragmentCache()
    var loads = 0

    _ = cache.fragments(for: key("/tmp/a.jsonl", 100)) {
      loads += 1
      return ["old"]
    }
    let updated = cache.fragments(for: key("/tmp/a.jsonl", 101)) {
      loads += 1
      return ["new"]
    }

    #expect(loads == 2)
    #expect(updated == ["new"])
  }

  @Test func doesNotCacheAnUnreadableTail() {
    var cache = TranscriptFragmentCache()
    var loads = 0
    let target = key("/tmp/gone.jsonl", 100)

    let missing = cache.fragments(for: target) {
      loads += 1
      return nil
    }
    let recovered = cache.fragments(for: target) {
      loads += 1
      return ["now readable"]
    }

    // Caching the failure would keep a briefly unreadable transcript excluded
    // from every later match.
    #expect(loads == 2)
    #expect(missing == nil)
    #expect(recovered == ["now readable"])
  }

  @Test func pruneDropsOnlyEntriesNotConsultedSinceTheLastPrune() {
    var cache = TranscriptFragmentCache()
    let stable = key("/tmp/stable.jsonl", 100)
    let superseded = key("/tmp/busy.jsonl", 100)
    _ = cache.fragments(for: stable) { ["stable"] }
    _ = cache.fragments(for: superseded) { ["v1"] }
    #expect(cache.count == 2)

    cache.pruneUnconsulted()
    #expect(cache.count == 2, "Both were consulted in this round, so both survive")

    // Next round: the busy transcript is appended to, so its old key is never
    // consulted again and must not accumulate.
    _ = cache.fragments(for: stable) { ["stable"] }
    _ = cache.fragments(for: key("/tmp/busy.jsonl", 101)) { ["v2"] }
    cache.pruneUnconsulted()

    #expect(cache.count == 2)
    var loads = 0
    _ = cache.fragments(for: superseded) {
      loads += 1
      return ["v1 again"]
    }
    #expect(loads == 1, "The superseded entry was evicted, so it must reload")
  }

  @Test func bestMatchServesASecondCallFromTheCache() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "prowl-fragment-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let firstURL = root.appending(path: "first.jsonl")
    let secondURL = root.appending(path: "second.jsonl")
    try #"{"type":"user","message":{"content":"Refactor authentication middleware without changing its API."}}"#
      .write(to: firstURL, atomically: true, encoding: .utf8)
    try #"{"type":"user","message":{"content":"Investigate the unrelated rendering regression."}}"#
      .write(to: secondURL, atomically: true, encoding: .utf8)

    let modifiedAt = Date(timeIntervalSince1970: 1_000)
    let candidates = [
      AgentSessionCandidate(
        session: AgentSession(id: "first", transcriptPath: firstURL, source: .recentFile),
        modifiedAt: modifiedAt
      ),
      AgentSessionCandidate(
        session: AgentSession(id: "second", transcriptPath: secondURL, source: .recentFile),
        modifiedAt: modifiedAt
      ),
    ]
    let activeText = "❯ Refactor authentication middleware without changing its API."

    var cache = TranscriptFragmentCache()
    let first = AgentSessionFingerprintMatcher.bestMatch(
      activeText: activeText,
      candidates: candidates,
      fragments: &cache
    )
    #expect(first?.session.id == "first")

    // Deleting the transcripts makes a re-read impossible, so a second match on
    // the same keys can only succeed by replaying the cached fragments.
    try FileManager.default.removeItem(at: firstURL)
    try FileManager.default.removeItem(at: secondURL)

    let cached = AgentSessionFingerprintMatcher.bestMatch(
      activeText: activeText,
      candidates: candidates,
      fragments: &cache
    )
    #expect(cached?.session.id == "first")

    // A cacheless call over the same candidates now has nothing to read, which
    // confirms the previous call really was served from the cache.
    #expect(AgentSessionFingerprintMatcher.bestMatch(activeText: activeText, candidates: candidates) == nil)
  }
}
