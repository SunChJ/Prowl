import Foundation

struct TerminalCloseProtectionCandidate: Equatable {
  let hasAgent: Bool
  let agentDisplayState: AgentDisplayState?
  let commandRunningDuration: TimeInterval?
}

enum TerminalCloseProtectionReason: Equatable, Hashable {
  case agentActive
  case longRunningCommand
}

struct TerminalCloseConfirmationDecision: Equatable {
  let protectedPaneCount: Int
  let reasons: Set<TerminalCloseProtectionReason>

  var requiresConfirmation: Bool {
    protectedPaneCount > 0
  }
}

enum TerminalCloseConfirmationPolicy {
  static let longRunningCommandThreshold: TimeInterval = 10

  static func decision(
    for candidates: [TerminalCloseProtectionCandidate],
    threshold: TimeInterval = Self.longRunningCommandThreshold
  ) -> TerminalCloseConfirmationDecision {
    var protectedPaneCount = 0
    var reasons: Set<TerminalCloseProtectionReason> = []

    for candidate in candidates {
      guard let reason = protectionReason(for: candidate, threshold: threshold) else { continue }
      protectedPaneCount += 1
      reasons.insert(reason)
    }

    return TerminalCloseConfirmationDecision(
      protectedPaneCount: protectedPaneCount,
      reasons: reasons
    )
  }

  /// Alert body for a close prompt. Always names the worktree: the prompt can
  /// be triggered from the sidebar against a worktree whose tabs are not
  /// visible, so the target's identity must be part of the confirmation.
  static func informativeMessage(
    for decision: TerminalCloseConfirmationDecision,
    worktreeName: String
  ) -> String {
    let paneText = decision.protectedPaneCount == 1 ? "pane" : "panes"
    let reasonText: String
    if decision.reasons == Set([.agentActive]) {
      reasonText = "active agent work or an unseen agent result"
    } else if decision.reasons == Set([.longRunningCommand]) {
      reasonText = "a command that has been running for at least 10 seconds"
    } else {
      reasonText = "active agent work, unseen agent results, or long-running commands"
    }
    return
      "This will close \(decision.protectedPaneCount) \(paneText) in “\(worktreeName)” with \(reasonText)."
  }

  private static func protectionReason(
    for candidate: TerminalCloseProtectionCandidate,
    threshold: TimeInterval
  ) -> TerminalCloseProtectionReason? {
    if candidate.hasAgent {
      switch candidate.agentDisplayState {
      case .working, .blocked, .done:
        return .agentActive
      case .idle, .none:
        return nil
      }
    }

    guard let duration = candidate.commandRunningDuration, duration >= threshold else {
      return nil
    }
    return .longRunningCommand
  }
}
