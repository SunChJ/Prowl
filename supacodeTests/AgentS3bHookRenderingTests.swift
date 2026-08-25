import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

/// Rendering rules for the three S3b runtimes. Each one injects differently, and the
/// asymmetries below were measured against Copilot CLI 1.0.80, Factory Droid 0.202.0, and
/// Qoder CLI 1.1.29 (docs-ai 064.008).
struct AgentS3bHookRenderingTests {
  private let hookCommands = [
    "SessionStart": "'/Applications/Prowl.app/Contents/Resources/prowl-cli/prowl' agents _hook droid SessionStart",
    "Stop": "'/Applications/Prowl.app/Contents/Resources/prowl-cli/prowl' agents _hook droid Stop",
  ]
  private let pluginDirectory = URL(
    filePath: "/Applications/Prowl.app/Contents/Resources/agent-hooks/copilot",
    directoryHint: .isDirectory
  )

  // MARK: - Adapter capabilities

  @Test func s3bAdaptersDeclareOnlyMeasuredCapabilities() throws {
    let expected: [AgentProfileRuntime: (AgentNativeHookRuntime, [String])] = [
      .copilot: (.copilot, ["Notification", "SessionEnd", "SessionStart", "Stop"]),
      .droid: (.droid, ["Notification", "SessionEnd", "SessionStart", "Stop"]),
      .qoder: (.qoder, ["Notification", "SessionEnd", "SessionStart", "Stop", "StopFailure"]),
    ]

    for (profileRuntime, (hookRuntime, nativeEvents)) in expected {
      let capability = try #require(
        AgentRuntimeAdapterRegistry.profileAdapter(for: profileRuntime)?.signalHooks
      )
      #expect(capability.runtime == hookRuntime)
      #expect(capability.nativeEvents.keys.sorted() == nativeEvents)
      #expect(capability.coveredEvents == [.needsInput, .sessionEnd, .sessionStart, .turnEnded])
      // Measured false positive: fires while the permission service auto-approves.
      #expect(capability.nativeEvents["PermissionRequest"] == nil)
      #expect(capability.nativeEvents["SubagentStop"] == nil)
    }

