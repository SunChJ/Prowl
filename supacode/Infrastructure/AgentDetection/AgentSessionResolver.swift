import Foundation

private nonisolated let agentSessionLogger = SupaLogger("AgentSession")

nonisolated struct AgentSession: Equatable, Sendable {
  enum Source: String, Equatable, Sendable {
    case commandLine = "command_line"
    case openFile = "open_file"
    case processLog = "process_log"
    case storeRecord = "store_record"
    case transcriptMatch = "transcript_match"
    case recentFile = "recent_file"
  }

  enum Confidence: String, Equatable, Sendable {
    case exact
    case high
    case medium
  }

  let id: String
  let transcriptPath: URL?
  let source: Source
  let confidence: Confidence

  init(
    id: String,
    transcriptPath: URL?,
    source: Source,
    confidence: Confidence = .medium
  ) {
    self.id = id
    self.transcriptPath = transcriptPath
    self.source = source
    self.confidence = confidence
  }
}

nonisolated struct AgentSessionCandidate: Equatable, Sendable {
  let session: AgentSession
  let modifiedAt: Date

  /// The sole session active during the process lifetime, or nil when zero or
  /// several distinct sessions qualify. Grouping by session id keeps layouts
  /// with several files per session (Kimi, Cline, Copilot) resolvable.
  nonisolated static func uniqueActiveCandidate(
    _ candidates: [Self],
    processStartedAt: Date,
    clockSkew: TimeInterval = 2
  ) -> Self? {
    let active = candidates.filter { $0.modifiedAt >= processStartedAt.addingTimeInterval(-clockSkew) }
    let sessions = Dictionary(grouping: active) { $0.session.id }
    guard sessions.count == 1, let group = sessions.values.first else { return nil }
    return group.max { $0.modifiedAt < $1.modifiedAt }
  }
}

nonisolated extension [AgentSessionCandidate] {
  /// Store rows queried under two cwd variants can duplicate a session.
  fileprivate func uniquedBySessionID() -> [AgentSessionCandidate] {
    var seen: Set<String> = []
    return filter { seen.insert($0.session.id).inserted }
  }
}

/// Outcome of one resolver call: `isFresh` distinguishes a newly computed
/// resolution from a cache replay during backoff.
nonisolated struct AgentSessionResolution: Sendable {
  let session: AgentSession?
  let isFresh: Bool
}

/// Compatibility shim over the per-agent profiles; the actual rules live in
/// `AgentSessionProfile`.
nonisolated enum AgentSessionPathParser {
  static func parse(path: String, agent: DetectedAgent) -> AgentSession? {
    AgentSessionProfile.profile(for: agent).parsePath(path)
  }
}

