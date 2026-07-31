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

  private func makePlan(dedicatedHome: URL?) -> AgentProfileLaunchPlan {
    AgentProfileLaunchPlan(
      profileID: UUID(),
      profileName: "Codex · Bound",
      runtime: .codex,
      invocation: AgentInvocation(executable: "codex", arguments: []),
      placement: .tab,
      splitDirection: .right,
      environment: [:],
      dedicatedHome: dedicatedHome
    )
  }
}
