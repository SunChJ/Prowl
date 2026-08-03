import Foundation
import Testing

@testable import supacode

/// Terminal-layer behavior of `launchAgentProfile` that is testable without a
/// live Ghostty surface (docs-ai 053/005).
@MainActor
struct WorktreeTerminalStateAgentProfileTests {
  @Test func provisionFailureAbortsTheLaunchEntirely() {
    let state = makeState()
    // A dedicated home outside the profile-home base fails the containment
    // gate before any surface is created.
    let plan = makePlan(
      dedicatedHome: URL(filePath: "/tmp/prowl-test-outside-base/home", directoryHint: .isDirectory)
    )

    let surfaceID = state.launchAgentProfile(plan)

    #expect(surfaceID == nil)
    #expect(state.tabManager.tabs.isEmpty)
    #expect(state.launchProfilesBySurface.isEmpty)
  }

  @Test func launchProfileNameOnlyAppliesToTheLaunchedRuntime() {
    let state = makeState()
    let surfaceID = UUID()
    state.launchProfilesBySurface[surfaceID] = WorktreeTerminalState.SurfaceLaunchProfile(
      profileID: UUID(),
      name: "Codex · Work",
      runtime: .codex,
      dedicatedHome: nil
    )

    #expect(state.launchProfileName(surfaceID: surfaceID, detected: .codex) == "Codex · Work")
    // A *different* agent started manually in the same pane must not wear the
    // old profile's name — same gating rule as `configRoot(forDetected:)`.
    #expect(state.launchProfileName(surfaceID: surfaceID, detected: .claude) == nil)
    #expect(state.launchProfileName(surfaceID: UUID(), detected: .codex) == nil)
  }

  @Test func launchIdentityClearsWhenTheLaunchedAgentExits() {
    let state = makeState()
    let surfaceID = UUID()
    state.launchProfilesBySurface[surfaceID] = WorktreeTerminalState.SurfaceLaunchProfile(
      profileID: UUID(),
      name: "Codex · Work",
      runtime: .codex,
      dedicatedHome: nil
    )
    state.surfaceAgentStates[surfaceID] = PaneAgentState(detectedAgent: .codex)

    state.removeAgentEntryIfNeeded(surfaceID: surfaceID)

    // The identity lives exactly as long as the launched agent: a manually
    // started agent afterwards is the user's own (docs-ai 053/006).
    #expect(state.launchProfilesBySurface[surfaceID] == nil)
  }

  @Test func launchTabWearsTheRuntimeIconInsteadOfTheTerminalGlyph() {
    // No runtime falls back to the generic glyph: a new case added without a
    // `CommandIconMap` entry would otherwise launch unbranded and silently.
    for runtime in AgentProfileRuntime.allCases {
      #expect(WorktreeTerminalState.launchTabIcon(for: runtime) != nil, "\(runtime) has no icon")
    }
    #expect(WorktreeTerminalState.launchTabIcon(for: .claude)?.storageString != "terminal")
    #expect(WorktreeTerminalState.launchTabIcon(for: .codex)?.storageString != "terminal")
    #expect(
      WorktreeTerminalState.launchTabIcon(for: .claude)?.storageString
        != WorktreeTerminalState.launchTabIcon(for: .codex)?.storageString
    )
  }

  @Test func launchCreatesTheTabWithTheRuntimeIcon() {
    let state = makeState()

    _ = state.launchAgentProfile(makePlan(dedicatedHome: nil))

    // Guards the call site, not just the helper: a hardcoded glyph here is the
    // original bug, and it survives a helper-only assertion.
    #expect(state.tabManager.tabs.count == 1)
    #expect(
      state.tabManager.tabs.first?.icon
        == WorktreeTerminalState.launchTabIcon(for: .codex)?.storageString
    )
    #expect(state.tabManager.tabs.first?.icon != "terminal")
    // Left claimable, so a later command in the same tab still wins the slot.
    #expect(state.tabManager.tabs.first?.iconLock == .auto)
  }

  @Test func splitLaunchRebrandsTheContainingTab() throws {
    let state = makeState()
    _ = state.launchAgentProfile(makePlan(dedicatedHome: nil))
    let tabID = try #require(state.tabManager.tabs.first?.id)
    state.tabManager.updateIcon(tabID, icon: "@asset:Git")

    let surfaceID = state.launchAgentProfile(
      makePlan(dedicatedHome: nil, runtime: .claude, placement: .split)
    )

    // The split becomes the focused surface, so its runtime owns the tab icon;
    // its `env …` title never reaches `CommandIconMap`.
    #expect(state.tabID(containing: try #require(surfaceID)) == tabID)
    #expect(state.tabManager.tabs.count == 1)
    #expect(
      state.tabManager.tabs.first?.icon
        == WorktreeTerminalState.launchTabIcon(for: .claude)?.storageString
    )
    #expect(state.tabManager.tabs.first?.iconLock == .auto)
  }

  @Test func splitLaunchLeavesAClaimedIconAlone() throws {
    let state = makeState()
    _ = state.launchAgentProfile(makePlan(dedicatedHome: nil))
    let tabID = try #require(state.tabManager.tabs.first?.id)
    state.tabManager.overrideIcon(tabID, icon: "@asset:Git")

    _ = state.launchAgentProfile(
      makePlan(dedicatedHome: nil, runtime: .claude, placement: .split)
    )

    #expect(state.tabManager.tabs.first?.icon == "@asset:Git")
    #expect(state.tabManager.tabs.first?.iconLock == .user)
  }

  @Test func splitLaunchLeavesAScriptIconAlone() throws {
    let state = makeState()
    _ = state.launchAgentProfile(makePlan(dedicatedHome: nil))
    let tabID = try #require(state.tabManager.tabs.first?.id)
    state.tabManager.setScriptIcon(tabID, icon: "@asset:Git")

    _ = state.launchAgentProfile(
      makePlan(dedicatedHome: nil, runtime: .claude, placement: .split)
    )

    // A launch is auto-detection's peer, not a script: it yields to `.script`
    // just as `CommandIconMap` does.
    #expect(state.tabManager.tabs.first?.icon == "@asset:Git")
    #expect(state.tabManager.tabs.first?.iconLock == .script)
  }

  private func makeState() -> WorktreeTerminalState {
    WorktreeTerminalState(
      runtime: GhosttyRuntime(),
      worktree: Worktree(
        id: "/tmp/repo/wt-1",
        name: "wt-1",
        detail: "",
        workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
        repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
      )
    )
  }

  private func makePlan(
    dedicatedHome: URL?,
    runtime: AgentProfileRuntime = .codex,
    placement: AgentProfilePlacement = .tab
  ) -> AgentProfileLaunchPlan {
    AgentProfileLaunchPlan(
      profileID: UUID(),
      profileName: "Codex · Bound",
      runtime: runtime,
      invocation: AgentInvocation(executable: runtime.agent.iconLookupToken, arguments: []),
      commandEnvironmentTokens: [],
      placement: placement,
      splitDirection: .right,
      surfaceEnvironment: [:],
      dedicatedHome: dedicatedHome
    )
  }
}
