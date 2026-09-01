import Foundation
import Testing

@testable import supacode

struct HeixiuAgentTrailTests {
  @Test func projectionPrioritizesAttentionThenProgressThenRest() throws {
    let idle = entry(state: .idle, changedAt: 50)
    let working = entry(state: .working, changedAt: 40)
    let done = entry(state: .done, changedAt: 30)
    let blocked = entry(state: .blocked, changedAt: 20)

    let projection = HeixiuAgentTrail.projection(for: [idle, working, done, blocked])

    #expect(projection.entries.map(\.id) == [blocked.id, done.id])
    #expect(projection.overflowCount == 2)
    #expect(projection.dominantState == .blocked)
  }

  @Test func projectionUsesRecencyInsideTheSameState() {
    let older = entry(state: .working, changedAt: 10)
    let newer = entry(state: .working, changedAt: 20)
    let idle = entry(state: .idle, changedAt: 30)

    let projection = HeixiuAgentTrail.projection(for: [older, idle, newer])

    #expect(projection.entries.map(\.id) == [newer.id, older.id, idle.id])
    #expect(projection.overflowCount == 0)
    #expect(projection.dominantState == .working)
  }

  @Test func allStatesHaveDistinctCatStatusSymbols() {
    let states: [AgentDisplayState] = [.working, .blocked, .done, .idle]

    #expect(Set(states.map(\.statusSymbolName)).count == states.count)
    #expect(AgentDisplayState.working.statusSymbolName == "pawprint.fill")
    #expect(AgentDisplayState.blocked.statusSymbolName == "exclamationmark")
    #expect(AgentDisplayState.done.statusSymbolName == "sparkles")
    #expect(AgentDisplayState.idle.statusSymbolName == "moon.zzz.fill")
  }

  @Test func catGeometryExpressesAgentStateWithoutChangingTheRosterModel() {
    let working = ProwlCatGeometry.geometry(for: .working)
    let blocked = ProwlCatGeometry.geometry(for: .blocked)
    let done = ProwlCatGeometry.geometry(for: .done)
    let idle = ProwlCatGeometry.geometry(for: .idle)

    #expect(blocked.tailLift > done.tailLift)
    #expect(done.tailLift > working.tailLift)
    #expect(working.tailLift > idle.tailLift)
    #expect(blocked.headLift > working.headLift)
    #expect(working.headLift > idle.headLift)
    #expect(working.forelegReach > idle.forelegReach)
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
