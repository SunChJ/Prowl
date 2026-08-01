import Testing

@testable import supacode

struct AgentScreenScanCacheTests {
  /// With no cache, the helper scans from scratch and returns a scan that
  /// round-trips the inputs and the freshly computed raw state.
  @Test func scansFromScratchWithoutCache() {
    let (raw, scan) = WorktreeTerminalState.resolveRawState(
      agent: .claude,
      text: "screen",
      cache: nil
    )

    #expect(raw == DetectedAgent.claude.detectState(in: "screen"))
    #expect(scan == WorktreeTerminalState.AgentScreenScan(agent: .claude, text: "screen", raw: raw))
  }

  /// When the cached agent and text both match, the helper returns the cached
  /// raw state without recomputing. Proven by seeding a sentinel raw a fresh
  /// scan would never produce and asserting it comes back unchanged.
  @Test func reusesCachedRawWhenAgentAndTextMatch() {
    let text = ""
    let sentinel = WorktreeTerminalState.AgentScreenScan(agent: .claude, text: text, raw: .blocked)
    #expect(DetectedAgent.claude.detectState(in: text) != .blocked)

    let (raw, scan) = WorktreeTerminalState.resolveRawState(agent: .claude, text: text, cache: sentinel)

    #expect(raw == .blocked)
    #expect(scan == sentinel)
  }

  /// A changed screen invalidates the cache and forces a rescan.
  @Test func rescansWhenTextChanges() {
    let cache = WorktreeTerminalState.AgentScreenScan(agent: .claude, text: "old", raw: .blocked)

    let (raw, scan) = WorktreeTerminalState.resolveRawState(agent: .claude, text: "new", cache: cache)

    #expect(raw == DetectedAgent.claude.detectState(in: "new"))
    #expect(scan.text == "new")
  }

  /// A different detected agent invalidates the cache even when the text is
  /// identical, since raw state is agent-specific.
  @Test func rescansWhenAgentChanges() {
    let cache = WorktreeTerminalState.AgentScreenScan(agent: .codex, text: "screen", raw: .blocked)

    let (raw, scan) = WorktreeTerminalState.resolveRawState(agent: .claude, text: "screen", cache: cache)

    #expect(raw == DetectedAgent.claude.detectState(in: "screen"))
    #expect(scan.agent == .claude)
  }
}
