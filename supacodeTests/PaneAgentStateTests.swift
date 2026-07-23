import Foundation
import Testing

@testable import supacode

struct PaneAgentStateTests {
  @Test func displayStateDerivesDoneFromUnseenIdle() {
    var state = PaneAgentState(
      detectedAgent: .codex,
      fallbackState: .idle,
      state: .idle,
      seen: false,
      lastChangedAt: Date(timeIntervalSince1970: 0)
    )

    #expect(state.displayState == .done)
    state.seen = true
    #expect(state.displayState == .idle)
  }

  @Test(arguments: [DetectedAgent.claude, .codex, .gemini])
  func workingIsStickyForShortIdleGap(agent: DetectedAgent) {
    let now = Date(timeIntervalSince1970: 100)
    var lastWorking: Date?

    let working = stabilizeAgentState(
      agent: agent,
      previous: .idle,
      raw: .working,
      now: now,
      lastWorkingAt: &lastWorking
    )
    #expect(working == .working)

    let stillWorking = stabilizeAgentState(
      agent: agent,
      previous: .working,
      raw: .idle,
      now: now.addingTimeInterval(2.9),
      lastWorkingAt: &lastWorking
    )
    #expect(stillWorking == .working)
  }

  @Test(arguments: [DetectedAgent.claude, .codex])
  func transitionsToIdleAfterStickyWindow(agent: DetectedAgent) {
    let now = Date(timeIntervalSince1970: 100)
    var lastWorking: Date? = now

    let idle = stabilizeAgentState(
      agent: agent,
      previous: .working,
      raw: .idle,
      now: now.addingTimeInterval(3.001),
      lastWorkingAt: &lastWorking
    )

    #expect(idle == .idle)
  }

  @Test func blockedBypassesStickyWindow() {
    let now = Date(timeIntervalSince1970: 100)
    var lastWorking: Date? = now

    let blocked = stabilizeAgentState(
      agent: .claude,
      previous: .working,
      raw: .blocked,
      now: now.addingTimeInterval(0.3),
      lastWorkingAt: &lastWorking
    )

    #expect(blocked == .blocked)
  }

  @Test func unknownObservationKeepsPreviousStateAndRefreshesHold() {
    let now = Date(timeIntervalSince1970: 100)
    var lastWorking: Date? = now
    let later = now.addingTimeInterval(10)

    let held = stabilizeAgentState(
      agent: .claude,
      previous: .working,
      raw: .unknown,
      now: later,
      lastWorkingAt: &lastWorking
    )

    #expect(held == .working)
    #expect(lastWorking == later)

    var noHistory: Date?
    let idle = stabilizeAgentState(
      agent: .claude,
      previous: .idle,
      raw: .unknown,
      now: later,
      lastWorkingAt: &noHistory
    )

    #expect(idle == .idle)
    #expect(noHistory == nil)
  }

  @Test func unknownObservationWithoutHistoryStaysUnknown() {
    let now = Date(timeIntervalSince1970: 100)
    var lastWorking: Date?

    let unknown = stabilizeAgentState(
      agent: .claude,
      previous: .unknown,
      raw: .unknown,
      now: now,
      lastWorkingAt: &lastWorking
    )

    #expect(unknown == .unknown)
  }

  @Test func presenceRequiresSixMissesBeforeRelease() {
    var presence = AgentDetectionPresence(currentAgent: .codex)

    for _ in 0..<5 {
      #expect(presence.update(detectedAgent: nil) == .codex)
    }
    #expect(presence.update(detectedAgent: nil) == nil)
    #expect(presence.currentAgent == nil)
  }

  @Test func isBusyReflectsWorkingAndBlockedDetectedAgents() {
    #expect(PaneAgentState(detectedAgent: .claude, state: .working).isBusy)
    #expect(PaneAgentState(detectedAgent: .claude, state: .blocked).isBusy)
    #expect(!PaneAgentState(detectedAgent: .claude, state: .idle).isBusy)
    // Unseen idle surfaces display as `.done`, which must not count as busy.
    #expect(!PaneAgentState(detectedAgent: .claude, state: .idle, seen: false).isBusy)
    // A plain shell (no detected agent) is never busy, even mid-output.
    #expect(!PaneAgentState(detectedAgent: nil, state: .working).isBusy)
  }

  @Test func launchObservationRetainsOnlyForSameProcess() {
    let observation = AgentLaunchObservation(model: "gpt-5.4", executionMode: .unrestricted)
    let previous = PaneAgentState(agentProcessID: 42, launchObservation: observation)

    #expect(
      PaneAgentState.retainedLaunchObservation(
        observed: nil,
        previous: previous,
        identifiedPID: 42
      ) == observation
    )
    #expect(
      PaneAgentState.retainedLaunchObservation(
        observed: nil,
        previous: previous,
        identifiedPID: 43
      ) == nil
    )
  }
}
