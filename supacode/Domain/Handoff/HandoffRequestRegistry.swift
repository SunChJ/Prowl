import Foundation

/// Owns the one-shot authorization for a HUD-injected handoff request. The
/// HUD and socket handler both run on the main actor, so claiming the request
/// or superseding it for a fallback is one serialized state transition.
@MainActor
final class HandoffRequestRegistry {
  private enum State {
    case pending
    case claimed
    case superseded
  }

  private var states: [UUID: State] = [:]

  func register(_ requestID: UUID) {
    states[requestID] = .pending
  }

  /// Claims a pending request for its CLI transition. A request can only be
  /// claimed once and cannot run after a HUD fallback supersedes it.
  @discardableResult
  func claim(_ requestID: UUID) -> Bool {
    guard states[requestID] == .pending else { return false }
    states[requestID] = .claimed
    return true
  }

  /// Supersedes a still-pending injected request before the HUD begins its
  /// independent fallback transition. A handler that already claimed it owns
  /// the transition and must be allowed to finish instead.
  @discardableResult
  func supersede(_ requestID: UUID) -> Bool {
    guard states[requestID] == .pending else { return false }
    states[requestID] = .superseded
    return true
  }
}
