import Foundation
import Testing

@testable import supacode

struct AgentProfileHookCarrierTests {
  @Test func managedHookValuesUseChildOnlyCarriersAndNeverTerminalInput() throws {
    let base = makePlan(
      invocation: AgentInvocation(executable: "claude", arguments: ["-p", "Prompt"]),
      prompt: "Prompt"
    )
    let preparedInvocation = AgentHookPreparedInvocation(
      invocation: AgentInvocation(executable: "claude", arguments: ["-p", "--settings", "{}", "Prompt"]),
      argumentValues: [2: #"{"secret":"hook-json"}"#]
    )
    let token = "token-should-never-be-typed"
    let socket = "/tmp/prowl custom.sock"
    let prepared = base.applyingManagedHook(
      preparedInvocation,
      resources: AgentHookResources(
        bundledCLIPath: "/Applications/Prowl Debug.app/Contents/Resources/prowl-cli/prowl",
        socketPath: socket
      ),
      launchCWD: URL(filePath: "/tmp/Project Space/界", directoryHint: .isDirectory),
      token: token,
      coveredEvents: [.needsInput, .sessionStart, .turnEnded]
    )

    #expect(prepared.hookRegistration?.token == token)
    #expect(
      prepared.hookRegistration?.launchCWD.path(percentEncoded: false).trimmingCharacters(
        in: CharacterSet(charactersIn: "/"))
        == "tmp/Project Space/界"
    )
    #expect(prepared.terminalInput.contains("\"$PROWL_LAUNCH_HOOK_ARG_0\""))
    #expect(prepared.terminalInput.contains("-u PROWL_LAUNCH_HOOK_TOKEN"))
    #expect(prepared.terminalInput.contains("-u PROWL_LAUNCH_HOOK_SOCKET"))
    #expect(prepared.terminalInput.contains("PROWL_AGENT_HOOK_TOKEN=\"$PROWL_LAUNCH_HOOK_TOKEN\""))
    #expect(prepared.terminalInput.contains("PROWL_CLI_SOCKET=\"$PROWL_LAUNCH_HOOK_SOCKET\""))
    #expect(!prepared.terminalInput.contains(token))
    #expect(!prepared.terminalInput.contains(socket))
    #expect(!prepared.terminalInput.contains("hook-json"))
    #expect(!prepared.terminalInput.contains("Prompt"))
  }

  @Test func forwardingLocatorIsAChildOnlyCarrierAndRecordContentsStayOutOfEnvironment() {
    let base = makePlan(invocation: AgentInvocation(executable: "codex", arguments: []))
    let record = CodexForwardingRecord(
      locator: URL(filePath: "/tmp/private/session/opaque.json", directoryHint: .notDirectory)
    )
    let prepared = base.applyingManagedHook(
      AgentHookPreparedInvocation(
        invocation: AgentInvocation(executable: "codex", arguments: ["-c", "notify=[]"]),
        argumentValues: [1: #"notify=["/bundle/prowl","agents","_hook","codex","agent-turn-complete"]"#]
      ),
      resources: AgentHookResources(bundledCLIPath: "/bundle/prowl", socketPath: "/tmp/prowl.sock"),
      launchCWD: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      token: "opaque-token",
      coveredEvents: [.turnEnded],
      forwardingRecord: record
    )

    #expect(
      prepared.surfaceEnvironment[AgentProfileLaunchPlanner.hookForwardCarrierName]
        == record.locator.path(percentEncoded: false)
    )
    #expect(
      prepared.commandEnvironmentTokens.contains(
        "PROWL_AGENT_HOOK_FORWARD_RECORD=\"$PROWL_LAUNCH_HOOK_FORWARD\""
      )
    )
    #expect(!prepared.terminalInput.contains(record.locator.path(percentEncoded: false)))
    #expect(!prepared.surfaceEnvironment.values.contains("/tmp/user-notifier-secret"))
  }

  @Test func attachingDispatchAfterPreflightKeepsOnePreparedHookPlan() throws {
    let base = makePlan(
      invocation: AgentInvocation(executable: "codex", arguments: ["User prompt"]),
      prompt: "User prompt"
    )
    let hooked = base.applyingManagedHook(
      AgentHookPreparedInvocation(
        invocation: AgentInvocation(executable: "codex", arguments: ["-c", "notify=[]", "User prompt"]),
        argumentValues: [1: "notify=[]"]
      ),
      resources: AgentHookResources(bundledCLIPath: "/bundle/prowl", socketPath: "/tmp/prowl.sock"),
      launchCWD: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      token: "token",
      coveredEvents: [.turnEnded]
    )
    let paired = try hooked.attachingDispatch(id: "dispatch-123", userPrompt: "User prompt")

    #expect(paired.hookRegistration == hooked.hookRegistration)
    #expect(paired.surfaceEnvironment[AgentProfileLaunchPlanner.dispatchCarrierName] == "dispatch-123")
    #expect(
      paired.surfaceEnvironment[AgentProfileLaunchPlanner.promptCarrierName]?
        .contains("Prowl dispatch completion protocol v1") == true
    )
    #expect(paired.invocation.arguments.last == paired.surfaceEnvironment[AgentProfileLaunchPlanner.promptCarrierName])
  }

  private func makePlan(
    invocation: AgentInvocation,
    prompt: String? = nil
  ) -> AgentProfileLaunchPlan {
    var environment: [String: String] = [:]
    if let prompt { environment[AgentProfileLaunchPlanner.promptCarrierName] = prompt }
    return AgentProfileLaunchPlan(
      profileID: UUID(),
      profileName: "Test",
      runtime: invocation.executable == "codex" ? .codex : .claude,
      invocation: invocation,
      commandEnvironmentTokens: [],
      placement: .tab,
      splitDirection: .right,
      surfaceEnvironment: environment,
      dedicatedHome: nil
    )
  }
}
