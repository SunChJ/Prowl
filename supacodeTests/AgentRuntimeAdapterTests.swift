import Clocks
import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

struct AgentRuntimeAdapterTests {
  private struct CatalogExpectation {
    let runtime: AgentProfileRuntime
    let agent: DetectedAgent
    let executable: String
    let arguments: [String]
  }

  private struct IntentExpectation {
    let runtime: AgentProfileRuntime
    let promptedArguments: [String]
    let headlessArguments: [String]
  }

  @Test func profileRuntimeCatalogCoversEveryLaunchableCLI() throws {
    let expected = [
      CatalogExpectation(runtime: .claude, agent: .claude, executable: "claude", arguments: []),
      CatalogExpectation(runtime: .codex, agent: .codex, executable: "codex", arguments: []),
      CatalogExpectation(runtime: .gemini, agent: .gemini, executable: "gemini", arguments: []),
      CatalogExpectation(runtime: .cursor, agent: .cursor, executable: "cursor-agent", arguments: []),
      CatalogExpectation(runtime: .cline, agent: .cline, executable: "cline", arguments: ["--tui"]),
      CatalogExpectation(runtime: .opencode, agent: .opencode, executable: "opencode", arguments: []),
      CatalogExpectation(runtime: .copilot, agent: .copilot, executable: "copilot", arguments: []),
      CatalogExpectation(runtime: .kimi, agent: .kimi, executable: "kimi", arguments: []),
      CatalogExpectation(runtime: .droid, agent: .droid, executable: "droid", arguments: []),
      CatalogExpectation(runtime: .amp, agent: .amp, executable: "amp", arguments: []),
      CatalogExpectation(runtime: .qoder, agent: .qoder, executable: "qodercli", arguments: []),
      CatalogExpectation(runtime: .qwen, agent: .qwen, executable: "qwen", arguments: []),
      CatalogExpectation(runtime: .grok, agent: .grok, executable: "grok", arguments: []),
      CatalogExpectation(runtime: .pi, agent: .pi, executable: "pi", arguments: []),
      CatalogExpectation(runtime: .omp, agent: .pi, executable: "omp", arguments: []),
    ]

    #expect(AgentProfileRuntime.allCases.count == expected.count)
    for expectation in expected {
      let invocation = try AgentRuntimeAdapterRegistry.makeStartInvocation(
        AgentStartRequest(runtime: expectation.runtime, intent: .interactive)
      )
      #expect(expectation.runtime.agent == expectation.agent)
      #expect(invocation.executable == expectation.executable)
      #expect(invocation.arguments == expectation.arguments)
    }
    #expect(AgentRuntimeAdapterRegistry.launchableAgents == DetectedAgent.allCases)
  }