actor AgentSessionResolver {
  static let shared = AgentSessionResolver()

  private struct CacheKey: Hashable {
    let pid: pid_t
    let startedAt: Date
  }

  private struct CachedResult {
    let resolvedAt: Date
    let session: AgentSession?
    let usedWideScan: Bool
    var unresolvedStreak: Int = 0
    var provisionalSoleID: String?
  }

  /// Unresolved lookups retry quickly while the narrow scan stays cheap, then
  /// back off exponentially while the pane stays ambiguous; wide fallback
  /// scans (full history trees) start at the slow end. 15 s cap keeps a
  /// permanently ambiguous pane at negligible background cost while still
  /// converging after a session rotation.
  nonisolated static func cacheLifetime(hasSession: Bool, usedWideScan: Bool, unresolvedStreak: Int) -> TimeInterval {
    if hasSession { return 5 }
    let base: TimeInterval = usedWideScan ? 8 : 1
    return min(15, base * TimeInterval(1 << min(unresolvedStreak, 4)))
  }

  /// resolved → ambiguous starts a new unresolved episode at streak 0 (the
  /// first retry keeps the fast pacing, e.g. right after `/clear`); only
  /// consecutive unresolved results escalate the backoff.
  nonisolated static func nextUnresolvedStreak(
    resolvedNow: Bool,
    previousWasUnresolved: Bool,
    previousStreak: Int
  ) -> Int {
    guard !resolvedNow, previousWasUnresolved else { return 0 }
    return previousStreak + 1
  }

  /// A sole process-lifetime candidate is only trusted after two consecutive
  /// resolutions agree on it. A pane that starts in a directory where another
  /// agent is actively writing can otherwise adopt that agent's session during
  /// the sub-second window before its own file lands.
  nonisolated static func confirmSole(
    _ session: AgentSession?,
    previousProvisionalID: String?
  ) -> (session: AgentSession?, provisionalID: String?) {
    guard let session else { return (nil, nil) }
    guard session.confidence == .medium else { return (session, nil) }
    guard session.id == previousProvisionalID else { return (nil, session.id) }
    return (session, nil)
  }

  private var cache: [CacheKey: CachedResult] = [:]
  private let fileManager: FileManager
  private let homeDirectory: URL

  init(
    fileManager: FileManager = .default,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) {
    self.fileManager = fileManager
    self.homeDirectory = homeDirectory
  }

  func resolve(
    identified: IdentifiedAgentProcess,
    workingDirectory: URL?,
    activeText: String,
    configRoot: URL? = nil,
    now: Date = Date()
  ) -> AgentSessionResolution {
    let process = identified.process
    guard let startedAt = ProcessDetection.processStartDate(pid: process.pid) else {
      return AgentSessionResolution(session: nil, isFresh: true)
    }
    let key = CacheKey(pid: process.pid, startedAt: startedAt)
    let cached = cache[key]
    if let cached {
      let lifetime = Self.cacheLifetime(
        hasSession: cached.session != nil,
        usedWideScan: cached.usedWideScan,
        unresolvedStreak: cached.unresolvedStreak
      )
      if now.timeIntervalSince(cached.resolvedAt) < lifetime {
        // Replayed cache hits are not new evidence; consumers must not age
        // their sticky sessions on them.
        return AgentSessionResolution(session: cached.session, isFresh: false)
      }
    }

    let (resolved, usedWideScan) = resolveUncached(
      identified: identified,
      processStartedAt: startedAt,
      workingDirectory: workingDirectory,
      activeText: activeText,
      configRoot: configRoot,
      now: now
    )
    var session = resolved
    var provisionalID: String?
    if let candidate = session, candidate.confidence == .medium {
      if claimedByAnotherProcess(candidate.id, excluding: key) {
        session = nil
      } else {
        (session, provisionalID) = Self.confirmSole(candidate, previousProvisionalID: cached?.provisionalSoleID)
      }
    }
    cache[key] = CachedResult(
      resolvedAt: now,
      session: session,
      usedWideScan: usedWideScan,
      // A pending sole confirmation retries fast instead of backing off.
      unresolvedStreak: Self.nextUnresolvedStreak(
        resolvedNow: session != nil || provisionalID != nil,
        previousWasUnresolved: cached.map { $0.session == nil && $0.provisionalSoleID == nil } ?? false,
        previousStreak: cached?.unresolvedStreak ?? 0
      ),
      provisionalSoleID: provisionalID
    )
    if cache.count > 128 {
      cache = cache.filter { entry in
        ProcessDetection.processStartDate(pid: entry.key.pid) == entry.key.startedAt
      }
    }
    return AgentSessionResolution(session: session, isFresh: true)
  }

  /// A session id already resolved for a different live process cannot also
  /// belong to this one; sole-candidate attribution must not steal it.
  private func claimedByAnotherProcess(_ id: String, excluding key: CacheKey) -> Bool {
    cache.contains { entry in
      entry.key != key && entry.value.session?.id == id
        && ProcessDetection.processStartDate(pid: entry.key.pid) == entry.key.startedAt
    }
  }

  /// Selects the path parser for this surface: the rooted variant when a
  /// relocated config root is in play (docs-ai 053), the default markers
  /// otherwise.
  nonisolated static func pathParser(
    profile: AgentSessionProfile,
    configRoot: URL?
  ) -> @Sendable (String) -> AgentSession? {
    if let configRoot, let rooted = profile.rootedParsePath {
      return { rooted($0, configRoot) }
    }
    return profile.parsePath
  }

  private func resolveUncached(
    identified: IdentifiedAgentProcess,
    processStartedAt: Date,
    workingDirectory: URL?,
    activeText: String,
    configRoot: URL? = nil,
    now: Date
  ) -> (session: AgentSession?, usedWideScan: Bool) {
    let profile = AgentSessionProfile.profile(for: identified.agent)
    let parsePath = Self.pathParser(profile: profile, configRoot: configRoot)

    let openSessions = ProcessDetection.openFilePaths(pid: identified.process.pid)
      .compactMap { parsePath($0) }
      .compactMap { session -> AgentSession? in
        guard let path = session.transcriptPath,
          let fullID = Self.sessionIDFromHeader(at: path, keys: profile.headerSessionIDKeys)
        else {
          return profile.requiresHeaderSessionID ? nil : session
        }
        return AgentSession(id: fullID, transcriptPath: path, source: session.source)
      }
    if let session = uniqueSession(openSessions) {
      let resolved = AgentSession(
        id: session.id,
        transcriptPath: session.transcriptPath,
        source: .openFile,
        confidence: .exact
      )
      return (resolved, false)
    }

    if let configRoot,
      let session = profile.rootedPIDKeyedSession?(configRoot, identified.process.pid, processStartedAt)
    {
      return (session, false)
    }
    if configRoot == nil,
      let session = profile.pidKeyedSession?(homeDirectory, identified.process.pid, processStartedAt)
    {
      return (session, false)
    }

    let openCandidates = openSessions.compactMap { session -> AgentSessionCandidate? in
      guard let path = session.transcriptPath,
        let attributes = try? fileManager.attributesOfItem(atPath: path.path),
        let modifiedAt = attributes[.modificationDate] as? Date
      else { return nil }
      return AgentSessionCandidate(session: session, modifiedAt: modifiedAt)
    }
    if let matched = AgentSessionFingerprintMatcher.bestMatch(
      activeText: activeText,
      candidates: openCandidates
    ) {
      let resolved = AgentSession(
        id: matched.session.id,
        transcriptPath: matched.session.transcriptPath,
        source: .transcriptMatch,
        confidence: .high
      )
      return (resolved, false)
    }

    let (candidates, usedWideScan) = recentCandidates(
      profile: profile,
      processStartedAt: processStartedAt,
      workingDirectory: workingDirectory,
      configRoot: configRoot,
      now: now
    )
    if let matched = AgentSessionFingerprintMatcher.bestMatch(activeText: activeText, candidates: candidates) {
      let resolved = AgentSession(
        id: matched.session.id,
        transcriptPath: matched.session.transcriptPath,
        source: .transcriptMatch,
        confidence: .high
      )
      return (resolved, usedWideScan)
    }
    let sole = AgentSessionCandidate.uniqueActiveCandidate(candidates, processStartedAt: processStartedAt)?.session
    return (sole, usedWideScan)
  }

  private func uniqueSession(_ sessions: [AgentSession]) -> AgentSession? {
    let unique = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return unique.count == 1 ? unique.values.first : nil
  }

  func recentCandidates(
    profile: AgentSessionProfile,
    processStartedAt: Date,
    workingDirectory: URL?,
    configRoot: URL? = nil,
    now: Date,
    visitLimit: Int = 20_000
  ) -> (candidates: [AgentSessionCandidate], usedWideScan: Bool) {
    let cwdVariants = workingDirectoryVariants(workingDirectory)
    let threshold = processStartedAt.addingTimeInterval(-2)
    // Under a relocated config root the rooted layout is used exclusively:
    // scanning the default home would misattribute another account's
    // sessions. Store-backed agents cannot be account-bound.
    let stored =
      configRoot == nil
      ? cwdVariants.flatMap { profile.storeCandidates?(homeDirectory, $0, threshold) ?? [] }
      : []
    var primaryRoots: [URL] = []
    for cwd in cwdVariants {
      let roots =
        if let configRoot {
          profile.rootedCandidateRoots?(configRoot, cwd, processStartedAt, now) ?? []
        } else {
          profile.candidateRoots(homeDirectory, cwd, processStartedAt, now)
        }
      for root in roots where !primaryRoots.contains(root) {
        primaryRoots.append(root)
      }
    }
    guard
      let primary = scanCandidates(
        in: primaryRoots,
        profile: profile,
        processStartedAt: processStartedAt,
        configRoot: configRoot,
        visitLimit: visitLimit
      )
    else {
      // A truncated primary scan voids this whole round: the fallback tree is
      // a superset and would only repeat the oversized enumeration. Report it
      // as a wide scan so the retry backs off at the slow tier.
      return ([], true)
    }
    let combined = primary + stored.uniquedBySessionID()
    guard combined.isEmpty else { return (combined, false) }
    let fallbackRoots =
      if let configRoot {
        profile.rootedFallbackRoots?(configRoot, workingDirectory) ?? []
      } else {
        profile.fallbackRoots(homeDirectory, workingDirectory)
      }
    guard !fallbackRoots.isEmpty else { return ([], false) }
    let fallback = scanCandidates(
      in: fallbackRoots,
      profile: profile,
      processStartedAt: processStartedAt,
      configRoot: configRoot,
      visitLimit: visitLimit
    )
    return (fallback ?? [], true)
  }

  /// The pane reports the shell's logical `$PWD` while agents usually record
  /// the physical path (`/tmp` vs `/private/tmp`); try both encodings.
  private func workingDirectoryVariants(_ cwd: URL?) -> [URL?] {
    guard let cwd else { return [nil] }
    let resolved = cwd.resolvingSymlinksInPath()
    return resolved.path == cwd.path ? [cwd] : [cwd, resolved]
  }

  /// Scans `roots` for session files modified during the process lifetime.
  /// Returns nil when any enumeration was truncated: an incomplete view could
  /// declare a false unique candidate, and unresolved is the safe outcome.
  func scanCandidates(
    in roots: [URL],
    profile: AgentSessionProfile,
    processStartedAt: Date,
    configRoot: URL? = nil,
    visitLimit: Int = 20_000
  ) -> [AgentSessionCandidate]? {
    var collected: [AgentSessionCandidate] = []
    for root in roots {
      guard
        let files = recentFiles(
          in: root,
          modifiedAfter: processStartedAt.addingTimeInterval(-2),
          visitLimit: visitLimit
        )
      else { return nil }
      for item in files {
        guard let candidate = enrichedCandidate(for: item, profile: profile, configRoot: configRoot)
        else { continue }
        collected.append(candidate)
      }
    }
    return collected
  }

  private func enrichedCandidate(
    for item: (url: URL, modifiedAt: Date),
    profile: AgentSessionProfile,
    configRoot: URL?
  ) -> AgentSessionCandidate? {
    guard let session = Self.pathParser(profile: profile, configRoot: configRoot)(item.url.path) else { return nil }
    if let fullID = Self.sessionIDFromHeader(at: item.url, keys: profile.headerSessionIDKeys) {
      return AgentSessionCandidate(
        session: AgentSession(id: fullID, transcriptPath: item.url, source: .recentFile),
        modifiedAt: item.modifiedAt
      )
    }
    // A profile that depends on the header (Gemini's filenames only carry a
    // truncated id) must not surface the unusable path-derived id.
    guard !profile.requiresHeaderSessionID else { return nil }
    return AgentSessionCandidate(session: session, modifiedAt: item.modifiedAt)
  }

  nonisolated static func sessionIDFromHeader(at url: URL, keys: [String]) -> String? {
    guard !keys.isEmpty, url.pathExtension == "jsonl",
      let handle = try? FileHandle(forReadingFrom: url)
    else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 8_192),
      let line = data.split(separator: 0x0A).first,
      let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
    else { return nil }
    for key in keys {
      if let value = object[key] as? String, !value.isEmpty { return value }
    }
    return nil
  }

  /// Returns nil when the enumeration exceeded `visitLimit`: a partial view
  /// must void the whole scan rather than feed uniqueness checks.
  private func recentFiles(
    in root: URL,
    modifiedAfter threshold: Date,
    visitLimit: Int
  ) -> [(url: URL, modifiedAt: Date)]? {
    guard
      let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }

    var visited = 0
    var result: [(URL, Date)] = []
    for case let url as URL in enumerator {
      visited += 1
      if visited > visitLimit {
        agentSessionLogger.warning("Agent session scan truncated at \(visitLimit) entries under \(root.path)")
        return nil
      }
      guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
        values.isRegularFile == true,
        let modifiedAt = values.contentModificationDate,
        modifiedAt >= threshold
      else { continue }
      result.append((url, modifiedAt))
    }
    return result
  }
}

