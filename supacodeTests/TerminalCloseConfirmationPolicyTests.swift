import Foundation
import Testing

@testable import supacode

struct TerminalCloseConfirmationPolicyTests {
  @Test func agentWorkingBlockedAndDoneRequireConfirmation() {
    let protectedStates: [AgentDisplayState] = [.working, .blocked, .done]

    for state in protectedStates {
      let decision = TerminalCloseConfirmationPolicy.decision(
        for: [
          TerminalCloseProtectionCandidate(
            hasAgent: true,
            agentDisplayState: state,
            commandRunningDuration: nil
          )
        ]
      )

      #expect(decision.requiresConfirmation)
      #expect(decision.protectedPaneCount == 1)
    }
  }

  @Test func agentIdleDoesNotRequireConfirmation() {
    let decision = TerminalCloseConfirmationPolicy.decision(
      for: [
        TerminalCloseProtectionCandidate(
          hasAgent: true,
          agentDisplayState: .idle,
          commandRunningDuration: 30
        )
      ]
    )

    #expect(decision.requiresConfirmation == false)
  }

  @Test func nonAgentCommandRequiresConfirmationOnlyAfterThreshold() {
    let shortCommand = TerminalCloseConfirmationPolicy.decision(
      for: [
        TerminalCloseProtectionCandidate(
          hasAgent: false,
          agentDisplayState: nil,
          commandRunningDuration: 9.9
        )
      ]
    )
    let longCommand = TerminalCloseConfirmationPolicy.decision(
      for: [
        TerminalCloseProtectionCandidate(
          hasAgent: false,
          agentDisplayState: nil,
          commandRunningDuration: 10
        )
      ]
    )
    let finishedCommand = TerminalCloseConfirmationPolicy.decision(
      for: [
        TerminalCloseProtectionCandidate(
          hasAgent: false,
          agentDisplayState: nil,
          commandRunningDuration: nil
        )
      ]
    )

    #expect(shortCommand.requiresConfirmation == false)
    #expect(longCommand.requiresConfirmation)
    #expect(finishedCommand.requiresConfirmation == false)
  }

  @Test func countsProtectedPanesAcrossTab() {
    let decision = TerminalCloseConfirmationPolicy.decision(
      for: [
        TerminalCloseProtectionCandidate(
          hasAgent: true,
          agentDisplayState: .working,
          commandRunningDuration: nil
        ),
        TerminalCloseProtectionCandidate(
          hasAgent: false,
          agentDisplayState: nil,
          commandRunningDuration: 14
        ),
        TerminalCloseProtectionCandidate(
          hasAgent: true,
          agentDisplayState: .idle,
          commandRunningDuration: 20
        ),
      ]
    )

    #expect(decision.requiresConfirmation)
    #expect(decision.protectedPaneCount == 2)
    #expect(decision.reasons.contains(.agentActive))
    #expect(decision.reasons.contains(.longRunningCommand))
  }

  @Test func informativeMessageNamesWorktree() {
    let decision = TerminalCloseConfirmationPolicy.decision(
      for: [
        TerminalCloseProtectionCandidate(
          hasAgent: true,
          agentDisplayState: .working,
          commandRunningDuration: nil
        )
      ]
    )

    let message = TerminalCloseConfirmationPolicy.informativeMessage(
      for: decision,
      worktreeName: "feature/foo"
    )

    #expect(
      message
        == "This will close 1 pane in “feature/foo” with active agent work or an unseen agent result."
    )
  }

  @Test func informativeMessageAggregatesMixedReasons() {
    let decision = TerminalCloseConfirmationPolicy.decision(
      for: [
        TerminalCloseProtectionCandidate(
          hasAgent: true,
          agentDisplayState: .working,
          commandRunningDuration: nil
        ),
        TerminalCloseProtectionCandidate(
          hasAgent: false,
          agentDisplayState: nil,
          commandRunningDuration: 30
        ),
      ]
    )

    let message = TerminalCloseConfirmationPolicy.informativeMessage(
      for: decision,
      worktreeName: "wt"
    )

    #expect(
      message
        == "This will close 2 panes in “wt” with active agent work, unseen agent results, or long-running commands."
    )
  }
}
