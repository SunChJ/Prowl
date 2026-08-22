import Foundation

@MainActor
final class AgentSignalCommandHandler: CommandHandler {
  typealias ResolveCaller = @MainActor (pid_t) -> CallerPane?
  typealias RecordSignal = @MainActor (CallerPane, AgentSignal) -> Bool

  private let resolveCaller: ResolveCaller
  private let recordSignal: RecordSignal
  private let now: @Sendable () -> Date
  private let dateFormatter: ISO8601DateFormatter

  init(
    resolveCaller: @escaping ResolveCaller,
    recordSignal: @escaping RecordSignal,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.resolveCaller = resolveCaller
    self.recordSignal = recordSignal
    self.now = now
    self.dateFormatter = ISO8601DateFormatter()
    self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    self.dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
  }

  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    await handle(envelope: envelope, context: CLICommandContext())
  }

  // swiftlint:disable async_without_await
  func handle(
    envelope: CommandEnvelope,
    context: CLICommandContext
  ) async -> CommandResponse {
    guard case .agentsSignal(let input) = envelope.command else {
      return failure(code: CLIErrorCode.invalidArgument, message: "Expected an agents.signal command.")
    }
    if let validationMessage = input.validationErrorMessage {
      return failure(code: CLIErrorCode.invalidArgument, message: validationMessage)
    }
    guard let processID = context.callerProcessID,
      let caller = resolveCaller(processID)
    else {
      return failure(
        code: CLIErrorCode.sourceRequired,
        message: "Run 'prowl agents signal' from inside the Prowl pane that is reporting the event."
      )
    }

    let signal = AgentSignal(
      kind: kind(for: input),
      source: .cooperativeCLI,
      confidence: .exact,
      timestamp: now(),
      sessionID: input.sessionID,
      detail: input.detail,
      claimedOrigin: input.origin
    )
    guard recordSignal(caller, signal) else {
      return failure(
        code: CLIErrorCode.agentGone,
        message: "The caller pane closed before its agent signal could be recorded."
      )
    }

    let payload = AgentSignalCommandPayload(
      pane: AgentSignalPanePayload(
        id: caller.surfaceID.uuidString,
        worktreeID: caller.worktreeID
      ),
      signal: AgentSignalPayload(
        event: input.event,
        progress: input.progress,
        source: "cooperative_cli",
        confidence: signal.confidence.rawValue,
        timestamp: dateFormatter.string(from: signal.timestamp),
        sessionID: signal.sessionID,
        detail: signal.detail,
        claimedOrigin: signal.claimedOrigin
      )
    )
    do {
      return try CommandResponse(
        ok: true,
        command: "agents.signal",
        schemaVersion: "prowl.cli.agents.signal.v1",
        data: RawJSON(encoding: payload)
      )
    } catch {
      return failure(code: CLIErrorCode.agentsFailed, message: "Failed to encode the agent signal receipt.")
    }
  }
  // swiftlint:enable async_without_await

  private func kind(for input: AgentSignalInput) -> AgentSignal.Kind {
    switch input.event {
    case .turnEnded: .turnEnded
    case .needsInput: .needsInput
    case .sessionStart: .sessionStart
    case .sessionEnd: .sessionEnd
    case .progress: .progress(input.progress)
    }
  }

  private func failure(code: String, message: String) -> CommandResponse {
    CommandResponse(
      ok: false,
      command: "agents.signal",
      schemaVersion: "prowl.cli.agents.signal.v1",
      error: CommandError(code: code, message: message)
    )
  }
}