    let hookedRuntimes: Set<AgentProfileRuntime> = [.claude, .codex, .copilot, .droid, .qoder]
    for runtime in AgentProfileRuntime.allCases where !hookedRuntimes.contains(runtime) {
      #expect(AgentRuntimeAdapterRegistry.profileAdapter(for: runtime)?.signalHooks == nil)
    }
  }

  // MARK: - Copilot

  @Test func copilotAppendsPluginDirectoryThroughACarrierBeforeThePrompt() throws {
    let invocation = AgentInvocation(
      executable: "copilot",
      arguments: ["--model", "gpt-5.6", "--interactive", "Review this"]
    )
    let prepared = CopilotHookPluginRenderer.prepare(
      invocation: invocation,
      pluginDirectory: pluginDirectory,
      promptArgumentIndex: 3
    )

    #expect(prepared.invocation.executable == "copilot")
    #expect(
      prepared.invocation.arguments == ["--model", "gpt-5.6", "--plugin-dir", "", "--interactive", "Review this"])
    #expect(prepared.argumentValues == [3: pluginDirectory.path(percentEncoded: false)])
  }

  /// Copilot loads every `--plugin-dir` additively, so a user's own plugin keeps working and
  /// no merge is needed.
  @Test func copilotPreservesUserPluginDirectoriesAndEndOfOptions() throws {
    let invocation = AgentInvocation(
      executable: "copilot",
      arguments: ["--plugin-dir", "/Users/me/my-plugin", "--", "--not-an-option"]
    )
    let prepared = CopilotHookPluginRenderer.prepare(
      invocation: invocation,
      pluginDirectory: pluginDirectory,
      promptArgumentIndex: nil
    )

    #expect(
      prepared.invocation.arguments == [
        "--plugin-dir", "/Users/me/my-plugin", "--plugin-dir", "", "--", "--not-an-option",
      ]
    )
    #expect(prepared.argumentValues[3] == pluginDirectory.path(percentEncoded: false))
  }

  // MARK: - Qoder

  /// Qoder's repeated `--settings` is *first*-wins, so a merged object must be inserted
  /// before the user's. Inserting after would silently disable Prowl's hooks.
  @Test func qoderMergesTheFirstSettingsSourceAndInsertsBeforeIt() throws {
    let source = Data(
      #"""
      {"future": {"keep": true},
       "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "/tmp/user stop"}]}]}}
      """#.utf8
    )
    let invocation = AgentInvocation(
      executable: "qodercli",
      arguments: ["--settings", "first.json", "--settings", "second.json", "--print", "Prompt"]
    )
    let outcome = QoderHookSettingsPreparer.prepare(
      invocation: invocation,
      launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      promptArgumentIndex: 5,
      hookCommands: hookCommands,
      readFile: { url, _ in
        #expect(url.path(percentEncoded: false) == "/tmp/project/first.json")
        return .stable(source)
      }
    )

    let prepared = try #require(outcome.prepared)
    #expect(outcome.warning == nil)
    // The merged carrier goes in front; the user's own arguments are left untouched.
    #expect(prepared.invocation.arguments.prefix(2) == ["--settings", ""])
    #expect(
      prepared.invocation.arguments.suffix(6) == [
        "--settings", "first.json", "--settings", "second.json", "--print", "Prompt",
      ])

    let merged = try JSONSerialization.jsonObject(with: Data(try #require(prepared.argumentValues[1]).utf8))
    let object = try #require(merged as? [String: Any])
    #expect((object["future"] as? [String: Any])?["keep"] as? Bool == true)
    let stop = try #require((object["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
    let commands = stop.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["command"] as? String }
    #expect(commands.contains("/tmp/user stop"))
    #expect(commands.contains(hookCommands["Stop"]!))
  }

  @Test func qoderWithoutUserSettingsRendersHooksOnlyInline() throws {
    let invocation = AgentInvocation(executable: "qodercli", arguments: ["--model", "auto"])
    let outcome = QoderHookSettingsPreparer.prepare(
      invocation: invocation,
      launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      promptArgumentIndex: nil,
      hookCommands: hookCommands,
      readFile: { _, _ in
        Issue.record("must not read any file")
        return .unreadable
      }
    )

    let prepared = try #require(outcome.prepared)
    #expect(prepared.invocation.arguments == ["--settings", "", "--model", "auto"])
    let json = try #require(prepared.argumentValues[1])
    #expect(json.contains("agents _hook droid Stop"))
  }

  /// `--setting-sources` suppresses flag-supplied hooks entirely, so injecting would create a
  /// silently dead channel. Degrade instead and leave the launch untouched.
  @Test func qoderDegradesWhenSettingSourcesIsPresent() throws {
    for arguments in [
      ["--setting-sources", "user", "--model", "auto"],
      ["--setting-sources=user,project"],
    ] {
      let outcome = QoderHookSettingsPreparer.prepare(
        invocation: AgentInvocation(executable: "qodercli", arguments: arguments),
        launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
        promptArgumentIndex: nil,
        hookCommands: hookCommands,
        readFile: { _, _ in .unreadable }
      )
      #expect(outcome.prepared == nil)
      #expect(outcome.warning?.code == .managedHookDegraded)
      #expect(outcome.warning?.runtime == "qodercli")
      #expect(outcome.originalInvocation.arguments == arguments)
    }
  }

  @Test func qoderDegradesOnUnreadableOrMalformedUserSettings() {
    for result in [ClaudeSettingsReadResult.unreadable, .changed, .oversized, .stable(Data("[]".utf8))] {
      let outcome = QoderHookSettingsPreparer.prepare(
        invocation: AgentInvocation(executable: "qodercli", arguments: ["--settings", "user.json"]),
        launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
        promptArgumentIndex: nil,
        hookCommands: hookCommands,
        readFile: { _, _ in result }
      )
      #expect(outcome.prepared == nil)
      #expect(outcome.warning?.code == .managedHookDegraded)
    }
  }

  // MARK: - Droid

  /// Droid's `--settings` takes a path only, so a file is unavoidable; repeated flags are
  /// last-wins, so the merge target is the final source.
  @Test func droidMergesTheFinalSettingsSourceIntoAPrivateFile() throws {
    let source = Data(
      #"""
      {"customModels": [{"apiKey": "sk-secret"}],
       "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "/tmp/user stop"}]}]}}
      """#.utf8
    )
    let invocation = AgentInvocation(
      executable: "droid",
      arguments: ["--settings", "first.json", "--settings", "final.json", "Prompt"]
    )
    let outcome = DroidHookSettingsPreparer.mergedSettings(
      invocation: invocation,
      launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      promptArgumentIndex: 4,
      hookCommands: hookCommands,
      readFile: { url, _ in
        #expect(url.path(percentEncoded: false) == "/tmp/project/final.json")
        return .stable(source)
      }
    )

    let data = try #require(outcome.data)
    #expect(outcome.warning == nil)

    // The manager writes the file, then the argv is rendered against its path.
    let prepared = DroidHookSettingsPreparer.applying(
      settingsPath: URL(filePath: "/private/prowl/hooks/abc.json", directoryHint: .notDirectory),
      invocation: invocation,
      promptArgumentIndex: 4
    )
    // The user's own flags stay; Prowl's path wins by being last.
    #expect(
      prepared.invocation.arguments == [
        "--settings", "first.json", "--settings", "final.json", "--settings", "", "Prompt",
      ]
    )
    #expect(prepared.argumentValues == [5: "/private/prowl/hooks/abc.json"])

    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    // A user's secrets survive the merge, which is why the copy must be owner-only.
    #expect(((object["customModels"] as? [[String: Any]])?.first?["apiKey"] as? String) == "sk-secret")
    let stop = try #require((object["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
    let commands = stop.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["command"] as? String }
    #expect(commands.contains("/tmp/user stop"))
    #expect(commands.contains(hookCommands["Stop"]!))
  }

  @Test func droidMergesFactoryRuntimeSettingsPathFromTheProfileEnvironmentWhenNoFlagIsGiven() throws {
    // Droid's `--settings` flag wins over `FACTORY_RUNTIME_SETTINGS_PATH`, so injecting the flag
    // without merging the env-pointed settings would drop the user's custom models, keys, and
    // hooks. With no flag, Prowl reads that file and merges into it.
    let envSource = Data(#"{"customModels": [{"apiKey": "sk-env"}]}"#.utf8)
    let outcome = DroidHookSettingsPreparer.mergedSettings(
      invocation: AgentInvocation(executable: "droid", arguments: ["Prompt"]),
      launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      promptArgumentIndex: 0,
      hookCommands: hookCommands,
      environmentSettingsPath: "/home/user/.factory/env.json",
      readFile: { url, _ in
        #expect(url.path(percentEncoded: false) == "/home/user/.factory/env.json")
        return .stable(envSource)
      }
    )
    let data = try #require(outcome.data)
    #expect(outcome.warning == nil)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(((object["customModels"] as? [[String: Any]])?.first?["apiKey"] as? String) == "sk-env")
    #expect((object["hooks"] as? [String: Any]) != nil)
  }

  @Test func droidDegradesRatherThanOverrideAnUnreadableEnvironmentSettings() {
    // If the env-pointed settings exist but cannot be read, overriding them would silently drop
    // the user's config, so the launch degrades instead.
    let outcome = DroidHookSettingsPreparer.mergedSettings(
      invocation: AgentInvocation(executable: "droid", arguments: ["Prompt"]),
      launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      promptArgumentIndex: 0,
      hookCommands: hookCommands,
      environmentSettingsPath: "/home/user/.factory/env.json",
      readFile: { _, _ in .unreadable }
    )
    #expect(outcome.data == nil)
    #expect(outcome.warning?.code == .managedHookDegraded)
  }

  @Test func droidPrefersTheExplicitFlagOverTheEnvironmentSettingsPath() throws {
    // The flag wins (measured), so a flag source is merged and the env path is never read.
    let flagSource = Data(#"{"customModels": [{"apiKey": "sk-flag"}]}"#.utf8)
    let outcome = DroidHookSettingsPreparer.mergedSettings(
      invocation: AgentInvocation(executable: "droid", arguments: ["--settings", "flag.json"]),
      launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      promptArgumentIndex: nil,
      hookCommands: hookCommands,
      environmentSettingsPath: "/home/user/.factory/env.json",
      readFile: { url, _ in
        #expect(url.path(percentEncoded: false) == "/tmp/project/flag.json")
        return .stable(flagSource)
      }
    )
    let data = try #require(outcome.data)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(((object["customModels"] as? [[String: Any]])?.first?["apiKey"] as? String) == "sk-flag")
  }

  @Test func droidWithoutUserSettingsMergesHooksOnly() throws {
    let outcome = DroidHookSettingsPreparer.mergedSettings(
      invocation: AgentInvocation(executable: "droid", arguments: ["Prompt"]),
      launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      promptArgumentIndex: 0,
      hookCommands: hookCommands,
      readFile: { _, _ in
        Issue.record("must not read any file")
        return .unreadable
      }
    )

    let data = try #require(outcome.data)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object.keys.sorted() == ["hooks"])

    let prepared = DroidHookSettingsPreparer.applying(
      settingsPath: URL(filePath: "/private/prowl/hooks/abc.json", directoryHint: .notDirectory),
      invocation: AgentInvocation(executable: "droid", arguments: ["Prompt"]),
      promptArgumentIndex: 0
    )
    #expect(prepared.invocation.arguments == ["--settings", "", "Prompt"])
  }

  @Test func droidTreatsASettingsValueAsAPathNeverInlineJSON() {
    // Droid's `--settings` is path-only (it `fs.stat`s the value), so a `{`-prefixed value is a
    // path that does not exist, not inline JSON to merge. Injecting a "fixed" file would run a
    // config the user's own Droid launch would have rejected.
    var readPath: String?
    let outcome = DroidHookSettingsPreparer.mergedSettings(
      invocation: AgentInvocation(executable: "droid", arguments: ["--settings", #"{"hooks":{}}"#]),
      launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      promptArgumentIndex: nil,
      hookCommands: hookCommands,
      readFile: { url, _ in
        readPath = url.path(percentEncoded: false)
        return .unreadable  // the "path" does not exist, exactly as Droid's own fs.stat would find
      }
    )
    // The value was resolved as a path (read attempted), not parsed as inline JSON.
    #expect(readPath == #"/tmp/project/{"hooks":{}}"#)
    #expect(outcome.data == nil)
    #expect(outcome.warning?.code == .managedHookDegraded)
    #expect(outcome.warning?.runtime == "droid")
  }

  @Test func droidDegradesWhenTheMergedSettingsExceedThePrivateFileLimit() {
    // The merge cap (256 KiB) is larger than the owner-only private-file store cap, so a merge
    // between the two would serialize but fail to write. Degrade at merge time with the Droid
    // reason instead of a confusing "file could not be created" at a threshold users can't see.
    let big = String(repeating: "a", count: CodexForwardingRecordReader.maximumRecordBytes)
    let source = Data(#"{"note": "\#(big)"}"#.utf8)
    let outcome = DroidHookSettingsPreparer.mergedSettings(
      invocation: AgentInvocation(executable: "droid", arguments: ["--settings", "s.json"]),
      launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      promptArgumentIndex: nil,
      hookCommands: hookCommands,
      readFile: { _, _ in .stable(source) }
    )
    #expect(outcome.data == nil)
    #expect(outcome.warning?.code == .managedHookDegraded)
    #expect(outcome.warning?.runtime == "droid")
  }

  @Test func droidDegradesWhenTheUserSourceIsUnusable() {
    for result in [ClaudeSettingsReadResult.unreadable, .changed, .oversized, .stable(Data("[]".utf8))] {
      let outcome = DroidHookSettingsPreparer.mergedSettings(
        invocation: AgentInvocation(executable: "droid", arguments: ["--settings", "user.json"]),
        launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
        promptArgumentIndex: nil,
        hookCommands: hookCommands,
        readFile: { _, _ in result }
      )
      #expect(outcome.data == nil)
      #expect(outcome.warning?.code == .managedHookDegraded)
      #expect(outcome.warning?.runtime == "droid")
    }
  }

  /// Droid also honors `FACTORY_RUNTIME_SETTINGS_PATH`, but an explicit flag beats it, so
  /// Prowl always injects through the flag.
  @Test func droidInjectionUsesTheFlagNotTheEnvironmentVariable() {
    let prepared = DroidHookSettingsPreparer.applying(
      settingsPath: URL(filePath: "/private/prowl/hooks/abc.json", directoryHint: .notDirectory),
      invocation: AgentInvocation(executable: "droid", arguments: []),
      promptArgumentIndex: nil
    )
    #expect(prepared.invocation.arguments == ["--settings", ""])
    #expect(prepared.argumentValues == [1: "/private/prowl/hooks/abc.json"])
  }

  // MARK: - Working directory

  /// Measured 2026-08-25: Droid `--cwd` and Copilot `-C` take the last occurrence, Qoder
  /// `-w`/`--cwd` the first; `--cwd=dir` and `-Cdir` are accepted; the hooks then report the
  /// changed directory as `cwd`.
  @Test func workingDirectoryScanFollowsEachRuntimesMeasuredPrecedence() {
    typealias Scan = ManagedHookWorkingDirectory.Scan
    #expect(
      ManagedHookWorkingDirectory.scan(
        arguments: ["--cwd", "b", "--cwd", "c", "Prompt"],
        optionNames: ["--cwd"], precedence: .lastWins, promptArgumentIndex: 4
      ) == Scan.changed("c"))
    #expect(
      ManagedHookWorkingDirectory.scan(
        arguments: ["--cwd=c"], optionNames: ["--cwd"], precedence: .lastWins, promptArgumentIndex: nil
      ) == Scan.changed("c"))
    #expect(
      ManagedHookWorkingDirectory.scan(
        arguments: ["-w", "b", "--cwd", "c"],
        optionNames: ["-w", "--cwd"], precedence: .firstWins, promptArgumentIndex: nil
      ) == Scan.changed("b"))
    #expect(
      ManagedHookWorkingDirectory.scan(
        arguments: ["-C", "b", "-Cc", "--", "-C", "d"],
        optionNames: ["-C"], precedence: .lastWins, promptArgumentIndex: nil
      ) == Scan.changed("c"))
    #expect(
      ManagedHookWorkingDirectory.scan(
        arguments: [], optionNames: ["-C"], precedence: .lastWins, promptArgumentIndex: nil
      ) == Scan.inherited)
    // A dangling option, or one whose only value would be the prompt, cannot be trusted.
    #expect(
      ManagedHookWorkingDirectory.scan(
        arguments: ["--cwd"], optionNames: ["--cwd"], precedence: .lastWins, promptArgumentIndex: nil
      ) == Scan.malformed)
    #expect(
      ManagedHookWorkingDirectory.scan(
        arguments: ["--cwd", "Prompt"], optionNames: ["--cwd"], precedence: .lastWins, promptArgumentIndex: 1
      ) == Scan.malformed)
  }

  @Test func effectiveWorkingDirectoryResolvesRelativeValuesAgainstTheInheritedDirectory() {
    let inherited = URL(filePath: "/tmp/project", directoryHint: .isDirectory)
    #expect(
      ManagedHookWorkingDirectory.effective(inherited: inherited, scan: .changed("sub/dir"))?
        .path(percentEncoded: false) == "/tmp/project/sub/dir/")
    #expect(
      ManagedHookWorkingDirectory.effective(inherited: inherited, scan: .changed("/elsewhere"))?
        .path(percentEncoded: false) == "/elsewhere/")
    #expect(
      ManagedHookWorkingDirectory.effective(inherited: inherited, scan: .inherited)?
        .path(percentEncoded: false) == "/tmp/project/")
    #expect(ManagedHookWorkingDirectory.effective(inherited: inherited, scan: .malformed) == nil)
  }

  /// The registration must carry the directory the hooks will report, while a relative
  /// settings path is still read from the launch directory.
  @Test func runtimesRegisterTheChangedWorkingDirectoryButReadSettingsFromTheInheritedOne() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "prowl-s3b-cwd-\(UUID().uuidString)", directoryHint: .isDirectory)
    let inherited = root.appending(path: "project", directoryHint: .isDirectory)
    let elsewhere = root.appending(path: "elsewhere", directoryHint: .isDirectory)
    let plugin = root.appending(path: "plugin", directoryHint: .isDirectory)
    for directory in [inherited, elsewhere, plugin] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: root) }
    let cli = root.appending(path: "prowl", directoryHint: .notDirectory)
    try "#!/bin/sh\nexit 0\n".write(to: cli, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
    try "{}".write(to: plugin.appending(path: "hooks.json"), atomically: true, encoding: .utf8)
    try #"{"marker": "inherited"}"#.write(
      to: inherited.appending(path: "s.json"), atomically: true, encoding: .utf8)
    try #"{"marker": "target"}"#.write(
      to: elsewhere.appending(path: "s.json"), atomically: true, encoding: .utf8)
    let resources = AgentHookResources(
      bundledCLIPath: cli.path(percentEncoded: false),
      socketPath: "/tmp/prowl.sock",
      copilotPluginPath: plugin.path(percentEncoded: false)
    )
    let target = elsewhere.path(percentEncoded: false)
    func trimmed(_ url: URL) -> String {
      url.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    let expected = trimmed(elsewhere)

    let droid = await AgentManagedHookPreparer.prepare(
      plan: makePlan(runtime: .droid, arguments: ["--cwd", target, "--settings", "s.json"]),
      inheritedCWD: inherited,
      resources: resources
    )
    #expect(droid.warning == nil)
    #expect(trimmed(droid.launchCWD) == expected)
    let merged = try #require(droid.pendingSettingsFile?.data)
    let object = try #require(try JSONSerialization.jsonObject(with: merged) as? [String: Any])
    #expect(object["marker"] as? String == "inherited")

    let qoder = await AgentManagedHookPreparer.prepare(
      plan: makePlan(runtime: .qoder, arguments: ["-w", target]),
      inheritedCWD: inherited,
      resources: resources
    )
    #expect(qoder.warning == nil)
    #expect(qoder.preparedInvocation != nil)
    #expect(trimmed(qoder.launchCWD) == expected)

    let copilot = await AgentManagedHookPreparer.prepare(
      plan: makePlan(runtime: .copilot, arguments: ["-C", target]),
      inheritedCWD: inherited,
      resources: resources
    )
    #expect(copilot.warning == nil)
    #expect(copilot.preparedInvocation != nil)
    #expect(trimmed(copilot.launchCWD) == expected)

    let malformed = await AgentManagedHookPreparer.prepare(
      plan: makePlan(runtime: .droid, arguments: ["--cwd"]),
      inheritedCWD: inherited,
      resources: resources
    )
    #expect(malformed.warning?.code == .managedHookDegraded)
    #expect(malformed.pendingSettingsFile == nil)
    #expect(trimmed(malformed.launchCWD) == trimmed(inherited))
  }

  private func makePlan(runtime: AgentProfileRuntime, arguments: [String]) -> AgentProfileLaunchPlan {
    AgentProfileLaunchPlan(
      profileID: UUID(),
      profileName: "Test",
      runtime: runtime,
      invocation: AgentInvocation(executable: runtime.agent.iconLookupToken, arguments: arguments),
      commandEnvironmentTokens: [],
      placement: .tab,
      splitDirection: .right,
      surfaceEnvironment: [:],
      dedicatedHome: nil
    )
  }
}
