import Clocks
import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

struct AgentRuntimeAdapterTests {
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

  @Test func modelSuggestionsMatchEachRuntime() {
    let codex = AgentRuntimeAdapterRegistry.adapter(for: .codex)
    #expect(codex?.modelSuggestions == ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.3-codex-spark"])

    let claude = AgentRuntimeAdapterRegistry.adapter(for: .claude)
    #expect(claude?.modelSuggestions == ["fable", "opus", "sonnet", "haiku", "opusplan"])
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
