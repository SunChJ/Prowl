import Foundation

@MainActor
final class AgentDispatchCompleteCommandHandler: CommandHandler {
  typealias ResolveCaller = @MainActor (pid_t) -> CallerPane?
  typealias Complete =
    @MainActor (
      String, DispatchCompletionOutcome, String, UUID
    ) -> Result<AgentDispatchMutationResult, AgentDispatchStoreError>

  private let resolveCaller: ResolveCaller
  private let complete: Complete
  private let formatter: ISO8601DateFormatter

  init(
    resolveCaller: @escaping ResolveCaller,
    complete: @escaping Complete,
    now: @escaping @MainActor () -> Date = Date.init
  ) {
    self.resolveCaller = resolveCaller
    self.complete = complete
    self.formatter = Self.makeFormatter()
    _ = now
  }

  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    await handle(envelope: envelope, context: CLICommandContext())
  }

  // swiftlint:disable:next async_without_await
  func handle(envelope: CommandEnvelope, context: CLICommandContext) async -> CommandResponse {
    guard case .agentsDispatchComplete(let input) = envelope.command else {
      return failure(code: CLIErrorCode.invalidArgument, message: "Expected an agents.dispatch-complete command.")
    }
    if let message = input.validationErrorMessage {
      return failure(code: CLIErrorCode.invalidArgument, message: message)
    }
    guard let processID = context.callerProcessID, let caller = resolveCaller(processID) else {
      return failure(
        code: CLIErrorCode.dispatchContextRequired,
        message: "Run dispatch completion from the Prowl pane that owns this dispatch."
      )
    }
    switch complete(input.dispatchID, input.outcome, input.summary, caller.surfaceID) {
    case .failure(let error):
      return map(error)
    case .success(let result):
      guard let binding = result.snapshot.binding,
        case .completed(let receipt) = result.snapshot.payload(using: formatter)
      else {
        return failure(code: CLIErrorCode.dispatchFailed, message: "The dispatch receipt is incomplete.")
      }
      do {
        return try CommandResponse(
          ok: true,
          command: "agents.dispatch-complete",
          schemaVersion: "prowl.cli.agents.dispatch-complete.v1",
          data: RawJSON(
            encoding: DispatchCompleteCommandPayload(
              target: binding.target,
              receipt: receipt,
              replayed: result.replayed
            ))
        )
      } catch {
        return failure(code: CLIErrorCode.dispatchFailed, message: "Failed to encode the dispatch receipt.")
      }
    }
  }

  private func map(_ error: AgentDispatchStoreError) -> CommandResponse {
    switch error {
    case .notFound:
      failure(code: CLIErrorCode.dispatchNotFound, message: "The dispatch receipt was not found.")
    case .sourceMismatch:
      failure(code: CLIErrorCode.dispatchSourceMismatch, message: "This pane does not own the dispatch receipt.")
    case .alreadyCompleted:
      failure(code: CLIErrorCode.dispatchAlreadyCompleted, message: "The dispatch was already completed differently.")
    case .alreadyTerminal:
      failure(code: CLIErrorCode.dispatchAlreadyTerminal, message: "The dispatch is already terminal.")
    case .bindingMissing:
      failure(code: CLIErrorCode.dispatchFailed, message: "The dispatch has no bound pane.")
    case .capacityExceeded, .alreadyBound:
      failure(code: CLIErrorCode.dispatchFailed, message: "The dispatch receipt could not be updated.")
    }
  }

  private func failure(code: String, message: String) -> CommandResponse {
    CommandResponse(
      ok: false,
      command: "agents.dispatch-complete",
      schemaVersion: "prowl.cli.agents.dispatch-complete.v1",
      error: CommandError(code: code, message: message)
    )
  }

  static func makeFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
  }
}

@MainActor
final class AgentDispatchAbandonCommandHandler: CommandHandler {
  typealias Abandon =
    @MainActor (
      String, String
    ) -> Result<AgentDispatchMutationResult, AgentDispatchStoreError>

  private let abandon: Abandon
  private let formatter: ISO8601DateFormatter

  init(
    abandon: @escaping Abandon,
    now: @escaping @MainActor () -> Date = Date.init
  ) {
    self.abandon = abandon
    self.formatter = AgentDispatchCompleteCommandHandler.makeFormatter()
    _ = now
  }

  // swiftlint:disable:next async_without_await
  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    guard case .agentsDispatchAbandon(let input) = envelope.command else {
      return failure(code: CLIErrorCode.invalidArgument, message: "Expected an agents.dispatch-abandon command.")
    }
    if let message = input.validationErrorMessage {
      return failure(code: CLIErrorCode.invalidArgument, message: message)
    }
    switch abandon(input.dispatchID, input.reason) {
    case .failure(.notFound):
      return failure(code: CLIErrorCode.dispatchNotFound, message: "The dispatch receipt was not found.")
    case .failure(.alreadyTerminal), .failure(.alreadyCompleted):
      return failure(code: CLIErrorCode.dispatchAlreadyTerminal, message: "The dispatch is already terminal.")
    case .failure:
      return failure(code: CLIErrorCode.dispatchFailed, message: "The dispatch receipt could not be abandoned.")
    case .success(let result):
      guard let binding = result.snapshot.binding,
        case .abandoned(let record) = result.snapshot.payload(using: formatter)
      else {
        return failure(code: CLIErrorCode.dispatchFailed, message: "The dispatch has no bound pane.")
      }
      do {
        return try CommandResponse(
          ok: true,
          command: "agents.dispatch-abandon",
          schemaVersion: "prowl.cli.agents.dispatch-abandon.v1",
          data: RawJSON(
            encoding: DispatchAbandonCommandPayload(
              target: binding.target,
              record: record,
              replayed: result.replayed
            ))
        )
      } catch {
        return failure(code: CLIErrorCode.dispatchFailed, message: "Failed to encode the abandoned dispatch.")
      }
    }
  }

  private func failure(code: String, message: String) -> CommandResponse {
    CommandResponse(
      ok: false,
      command: "agents.dispatch-abandon",
      schemaVersion: "prowl.cli.agents.dispatch-abandon.v1",
      error: CommandError(code: code, message: message)
    )
  }
}
