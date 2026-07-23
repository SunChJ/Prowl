import Foundation

nonisolated protocol AgentRuntimeAdapter: Sendable {
  var agent: DetectedAgent { get }
  /// Human-readable product name for UI entry points ("Claude Code").
  var displayName: String { get }

  func observe(arguments: [String]) -> AgentLaunchObservation
  func makeStartInvocation(_ request: AgentStartRequest) throws -> AgentInvocation
  /// Resume is side-effect-free by design: the invocation never renders
  /// execution-mode flags, and it must not mutate the source session's recorded
  /// state (fork/ephemeral variants only). The resumed agent replies with
  /// content; Prowl persists any artifact. `replyFile`, when supported, asks the
  /// CLI to write its final message there.
  func makeResumeInvocation(_ request: AgentResumeRequest, replyFile: URL?) throws -> AgentInvocation
}

nonisolated enum AgentExecutionMode: String, Codable, Equatable, Sendable {
  case standard
  case unrestricted
}

nonisolated struct AgentLaunchConfiguration: Codable, Equatable, Sendable {
  var model: String?
  var executionMode: AgentExecutionMode

  init(model: String? = nil, executionMode: AgentExecutionMode = .standard) {
    self.model = model
    self.executionMode = executionMode
  }
}

/// Options observed from a live agent process. Nil denotes an unknown effective setting,
/// never an inferred safe default from the absence of an argv flag.
nonisolated struct AgentLaunchObservation: Equatable, Sendable {
  let model: String?
  let executionMode: AgentExecutionMode?

  init(model: String? = nil, executionMode: AgentExecutionMode? = nil) {
    self.model = model
    self.executionMode = executionMode
  }
}

nonisolated struct AgentStartRequest: Equatable, Sendable {
  let agent: DetectedAgent
  let prompt: String
  let configuration: AgentLaunchConfiguration

  init(agent: DetectedAgent, prompt: String, configuration: AgentLaunchConfiguration = .init()) {
    self.agent = agent
    self.prompt = prompt
    self.configuration = configuration
  }
}

/// A headless, read-only resume of a verified native session. Unlike
/// `AgentStartRequest` it carries no execution mode: a resume never escalates
/// permissions, so only the same-adapter model can be inherited.
nonisolated struct AgentResumeRequest: Equatable, Sendable {
  let agent: DetectedAgent
  let session: AgentSession
  let prompt: String
  let model: String?

  init(
    agent: DetectedAgent,
    session: AgentSession,
    prompt: String,
    model: String? = nil
  ) {
    self.agent = agent
    self.session = session
    self.prompt = prompt
    self.model = model
  }
}

nonisolated struct AgentInvocation: Equatable, Sendable {
  let executable: String
  let arguments: [String]

  init(executable: String, arguments: [String]) {
    self.executable = executable
    self.arguments = arguments
  }

  /// One reviewed POSIX-shell rendering path for a command injected into a terminal surface.
  var terminalInput: String {
    ([executable] + arguments).map(Self.shellQuote).joined(separator: " ")
  }

  private static func shellQuote(_ argument: String) -> String {
    "'" + argument.replacing("'", with: "'\"'\"'") + "'"
  }
}

nonisolated enum AgentRuntimeError: Error, Equatable, Sendable {
  case unsupportedAgent(DetectedAgent)
  case unsafeSessionConfidence(AgentSession.Confidence)
  case resumeTimedOut
}

nonisolated enum AgentRuntimeAdapterRegistry {
  static func adapter(for agent: DetectedAgent) -> (any AgentRuntimeAdapter)? {
    switch agent {
    case .claude: ClaudeCodeRuntimeAdapter()
    case .codex: CodexRuntimeAdapter()
    default: nil
    }
  }

  /// Agents with a verified interactive launch adapter, in catalog order.
  /// UI entry points derive their handoff targets from this list.
  static var launchableAgents: [DetectedAgent] {
    DetectedAgent.allCases.filter { adapter(for: $0) != nil }
  }

  static func displayName(for agent: DetectedAgent) -> String {
    adapter(for: agent)?.displayName ?? agent.displayName
  }

  static func canStart(_ agent: DetectedAgent) -> Bool {
    adapter(for: agent) != nil
  }

  static func canResume(_ agent: DetectedAgent) -> Bool {
    adapter(for: agent) != nil
  }

  static func observe(agent: DetectedAgent, arguments: [String]) -> AgentLaunchObservation {
    adapter(for: agent)?.observe(arguments: arguments) ?? .init()
  }

  static func inheritedConfiguration(
    from sourceAgent: DetectedAgent,
    observation: AgentLaunchObservation?,
    to destinationAgent: DetectedAgent
  ) -> AgentLaunchConfiguration {
    AgentLaunchConfiguration(
      model: sourceAgent == destinationAgent ? observation?.model : nil,
      executionMode: observation?.executionMode ?? .standard
    )
  }

  static func makeStartInvocation(_ request: AgentStartRequest) throws -> AgentInvocation {
    guard let adapter = adapter(for: request.agent) else {
      throw AgentRuntimeError.unsupportedAgent(request.agent)
    }
    return try adapter.makeStartInvocation(request)
  }

  static func makeResumeInvocation(_ request: AgentResumeRequest, replyFile: URL? = nil) throws -> AgentInvocation {
    guard request.session.confidence == .exact || request.session.confidence == .high else {
      throw AgentRuntimeError.unsafeSessionConfidence(request.session.confidence)
    }
    guard let adapter = adapter(for: request.agent) else {
      throw AgentRuntimeError.unsupportedAgent(request.agent)
    }
    return try adapter.makeResumeInvocation(request, replyFile: replyFile)
  }
}

