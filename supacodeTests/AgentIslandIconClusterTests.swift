import Foundation
import Testing

@testable import supacode

struct AgentIslandIconClusterTests {
  @Test func projectionPlacesRecentNonIdleEntriesBeforeIdle() throws {
    let idle = entry(state: .idle, changedAt: 50)
    let working = entry(state: .working, changedAt: 40)
    let done = entry(state: .done, changedAt: 30)
    let blocked = entry(state: .blocked, changedAt: 20)

    let projection = AgentIslandIconCluster.projection(for: [idle, working, done, blocked])

    #expect(projection.entries.map(\.id) == [working.id, done.id, blocked.id])
    #expect(projection.overflowCount == 1)
  }

  @Test func projectionKeepsIdleOnTheRightEvenWhenItIsNewer() {
    let olderWorking = entry(state: .working, changedAt: 10)
    let newerWorking = entry(state: .working, changedAt: 20)
    let newestIdle = entry(state: .idle, changedAt: 30)

    let projection = AgentIslandIconCluster.projection(for: [
      olderWorking, newestIdle, newerWorking,
    ])

    #expect(projection.entries.map(\.id) == [newerWorking.id, olderWorking.id, newestIdle.id])
    #expect(projection.overflowCount == 0)
  }

  @Test func sixEntriesProjectThreeIconsAndThreeOverflow() {
    let entries = (0..<6).map { index in
      entry(state: .working, changedAt: TimeInterval(index))
    }

    let projection = AgentIslandIconCluster.projection(for: entries)

    #expect(projection.entries.map(\.id) == [entries[5].id, entries[4].id, entries[3].id])
    #expect(projection.overflowCount == 3)
  }

  @Test func animatedRingUsesStateSpecificBreathingWithSlowerDrift() {
    let working = AgentIslandRingPresentation.presentation(for: .working)
    let blocked = AgentIslandRingPresentation.presentation(for: .blocked)
    let done = AgentIslandRingPresentation.presentation(for: .done)
    let idle = AgentIslandRingPresentation.presentation(for: .idle)

    #expect(
      Set([working.breathingDuration, blocked.breathingDuration, done.breathingDuration]).count == 3)
    for presentation in [working, blocked, done] {
      #expect(presentation.breathingDuration > 0)
      #expect(presentation.driftDuration >= presentation.breathingDuration * 4)
    }
    #expect(idle.breathingDuration == 0)
    #expect(idle.driftDuration == 0)
  }

  @Test func onlyNonIdleStatesAnimateTheirIslandRing() {
    let working = AgentIslandRingPresentation.presentation(for: .working)
    let blocked = AgentIslandRingPresentation.presentation(for: .blocked)
    let done = AgentIslandRingPresentation.presentation(for: .done)
    let idle = AgentIslandRingPresentation.presentation(for: .idle)

    #expect(working.animates)
    #expect(blocked.animates)
    #expect(done.animates)
    #expect(!idle.animates)
  }

  private func entry(state: AgentDisplayState, changedAt: TimeInterval) -> ActiveAgentEntry {
    let id = UUID()
    return ActiveAgentEntry(
      id: id,
      worktreeID: "/repo/wt",
      worktreeName: "wt",
      workingDirectory: nil,
      tabID: TerminalTabID(rawValue: UUID()),
      paneTitle: "Agent",
      surfaceID: id,
      paneIndex: 1,
      iconLookupToken: DetectedAgent.codex.iconLookupToken,
      agent: .codex,
      rawState: state == .blocked ? .blocked : state == .working ? .working : .idle,
      displayState: state,
      lastChangedAt: Date(timeIntervalSince1970: changedAt)
    )
  }
}
