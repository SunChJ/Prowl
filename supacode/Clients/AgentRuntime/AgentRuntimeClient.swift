import ComposableArchitecture
import Foundation

/// Executes a headless, read-only resume of a verified agent session and
/// returns the agent's final reply text. The resumed agent only replies with
/// content; Prowl itself validates and persists any artifact derived from it.
nonisolated struct AgentRuntimeClient: Sendable {
  private var resumeImpl: @Sendable (AgentResumeRequest, URL) async throws -> String

  init(resume: @escaping @Sendable (AgentResumeRequest, URL) async throws -> String) {
    self.resumeImpl = resume
  }

  func resume(_ request: AgentResumeRequest, in workingDirectory: URL) async throws -> String {
    try await resumeImpl(request, workingDirectory)
  }

  /// Bounds one resume turn; a stalled CLI must not hang `handoff save` or the
  /// Command Palette handoff indefinitely.
  static let resumeTimeout: Duration = .seconds(120)

  static func live(shell: ShellClient, clock: any Clock<Duration> = ContinuousClock()) -> Self {
    Self(
      resume: { request, workingDirectory in
        let replyFile = FileManager.default.temporaryDirectory
          .appending(path: "prowl-agent-reply-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: replyFile) }
        let invocation = try AgentRuntimeAdapterRegistry.makeResumeInvocation(request, replyFile: replyFile)
        let output = try await withResumeTimeout(clock: clock) {
          try await shell.runLogin(
            URL(fileURLWithPath: "/usr/bin/env"),
            [invocation.executable] + invocation.arguments,
            workingDirectory,
            log: false
          )
        }
        // Prefer the CLI-written reply file (codex); fall back to stdout (claude).
        let fileReply = (try? String(contentsOf: replyFile, encoding: .utf8))?
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if let fileReply, !fileReply.isEmpty {
          return fileReply
        }
        return output.stdout
      }
    )
  }

  private static func withResumeTimeout(
    clock: any Clock<Duration>,
    operation: @escaping @Sendable () async throws -> ShellOutput
  ) async throws -> ShellOutput {
    try await withThrowingTaskGroup(of: ShellOutput.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await clock.sleep(for: resumeTimeout)
        throw AgentRuntimeError.resumeTimedOut
      }
      guard let output = try await group.next() else {
        throw AgentRuntimeError.resumeTimedOut
      }
      group.cancelAll()
      return output
    }
  }
}

extension AgentRuntimeClient: DependencyKey {
  nonisolated static let liveValue = AgentRuntimeClient.live(shell: .live)

  nonisolated static let testValue = AgentRuntimeClient(
    resume: { _, _ in
      reportIssue("AgentRuntimeClient.resume is unimplemented")
      throw UnimplementedAgentRuntimeError()
    }
  )
}

private struct UnimplementedAgentRuntimeError: Error {}

extension DependencyValues {
  var agentRuntimeClient: AgentRuntimeClient {
    get { self[AgentRuntimeClient.self] }
    set { self[AgentRuntimeClient.self] = newValue }
  }
}