nonisolated enum AgentSessionFingerprintMatcher {
  static func bestMatch(
    activeText: String,
    candidates: [AgentSessionCandidate]
  ) -> AgentSessionCandidate? {
    let screen = normalize(activeText)
    guard screen.count >= 12 else { return nil }
    // Bound tail reads WITHOUT evicting whole sessions: cap files per session
    // (extra files of one session only reinforce it), and refuse to declare
    // uniqueness when there are more sessions than the read budget covers —
    // an unexamined session could hold the same text.
    let bySession = Dictionary(grouping: candidates) { $0.session.id }
    guard bySession.count <= 12 else { return nil }
    var scored: [(AgentSessionCandidate, Int)] = []
    for group in bySession.values {
      var sessionScoreable = false
      for candidate in group.sorted(by: { $0.modifiedAt > $1.modifiedAt }).prefix(2) {
        guard let path = candidate.session.transcriptPath, let data = tailData(at: path) else { continue }
        // Lossy decoding is deliberate: the tail window can start mid-character
        // in a multi-byte transcript, and a failable conversion would void the
        // whole tail instead of just the cut first line.
        // swiftlint:disable:next optional_data_string_conversion
        let fragments = transcriptStrings(String(decoding: data, as: UTF8.self))
        // Scoreable means the session produced at least one fragment long
        // enough to actually enter the comparison — fragments below the floor
        // ("OK") are no testimony at all.
        let comparable = fragments.map(normalize).filter { $0.count >= 12 }
        if !comparable.isEmpty { sessionScoreable = true }
        let score = comparable.reduce(0) { best, normalized in
          if screen.contains(normalized) { return max(best, min(200, normalized.count + 80)) }
          let suffix = String(normalized.suffix(80))
          return suffix.count >= 24 && screen.contains(suffix) ? max(best, suffix.count) : best
        }
        if score > 0 { scored.append((candidate, score)) }
      }
      // A session that yields no comparable text at all (unreadable tail,
      // oversized single-line JSON, no supported fields) might still be the
      // real one; uniqueness cannot be declared over its silence. A scoreable
      // session that merely scores zero HAS testified — it stays eliminable.
      guard sessionScoreable else { return nil }
    }

    // The margin rule guards against picking between *sessions* that look
    // alike; files belonging to one session reinforce it instead of competing.
    let sessions = Dictionary(grouping: scored) { $0.0.session.id }
      .map { id, group in
        (id: id, best: group.max { $0.1 < $1.1 }!)
      }
      .sorted { $0.best.1 > $1.best.1 }

    guard let winner = sessions.first, winner.best.1 >= 40 else { return nil }
    if sessions.count > 1, winner.best.1 - sessions[1].best.1 < 20 { return nil }
    return winner.best.0
  }

  static func normalize(_ value: String) -> String {
    value
      .replacing(#/\u{001B}\[[0-?]*[ -\/]*[@-~]/#, with: " ")
      .lowercased()
      .split(whereSeparator: \Character.isWhitespace)
      .joined(separator: " ")
  }

  private static func tailData(at url: URL, byteLimit: UInt64 = 131_072) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let size = try? handle.seekToEnd() else { return nil }
    try? handle.seek(toOffset: size > byteLimit ? size - byteLimit : 0)
    return try? handle.readToEnd()
  }

  private static func transcriptStrings(_ text: String) -> [String] {
    text.split(separator: "\n").suffix(80).flatMap { line -> [String] in
      guard let data = line.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data)
      else { return [] }
      return strings(in: json, key: nil)
    }
  }

  private static func strings(in value: Any, key: String?) -> [String] {
    if let string = value as? String,
      ["content", "text", "message", "result", "prompt", "last_assistant_message"].contains(key ?? "")
    {
      return [string]
    }
    if let array = value as? [Any] {
      return array.flatMap { strings(in: $0, key: key) }
    }
    if let object = value as? [String: Any] {
      return object.flatMap { strings(in: $0.value, key: $0.key) }
    }
    return []
  }
}