nonisolated private struct CodexRuntimeAdapter: AgentRuntimeAdapter {
  let agent: DetectedAgent = .codex
  let displayName = "Codex"

  func observe(arguments: [String]) -> AgentLaunchObservation {
    let explicitlyBypassesSandbox =
      arguments.contains("--dangerously-bypass-approvals-and-sandbox")
      || arguments.contains("--yolo")
    return AgentLaunchObservation(
      model: arguments.optionValue(long: "--model", short: "-m"),
      executionMode: explicitlyBypassesSandbox ? .unrestricted : nil
    )
  }

  func makeStartInvocation(_ request: AgentStartRequest) throws -> AgentInvocation {
    AgentInvocation(executable: "codex", arguments: options(for: request.configuration) + [request.prompt])
  }

  func makeResumeInvocation(_ request: AgentResumeRequest, replyFile: URL?) throws -> AgentInvocation {
    // `--ephemeral` keeps the preparation turn out of `~/.codex/sessions`, so a
    // resume never mutates the recorded state of the live source session.
    var arguments = ["exec", "resume", "--ephemeral"]
    if let model = request.model {
      arguments += ["--model", model]
    }
    if let replyFile {
      arguments += ["--output-last-message", replyFile.path(percentEncoded: false)]
    }
    return AgentInvocation(
      executable: "codex",
      arguments: arguments + [request.session.id, request.prompt]
    )
  }

  private func options(for configuration: AgentLaunchConfiguration) -> [String] {
    var options: [String] = []
    if let model = configuration.model {
      options += ["--model", model]
    }
    if configuration.executionMode == .unrestricted {
      options.append("--dangerously-bypass-approvals-and-sandbox")
    }
    return options
  }
}

nonisolated private struct ClaudeCodeRuntimeAdapter: AgentRuntimeAdapter {
  let agent: DetectedAgent = .claude
  let displayName = "Claude Code"

  func observe(arguments: [String]) -> AgentLaunchObservation {
    let explicitlyBypassesPermissions =
      arguments.contains("--dangerously-skip-permissions")
      || arguments.optionValue(long: "--permission-mode") == "bypassPermissions"
    return AgentLaunchObservation(
      model: arguments.optionValue(long: "--model", short: "-m"),
      executionMode: explicitlyBypassesPermissions ? .unrestricted : nil
    )
  }

  func makeStartInvocation(_ request: AgentStartRequest) throws -> AgentInvocation {
    AgentInvocation(executable: "claude", arguments: options(for: request.configuration) + [request.prompt])
  }

  func makeResumeInvocation(_ request: AgentResumeRequest, replyFile: URL?) throws -> AgentInvocation {
    // `claude -p` prints only the final reply on stdout, so no reply file is needed.
    // `--fork-session` is load-bearing: without it `--resume` continues the same
    // session ID and appends the preparation turn to the transcript of a session
    // that is usually still live in the pane (dual-writer on one JSONL).
    var arguments = ["-p", "--fork-session", "--resume", request.session.id]
    if let model = request.model {
      arguments += ["--model", model]
    }
    return AgentInvocation(executable: "claude", arguments: arguments + [request.prompt])
  }

  private func options(for configuration: AgentLaunchConfiguration) -> [String] {
    var options: [String] = []
    if let model = configuration.model {
      options += ["--model", model]
    }
    if configuration.executionMode == .unrestricted {
      options.append("--dangerously-skip-permissions")
    }
    return options
  }
}

nonisolated extension [String] {
  fileprivate func optionValue(long: String, short: String? = nil) -> String? {
    for (index, argument) in enumerated() {
      if argument == long || short == argument {
        let next = self.index(after: index)
        guard next < endIndex else { return nil }
        return self[next]
      }
      if argument.hasPrefix(long + "=") {
        return String(argument.dropFirst(long.count + 1))
      }
    }
    return nil
  }
}
