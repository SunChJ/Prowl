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

  @Test func replacesAnOlderVersionOfTheSamePathImmediately() {
    var cache = TranscriptFragmentCache()
    _ = cache.fragments(for: key("/tmp/busy.jsonl", 100)) { ["v1"] }
    _ = cache.fragments(for: key("/tmp/busy.jsonl", 101)) { ["v2"] }

    #expect(cache.count == 1)
  }

  @Test func dropsAnOlderVersionWhenLoadingTheNewVersionFails() {
    var cache = TranscriptFragmentCache()
    _ = cache.fragments(for: key("/tmp/busy.jsonl", 100)) { ["v1"] }

    #expect(cache.fragments(for: key("/tmp/busy.jsonl", 101)) { nil } == nil)
    #expect(cache.count == 0)
  }

  @Test func evictsTheLeastRecentlyUsedEntryAtCapacity() {
    var cache = TranscriptFragmentCache(maxEntryCount: 2, maxRetainedUTF8Bytes: .max)
    let first = key("/tmp/first.jsonl", 100)
    let second = key("/tmp/second.jsonl", 100)
    let third = key("/tmp/third.jsonl", 100)
    _ = cache.fragments(for: first) { ["first"] }
    _ = cache.fragments(for: second) { ["second"] }
    _ = cache.fragments(for: first) { ["not reached"] }
    _ = cache.fragments(for: third) { ["third"] }

    var firstReloads = 0
    _ = cache.fragments(for: first) {
      firstReloads += 1
      return ["first reloaded"]
    }
    var secondReloads = 0
    _ = cache.fragments(for: second) {
      secondReloads += 1
      return ["second reloaded"]
    }

    #expect(firstReloads == 0, "A cache hit must make the entry most recently used")
    #expect(secondReloads == 1, "The least recently used entry must be evicted first")
  }

  @Test func doesNotRetainAnEntryLargerThanTheByteBudget() {
    var cache = TranscriptFragmentCache(maxEntryCount: 10, maxRetainedUTF8Bytes: 3)
    let target = key("/tmp/large.jsonl", 100)
    var loads = 0

    for _ in 0..<2 {
      _ = cache.fragments(for: target) {
        loads += 1
        return ["four"]
      }
    }

    #expect(loads == 2)
    #expect(cache.count == 0)
  }

  @Test func byteBudgetEvictsTheLeastRecentlyUsedEntry() {
    var cache = TranscriptFragmentCache(maxEntryCount: 10, maxRetainedUTF8Bytes: 10)
    let first = key("a", 100)
    let second = key("b", 100)
    let third = key("c", 100)
    _ = cache.fragments(for: first) { ["1234"] }
    _ = cache.fragments(for: second) { ["1234"] }
    _ = cache.fragments(for: first) { ["not reached"] }
    _ = cache.fragments(for: third) { ["1234"] }

    var firstReloads = 0
    _ = cache.fragments(for: first) {
      firstReloads += 1
      return ["1234"]
    }
    var secondReloads = 0
    _ = cache.fragments(for: second) {
      secondReloads += 1
      return ["1234"]
    }

    #expect(firstReloads == 0)
    #expect(secondReloads == 1)
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
