import Foundation
import Testing

@testable import supacode

struct AgentHookRenderingTests {
  private let hookCommands = [
    "SessionStart":
      "'/Applications/Prowl Debug.app/Contents/Resources/prowl-cli/prowl' agents _hook claude SessionStart",
    "Stop": "'/Applications/Prowl Debug.app/Contents/Resources/prowl-cli/prowl' agents _hook claude Stop",
    "SessionEnd": "'/Applications/Prowl Debug.app/Contents/Resources/prowl-cli/prowl' agents _hook claude SessionEnd",
  ]

  @Test func adaptersDeclareOnlyApprovedS3aCapabilities() throws {
    let claude = try #require(AgentRuntimeAdapterRegistry.profileAdapter(for: .claude)?.signalHooks)
    #expect(claude.runtime == .claude)
    #expect(claude.coveredEvents == [.needsInput, .sessionEnd, .sessionStart, .turnEnded])
    #expect(claude.nativeEvents["Stop"] == .turnEnded)

    let codex = try #require(AgentRuntimeAdapterRegistry.profileAdapter(for: .codex)?.signalHooks)
    #expect(codex.runtime == .codex)
    #expect(codex.coveredEvents == [.turnEnded])
    #expect(codex.nativeEvents == ["agent-turn-complete": .turnEnded])

    for runtime in AgentProfileRuntime.allCases where runtime != .claude && runtime != .codex {
      #expect(AgentRuntimeAdapterRegistry.profileAdapter(for: runtime)?.signalHooks == nil)
    }
  }