  @Test func promptedAndHeadlessStartsUseRuntimeSpecificCLISemantics() throws {
    let expected = [
      IntentExpectation(
        runtime: .claude, promptedArguments: ["Review this."], headlessArguments: ["-p", "Review this."]),
      IntentExpectation(
        runtime: .codex, promptedArguments: ["Review this."], headlessArguments: ["exec", "Review this."]),
      IntentExpectation(
        runtime: .gemini, promptedArguments: ["--prompt-interactive", "Review this."],
        headlessArguments: ["--prompt", "Review this."]),
      IntentExpectation(
        runtime: .cursor, promptedArguments: ["Review this."], headlessArguments: ["--print", "Review this."]),
      IntentExpectation(
        runtime: .cline, promptedArguments: ["--tui", "Review this."], headlessArguments: ["Review this."]),
      IntentExpectation(
        runtime: .opencode, promptedArguments: ["--prompt", "Review this."],
        headlessArguments: ["run", "Review this."]),
      IntentExpectation(
        runtime: .copilot, promptedArguments: ["--interactive", "Review this."],
        headlessArguments: ["--prompt", "Review this."]),
      IntentExpectation(
        runtime: .kimi, promptedArguments: ["--prompt", "Review this."],
        headlessArguments: ["--print", "--prompt", "Review this."]),
      IntentExpectation(
        runtime: .droid, promptedArguments: ["Review this."], headlessArguments: ["exec", "Review this."]),
      IntentExpectation(
        runtime: .qoder, promptedArguments: ["--prompt-interactive", "Review this."],
        headlessArguments: ["--print", "Review this."]),
      IntentExpectation(
        runtime: .qwen, promptedArguments: ["--prompt-interactive", "Review this."],
        headlessArguments: ["--prompt", "Review this."]),
      IntentExpectation(
        runtime: .grok, promptedArguments: ["Review this."], headlessArguments: ["--single", "Review this."]),
      IntentExpectation(
        runtime: .pi, promptedArguments: ["Review this."], headlessArguments: ["--print", "Review this."]),
      IntentExpectation(
        runtime: .omp, promptedArguments: ["Review this."], headlessArguments: ["--print", "Review this."]),
    ]

    for expectation in expected {
      let prompted = try AgentRuntimeAdapterRegistry.makeStartInvocation(
        AgentStartRequest(runtime: expectation.runtime, intent: .prompt("Review this."))
      )
      let headless = try AgentRuntimeAdapterRegistry.makeStartInvocation(
        AgentStartRequest(runtime: expectation.runtime, intent: .headless("Review this."))
      )
      #expect(prompted.arguments == expectation.promptedArguments)
      #expect(headless.arguments == expectation.headlessArguments)
    }

    #expect(
      throws: AgentRuntimeError.unsupportedStartIntent(.amp, .prompt("Review this."))
    ) {
      try AgentRuntimeAdapterRegistry.makeStartInvocation(
        AgentStartRequest(runtime: .amp, intent: .prompt("Review this."))
      )
    }
    let ampHeadless = try AgentRuntimeAdapterRegistry.makeStartInvocation(
      AgentStartRequest(runtime: .amp, intent: .headless("Review this."))
    )
    #expect(ampHeadless.arguments == ["--execute", "Review this."])
  }

  @Test func profileOptionsAreCapabilityGated() throws {
    let noModel: Set<AgentProfileRuntime> = [.droid, .amp]
    let noReasoning: Set<AgentProfileRuntime> = [.gemini, .cursor, .kimi, .droid]
    let unrestricted: Set<AgentProfileRuntime> = [
      .claude, .codex, .gemini, .cursor, .opencode, .copilot, .kimi, .qoder, .qwen, .omp,
    ]
    let isolated: Set<AgentProfileRuntime> = [
      .claude, .codex, .gemini, .cline, .copilot, .qoder, .qwen, .pi, .omp,
    ]

    for runtime in AgentProfileRuntime.allCases {
      let adapter = try #require(AgentRuntimeAdapterRegistry.profileAdapter(for: runtime))
      #expect(adapter.supportsModelSelection == !noModel.contains(runtime))
      #expect(adapter.supportsReasoningEffort == !noReasoning.contains(runtime))
      #expect(adapter.supportsUnrestrictedExecution == unrestricted.contains(runtime))
      #expect(adapter.supportsAccountIsolation == isolated.contains(runtime))
    }
  }

  @Test func expandedRuntimeOptionsRenderOnlyVerifiedFields() throws {
    let configuration = AgentLaunchConfiguration(
      model: "model-x",
      executionMode: .unrestricted,
      reasoningEffort: "high"
    )
    let expected: [(AgentProfileRuntime, [String])] = [
      (.gemini, ["--model", "model-x", "--approval-mode", "yolo", "--sandbox=false"]),
      (.cursor, ["--model", "model-x", "--yolo", "--sandbox", "disabled"]),
      (.cline, ["--model", "model-x", "--thinking", "high", "--tui"]),
      (.opencode, ["--model", "model-x", "--variant", "high", "--auto"]),
      (.copilot, ["--model", "model-x", "--reasoning-effort", "high", "--allow-all"]),
      (.kimi, ["--model", "model-x", "--yolo"]),
      (.droid, []),
      (.amp, ["--effort", "high"]),
      (.qoder, ["--model", "model-x", "--reasoning-effort", "high", "--dangerously-skip-permissions"]),
      (.qwen, ["--model", "model-x", "--reasoning-effort", "high", "--approval-mode", "yolo", "--sandbox=false"]),
      (.grok, ["--model", "model-x", "--reasoning-effort", "high"]),
      (.pi, ["--model", "model-x", "--thinking", "high"]),
      (.omp, ["--model", "model-x", "--thinking", "high", "--approval-mode", "yolo"]),
    ]

    for (runtime, arguments) in expected {
      let invocation = try AgentRuntimeAdapterRegistry.makeStartInvocation(
        AgentStartRequest(runtime: runtime, intent: .interactive, configuration: configuration)
      )
      #expect(invocation.arguments == arguments)
    }
  }

  @Test func startAndResumeCapabilitiesAreIndependent() {
    for agent in DetectedAgent.allCases {
      #expect(AgentRuntimeAdapterRegistry.canStart(agent))
      #expect(AgentRuntimeAdapterRegistry.canResume(agent) == (agent == .claude || agent == .codex))
    }
  }

  @Test func codexStartBuildsUnrestrictedInvocation() throws {
    let invocation = try AgentRuntimeAdapterRegistry.makeStartInvocation(
      AgentStartRequest(
        agent: .codex,
        intent: .prompt("Continue the handoff."),
        configuration: AgentLaunchConfiguration(model: "gpt-5.4", executionMode: .unrestricted)
      )
    )

    #expect(invocation.executable == "codex")
    #expect(
      invocation.arguments
        == ["--model", "gpt-5.4", "--dangerously-bypass-approvals-and-sandbox", "Continue the handoff."]
    )
  }

  @Test func interactiveStartRendersNoPromptArgument() throws {
    let codex = try AgentRuntimeAdapterRegistry.makeStartInvocation(
      AgentStartRequest(agent: .codex, intent: .interactive)
    )
    #expect(codex.executable == "codex")
    #expect(codex.arguments.isEmpty)

    let claude = try AgentRuntimeAdapterRegistry.makeStartInvocation(
      AgentStartRequest(
        agent: .claude,
        intent: .interactive,
        configuration: AgentLaunchConfiguration(model: "claude-opus-5")
      )
    )
    #expect(claude.executable == "claude")
    #expect(claude.arguments == ["--model", "claude-opus-5"])
  }

  @Test func headlessStartRendersOneShotExecutionMode() throws {
    let codex = try AgentRuntimeAdapterRegistry.makeStartInvocation(
      AgentStartRequest(agent: .codex, intent: .headless("Summarize the repo."))
    )
    #expect(codex.arguments == ["exec", "Summarize the repo."])

    let claude = try AgentRuntimeAdapterRegistry.makeStartInvocation(
      AgentStartRequest(agent: .claude, intent: .headless("Summarize the repo."))
    )
    #expect(claude.arguments == ["-p", "Summarize the repo."])
  }

  @Test func reasoningEffortMapsToRuntimeSpecificOptions() throws {
    let claude = try AgentRuntimeAdapterRegistry.makeStartInvocation(
      AgentStartRequest(
        agent: .claude,
        intent: .interactive,
        configuration: AgentLaunchConfiguration(reasoningEffort: "high")
      )
    )
    #expect(claude.arguments == ["--effort", "high"])

    let codex = try AgentRuntimeAdapterRegistry.makeStartInvocation(
      AgentStartRequest(
        agent: .codex,
        intent: .interactive,
        configuration: AgentLaunchConfiguration(reasoningEffort: "xhigh")
      )
    )
    #expect(codex.arguments == ["-c", "model_reasoning_effort=xhigh"])
  }

  @Test func extraArgumentsAppendAfterAdapterOptionsBeforePrompt() throws {
    let invocation = try AgentRuntimeAdapterRegistry.makeStartInvocation(
      AgentStartRequest(
        agent: .codex,
        intent: .prompt("Go."),
        configuration: AgentLaunchConfiguration(
          model: "gpt-5.4",
          extraArguments: ["--search", "--cd", "/tmp/with space"]
        )
      )
    )
    #expect(
      invocation.arguments == ["--model", "gpt-5.4", "--search", "--cd", "/tmp/with space", "Go."]
    )
  }

  @Test func accountIsolationCapabilityIsDeclaredPerAdapter() {
    let codex = AgentRuntimeAdapterRegistry.adapter(for: .codex)
    #expect(codex?.supportsAccountIsolation == true)
    #expect(codex?.accountHomeEnvironmentVariable == "CODEX_HOME")

    let claude = AgentRuntimeAdapterRegistry.adapter(for: .claude)
    #expect(claude?.supportsAccountIsolation == true)
    #expect(claude?.accountHomeEnvironmentVariable == "CLAUDE_CONFIG_DIR")
    #expect(claude?.reasoningEffortSuggestions.contains("high") == true)
  }

  @Test func runtimeSuggestionsMatchCurrentCapabilities() {
    let codex = AgentRuntimeAdapterRegistry.adapter(for: .codex)
    #expect(codex?.modelSuggestions == ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"])
    #expect(codex?.reasoningEffortSuggestions == ["low", "medium", "high", "xhigh", "max"])

    let claude = AgentRuntimeAdapterRegistry.adapter(for: .claude)
    #expect(
      claude?.modelSuggestions
        == ["claude-fable-5", "claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5-20251001"]
    )
    #expect(claude?.reasoningEffortSuggestions == ["low", "medium", "high", "xhigh", "max"])
  }

  @Test func launchConfigurationDecodesLegacyPayloadWithoutNewFields() throws {
    let legacy = Data(#"{"model":"gpt-5.4","executionMode":"standard"}"#.utf8)
    let configuration = try JSONDecoder().decode(AgentLaunchConfiguration.self, from: legacy)
    #expect(configuration.model == "gpt-5.4")
    #expect(configuration.reasoningEffort == nil)
    #expect(configuration.extraArguments.isEmpty)
  }

  @Test func claudeResumeStaysReadOnlyAndKeepsModel() throws {
    let session = AgentSession(
      id: "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
      transcriptPath: nil,
      source: .openFile,
      confidence: .exact
    )
    let invocation = try AgentRuntimeAdapterRegistry.makeResumeInvocation(
      AgentResumeRequest(
        agent: .claude,
        session: session,
        prompt: "Reply with the handoff artifact.",
        model: "claude-opus-4"
      )
    )

    #expect(invocation.executable == "claude")
    #expect(
      invocation.arguments
        == [
          "-p",
          "--fork-session",
          "--resume",
          "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
          "--model",
          "claude-opus-4",
          "Reply with the handoff artifact.",
        ]
    )
  }

  @Test func codexResumeWritesReplyFileAndStaysReadOnly() throws {
    let session = AgentSession(
      id: "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
      transcriptPath: nil,
      source: .openFile,
      confidence: .high
    )
    let replyFile = URL(fileURLWithPath: "/tmp/prowl-agent-reply.md")
    let invocation = try AgentRuntimeAdapterRegistry.makeResumeInvocation(
      AgentResumeRequest(
        agent: .codex,
        session: session,
        prompt: "Reply with the handoff artifact.",
        model: "gpt-5.4"
      ),
      replyFile: replyFile
    )

    #expect(invocation.executable == "codex")
    #expect(
      invocation.arguments
        == [
          "exec",
          "resume",
          "--ephemeral",
          "--model",
          "gpt-5.4",
          "--output-last-message",
          "/tmp/prowl-agent-reply.md",
          "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
          "Reply with the handoff artifact.",
        ]
    )
  }

  @Test func observedLaunchOnlyClaimsExplicitUnrestrictedMode() {
    let codex = AgentRuntimeAdapterRegistry.observe(
      agent: .codex,
      arguments: ["codex", "--model", "gpt-5.4", "--dangerously-bypass-approvals-and-sandbox"]
    )
    #expect(codex.model == "gpt-5.4")
    #expect(codex.executionMode == .unrestricted)

    let yolo = AgentRuntimeAdapterRegistry.observe(agent: .codex, arguments: ["codex", "--yolo"])
    #expect(yolo.executionMode == .unrestricted)

    let claude = AgentRuntimeAdapterRegistry.observe(
      agent: .claude,
      arguments: ["claude", "--allow-dangerously-skip-permissions"]
    )
    #expect(claude.executionMode == nil)
  }

  @Test func inheritedConfigurationCarriesOnlyPortableSourceIntent() {
    let observation = AgentLaunchObservation(model: "gpt-5.4", executionMode: .unrestricted)

    let claude = AgentRuntimeAdapterRegistry.inheritedConfiguration(
      from: .codex,
      observation: observation,
      to: .claude
    )
    #expect(claude.model == nil)
    #expect(claude.executionMode == .unrestricted)

    let codex = AgentRuntimeAdapterRegistry.inheritedConfiguration(
      from: .codex,
      observation: observation,
      to: .codex
    )
    #expect(codex.model == "gpt-5.4")
    #expect(codex.executionMode == .unrestricted)
  }

  @Test func resumeRejectsMediumConfidenceSession() throws {
    let session = AgentSession(
      id: "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
      transcriptPath: nil,
      source: .recentFile,
      confidence: .medium
    )

    #expect(throws: AgentRuntimeError.self) {
      try AgentRuntimeAdapterRegistry.makeResumeInvocation(
        AgentResumeRequest(agent: .codex, session: session, prompt: "Summarize the task.")
      )
    }
  }

  @Test func terminalInputQuotesEveryArgument() {
    let invocation = AgentInvocation(
      executable: "codex",
      arguments: ["exec", "resume", "session id", "Write 'current.md'\nwithout shell injection."]
    )

    #expect(
      invocation.terminalInput
        == "'codex' 'exec' 'resume' 'session id' 'Write '\"'\"'current.md'\"'\"'\nwithout shell injection.'"
    )
  }

  @Test func runtimeClientRunsResumeThroughDirectArgv() async throws {
    let recordedExecutable = LockIsolated<URL?>(nil)
    let recordedArguments = LockIsolated<[String]>([])
    let recordedDirectory = LockIsolated<URL?>(nil)
    let recordedLog = LockIsolated<Bool?>(nil)
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { executable, arguments, directory, log in
        recordedExecutable.setValue(executable)
        recordedArguments.setValue(arguments)
        recordedDirectory.setValue(directory)
        recordedLog.setValue(log)
        return ShellOutput(stdout: "## Objective\nreply", stderr: "", exitCode: 0)
      }
    )
    let directory = URL(fileURLWithPath: "/tmp/handoff", isDirectory: true)
    let session = AgentSession(
      id: "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
      transcriptPath: nil,
      source: .openFile,
      confidence: .high
    )

    let reply = try await AgentRuntimeClient.live(shell: shell).resume(
      AgentResumeRequest(
        agent: .codex,
        session: session,
        prompt: "Reply with the handoff artifact."
      ),
      in: directory
    )

    // The stub never writes the reply file, so stdout is the reply.
    #expect(reply == "## Objective\nreply")
    #expect(recordedExecutable.value?.path == "/usr/bin/env")
    let arguments = recordedArguments.value
    #expect(arguments.prefix(4) == ["codex", "exec", "resume", "--ephemeral"])
    #expect(arguments.contains("--output-last-message"))
    #expect(!arguments.contains("--dangerously-bypass-approvals-and-sandbox"))
    #expect(
      arguments.suffix(2)
        == ["9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711", "Reply with the handoff artifact."]
    )
    #expect(recordedDirectory.value == directory)
    #expect(recordedLog.value == false)
  }

  @Test func runtimeClientPrefersReplyFileOverStdout() async throws {
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { _, arguments, _, _ in
        if let flagIndex = arguments.firstIndex(of: "--output-last-message"),
          arguments.indices.contains(flagIndex + 1)
        {
          try "## Objective\nfrom reply file\n".write(
            to: URL(fileURLWithPath: arguments[flagIndex + 1]),
            atomically: true,
            encoding: .utf8
          )
        }
        return ShellOutput(stdout: "event noise", stderr: "", exitCode: 0)
      }
    )
    let session = AgentSession(
      id: "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
      transcriptPath: nil,
      source: .openFile,
      confidence: .high
    )

    let reply = try await AgentRuntimeClient.live(shell: shell).resume(
      AgentResumeRequest(agent: .codex, session: session, prompt: "Reply with the handoff artifact."),
      in: URL(fileURLWithPath: "/tmp/handoff", isDirectory: true)
    )

    #expect(reply == "## Objective\nfrom reply file")
  }

  @Test func runtimeClientTimesOutStalledResume() async {
    let hang = TestClock()
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { _, _, _, _ in
        try await hang.sleep(for: .seconds(600))
        return ShellOutput(stdout: "late", stderr: "", exitCode: 0)
      }
    )
    let session = AgentSession(
      id: "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
      transcriptPath: nil,
      source: .openFile,
      confidence: .high
    )

    await #expect(throws: AgentRuntimeError.resumeTimedOut) {
      _ = try await AgentRuntimeClient.live(shell: shell, clock: ImmediateClock()).resume(
        AgentResumeRequest(agent: .claude, session: session, prompt: "Reply with the handoff artifact."),
        in: URL(fileURLWithPath: "/tmp/handoff", isDirectory: true)
      )
    }
  }
}