  @Test func claudeSettingsMergePreservesUnknownFieldsAndEveryExistingHandler() throws {
    let source = Data(
      #"""
      {
        "future": {"enabled": true},
        "hooks": {
          "Stop": [{"matcher": "main", "hooks": [{"type": "command", "command": "/tmp/user stop"}]}],
          "FutureEvent": [{"hooks": [{"type": "command", "command": "/tmp/future"}]}]
        }
      }
      """#.utf8
    )
    let invocation = AgentInvocation(
      executable: "claude",
      arguments: ["--model", "opus", "--settings", "settings.json", "Prompt"]
    )
    let outcome = ClaudeHookSettingsPreparer.prepare(
      invocation: invocation,
      launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      hookCommands: hookCommands,
      readFile: { url, _ in
        #expect(url.path(percentEncoded: false) == "/tmp/project/settings.json")
        return .stable(source)
      }
    )
    let prepared = try #require(outcome.prepared)
    #expect(outcome.warning == nil)
    #expect(prepared.invocation.arguments == invocation.arguments)
    let mergedString = try #require(prepared.argumentValues[3])
    let mergedData = Data(mergedString.utf8)
    let merged = try #require(JSONSerialization.jsonObject(with: mergedData) as? [String: Any])
    #expect((merged["future"] as? [String: Bool])?["enabled"] == true)
    let hooks = try #require(merged["hooks"] as? [String: Any])
    let stop = try #require(hooks["Stop"] as? [[String: Any]])
    #expect(stop.count == 2)
    #expect((stop[0]["matcher"] as? String) == "main")
    #expect((hooks["FutureEvent"] as? [[String: Any]])?.count == 1)
  }

  @Test func claudeSettingsUsesFinalEffectiveSourceAndAvoidsProwlDuplicates() throws {
    let existingCommand = try #require(hookCommands["Stop"])
    let inline =
      "{\"marker\":\"final\",\"hooks\":{\"Stop\":[{\"hooks\":["
      + "{\"type\":\"command\",\"command\":\"\(existingCommand)\"}]}]}}"
    let invocation = AgentInvocation(
      executable: "claude",
      arguments: ["--settings", "ignored.json", "--settings=\(inline)", "Prompt"]
    )
    var reads = 0
    let outcome = ClaudeHookSettingsPreparer.prepare(
      invocation: invocation,
      launchDirectory: URL(filePath: "/tmp", directoryHint: .isDirectory),
      hookCommands: hookCommands,
      readFile: { _, _ in
        reads += 1
        return .unreadable
      }
    )
    let prepared = try #require(outcome.prepared)
    #expect(reads == 0)
    let mergedString = try #require(prepared.argumentValues[3])
    let mergedData = Data(mergedString.utf8)
    let merged = try #require(JSONSerialization.jsonObject(with: mergedData) as? [String: Any])
    #expect(merged["marker"] as? String == "final")
    let hooks = try #require(merged["hooks"] as? [String: Any])
    let stop = try #require(hooks["Stop"] as? [[String: Any]])
    #expect(stop.count == 1)
  }

  @Test func stableReaderRejectsAtomicPathReplacement() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "prowl-settings-replacement-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = directory.appending(path: "settings.json", directoryHint: .notDirectory)
    try Data(#"{"version":1}"#.utf8).write(to: settings)

    let result = ClaudeSettingsStableReader.read(settings, maximumBytes: 1_024) {
      try? Data(#"{"version":2}"#.utf8).write(to: settings, options: .atomic)
    }

    #expect(result == .changed)
  }

  @Test func claudeMalformedChangedAndOversizedSettingsPreserveInvocation() {
    let invocation = AgentInvocation(executable: "claude", arguments: ["--settings", "bad.json", "Prompt"])
    let missingValue = ClaudeHookSettingsPreparer.prepare(
      invocation: AgentInvocation(executable: "claude", arguments: ["--settings", "Prompt"]),
      launchDirectory: URL(filePath: "/tmp", directoryHint: .isDirectory),
      promptArgumentIndex: 1,
      hookCommands: hookCommands,
      readFile: { _, _ in .unreadable }
    )
    #expect(missingValue.prepared == nil)
    #expect(missingValue.originalInvocation.arguments == ["--settings", "Prompt"])

    let results: [ClaudeSettingsReadResult] = [
      .stable(Data("[]".utf8)),
      .stable(Data("{".utf8)),
      .changed,
      .oversized,
      .unreadable,
    ]

    for result in results {
      let outcome = ClaudeHookSettingsPreparer.prepare(
        invocation: invocation,
        launchDirectory: URL(filePath: "/tmp", directoryHint: .isDirectory),
        hookCommands: hookCommands,
        readFile: { _, _ in result }
      )
      #expect(outcome.prepared == nil)
      #expect(outcome.warning?.code == .managedHookDegraded)
      #expect(outcome.originalInvocation == invocation)
    }
  }

  @Test func claudeAndCodexHookArgumentsStayBeforeThePositionalPrompt() throws {
    let claude = AgentInvocation(executable: "claude", arguments: ["-p", "Prompt"])
    let claudeOutcome = ClaudeHookSettingsPreparer.prepare(
      invocation: claude,
      launchDirectory: URL(filePath: "/tmp", directoryHint: .isDirectory),
      promptArgumentIndex: 1,
      hookCommands: hookCommands,
      readFile: { _, _ in .unreadable }
    )
    let preparedClaude = try #require(claudeOutcome.prepared)
    #expect(preparedClaude.invocation.arguments.last == "Prompt")
    #expect(preparedClaude.invocation.arguments.dropLast().contains("--settings"))

    let codex = CodexManagedNotifyRenderer.prepare(
      invocation: AgentInvocation(executable: "codex", arguments: ["exec", "Prompt"]),
      bundledCLIPath: "/Applications/Prowl Debug.app/Contents/Resources/prowl-cli/prowl",
      promptArgumentIndex: 1
    )
    #expect(codex.invocation.arguments.last == "Prompt")
    #expect(codex.invocation.arguments.contains("-c"))
    #expect(codex.argumentValues.values.first?.contains("notify=") == true)
    #expect(codex.argumentValues.values.first?.contains("dangerously-bypass-hook-trust") == false)
  }

  @Test func unpromptedOptionValuePairsAreNeverInferredAsPrompts() throws {
    let claude = ClaudeHookSettingsPreparer.prepare(
      invocation: AgentInvocation(executable: "claude", arguments: ["-p", "--model", "opus"]),
      launchDirectory: URL(filePath: "/tmp", directoryHint: .isDirectory),
      hookCommands: hookCommands,
      readFile: { _, _ in .unreadable }
    )
    let preparedClaude = try #require(claude.prepared)
    #expect(
      Array(preparedClaude.invocation.arguments.prefix(3))
        == ["-p", "--model", "opus"]
    )
    #expect(preparedClaude.invocation.arguments.suffix(2) == ["--settings", "{}"])

    for original in [
      ["exec", "-C", "/tmp/project"],
      ["exec", "--cd=/tmp/project"],
    ] {
      let codex = CodexManagedNotifyRenderer.prepare(
        invocation: AgentInvocation(executable: "codex", arguments: original),
        bundledCLIPath: "/bundle/prowl"
      )
      #expect(Array(codex.invocation.arguments.prefix(original.count)) == original)
      #expect(codex.invocation.arguments.suffix(2) == ["-c", "notify=[]"])
    }
  }

  @Test func arbitraryArgumentCarriersNeverRenderValuesIntoTerminalInput() {
    let invocation = AgentInvocation(
      executable: "claude",
      arguments: ["-p", "--settings", "{\"secret\":true}", "long prompt"]
    )
    let rendered = invocation.terminalInput(
      replacingArgumentsWithEnvironmentVariables: [2: "PROWL_HOOK_ARG_0", 3: "PROWL_LAUNCH_PROMPT"]
    )

    #expect(rendered.contains("\"$PROWL_HOOK_ARG_0\""))
    #expect(rendered.contains("\"$PROWL_LAUNCH_PROMPT\""))
    #expect(!rendered.contains("secret"))
    #expect(!rendered.contains("long prompt"))
  }
}
