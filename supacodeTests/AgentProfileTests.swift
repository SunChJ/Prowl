import Foundation
import Testing

@testable import supacode

struct AgentProfileTests {
  private func profile(
    id: UUID = UUID(),
    name: String = "Codex · Work",
    isEnabled: Bool = true,
    runtime: AgentProfileRuntime = .codex
  ) -> AgentProfile {
    AgentProfile(id: id, name: name, isEnabled: isEnabled, runtime: runtime)
  }

  // MARK: - Normalization

  @Test func normalizationDropsBlankNamesAndDuplicateIDs() {
    let id = UUID()
    let profiles = [
      profile(id: id, name: "  Codex · Work  "),
      profile(id: id, name: "Duplicate of first"),
      profile(name: "   "),
      profile(name: "Claude · Review", runtime: .claude),
    ]

    let normalized = AgentProfile.normalizedProfiles(profiles)

    #expect(normalized.count == 2)
    #expect(normalized[0].id == id)
    #expect(normalized[0].name == "Codex · Work")
    #expect(normalized[1].name == "Claude · Review")
  }

  @Test func decodeFillsDefaultsForMissingFields() throws {
    let id = UUID()
    let legacy = Data(#"{"id":"\#(id.uuidString)","name":"Codex","runtime":"codex"}"#.utf8)

    let decoded = try JSONDecoder().decode(AgentProfile.self, from: legacy)

    #expect(decoded.id == id)
    #expect(decoded.isEnabled)
    #expect(decoded.model == nil)
    #expect(decoded.reasoningEffort == nil)
    #expect(decoded.executionMode == .standard)
    #expect(decoded.placement == .tab)
    #expect(decoded.splitDirection == .right)
    #expect(decoded.extraArguments.isEmpty)
    #expect(!decoded.bindsDedicatedHome)
  }

  // MARK: - Recommendation

  @Test func recommendationPrefersDesignationOverMemoryAndOrder() {
    let designated = profile(name: "Designated")
    let remembered = profile(name: "Remembered")
    let first = profile(name: "First")
    let profiles = [first, remembered, designated]

    let recommended = AgentProfileRecommendation.recommendedProfile(
      profiles: profiles,
      designatedID: designated.id,
      lastLaunchedID: remembered.id
    )

    #expect(recommended?.id == designated.id)
  }

  @Test func recommendationFallsThroughDisabledDesignationToMemory() {
    let designated = profile(name: "Designated", isEnabled: false)
    let remembered = profile(name: "Remembered")
    let profiles = [profile(name: "First"), remembered, designated]

    let recommended = AgentProfileRecommendation.recommendedProfile(
      profiles: profiles,
      designatedID: designated.id,
      lastLaunchedID: remembered.id
    )

    #expect(recommended?.id == remembered.id)
  }

  @Test func recommendationFallsThroughDanglingMemoryToFirstEnabled() {
    let disabledFirst = profile(name: "Disabled", isEnabled: false)
    let enabled = profile(name: "Enabled")
    let profiles = [disabledFirst, enabled]

    let recommended = AgentProfileRecommendation.recommendedProfile(
      profiles: profiles,
      designatedID: nil,
      lastLaunchedID: UUID()
    )

    #expect(recommended?.id == enabled.id)
  }

  @Test func recommendationIsNilWhenNothingIsEnabled() {
    let profiles = [profile(name: "Disabled", isEnabled: false)]

    let recommended = AgentProfileRecommendation.recommendedProfile(
      profiles: profiles,
      designatedID: nil,
      lastLaunchedID: nil
    )

    #expect(recommended == nil)
  }

  // MARK: - Shell word splitting

  @Test func splitterHandlesQuotesAndEscapes() {
    #expect(ShellWordSplitter.split("") == [])
    #expect(ShellWordSplitter.split("   ") == [])
    #expect(ShellWordSplitter.split("--yolo --search") == ["--yolo", "--search"])
    #expect(ShellWordSplitter.split("--cd '/tmp/with space'") == ["--cd", "/tmp/with space"])
    #expect(ShellWordSplitter.split(#"--note "double \" quote""#) == ["--note", #"double " quote"#])
    #expect(ShellWordSplitter.split(#"a\ b"#) == ["a b"])
    #expect(ShellWordSplitter.split("''") == [""])
    #expect(ShellWordSplitter.split("--flag=value") == ["--flag=value"])
  }

  @Test func splitterConsumesUnterminatedQuoteAsLiteralTail() {
    #expect(ShellWordSplitter.split("--note 'unterminated tail") == ["--note", "unterminated tail"])
  }

  // MARK: - Launch plan

  @Test func purePresetPlanHasNoEnvironmentAndSplitsExtraArguments() throws {
    var preset = profile(name: "Codex · Deep")
    preset.model = "gpt-5.4"
    preset.reasoningEffort = "xhigh"
    preset.extraArguments = "--search --cd '/tmp/with space'"

    let plan = try AgentProfileLaunchPlanner.plan(
      for: preset,
      homeBaseDirectory: URL(fileURLWithPath: "/base", isDirectory: true)
    )

    #expect(plan.environment.isEmpty)
    #expect(plan.dedicatedHome == nil)
    #expect(plan.invocation.executable == "codex")
    #expect(
      plan.invocation.arguments == [
        "--model", "gpt-5.4",
        "-c", "model_reasoning_effort=xhigh",
        "--search", "--cd", "/tmp/with space",
      ]
    )
    #expect(plan.previewText == plan.invocation.terminalInput)
  }

  @Test func boundProfilePlanDerivesHomeFromUUIDInsideBase() throws {
    var bound = profile(name: "Codex · Work")
    bound.bindsDedicatedHome = true
    let base = URL(fileURLWithPath: "/base/agent-profiles", isDirectory: true)

    let plan = try AgentProfileLaunchPlanner.plan(for: bound, homeBaseDirectory: base)

    let home = try #require(plan.dedicatedHome)
    #expect(
      AgentProfileLaunchPlanner.pathString(home) == "/base/agent-profiles/\(bound.id.uuidString)"
    )
    #expect(plan.environment == ["CODEX_HOME": "/base/agent-profiles/\(bound.id.uuidString)"])
    #expect(plan.previewText.hasPrefix("CODEX_HOME=/base/agent-profiles/"))
    #expect(AgentProfileLaunchPlanner.isContained(home, in: base))
  }

  @Test func boundClaudeProfileUsesConfigDirVariable() throws {
    var bound = profile(name: "Claude · Personal", runtime: .claude)
    bound.bindsDedicatedHome = true

    let plan = try AgentProfileLaunchPlanner.plan(
      for: bound,
      homeBaseDirectory: URL(fileURLWithPath: "/base", isDirectory: true)
    )

    #expect(plan.environment.keys.contains("CLAUDE_CONFIG_DIR"))
  }

  @Test func containmentRejectsBaseItselfAndOutsidePaths() {
    let base = URL(fileURLWithPath: "/base/agent-profiles", isDirectory: true)
    #expect(!AgentProfileLaunchPlanner.isContained(base, in: base))
    #expect(
      !AgentProfileLaunchPlanner.isContained(
        URL(fileURLWithPath: "/base/agent-profiles/../../.codex", isDirectory: true),
        in: base
      )
    )
    #expect(
      !AgentProfileLaunchPlanner.isContained(
        URL(fileURLWithPath: "/base/agent-profiles-other/x", isDirectory: true),
        in: base
      )
    )
  }

  @Test func provisionerRefusesHomesOutsideBase() {
    let base = URL(fileURLWithPath: "/base/agent-profiles", isDirectory: true)
    #expect(throws: AgentProfileLaunchPlanError.self) {
      try AgentProfileHomeProvisioner.provision(
        home: URL(fileURLWithPath: "/Users/x/.codex", isDirectory: true),
        base: base
      )
    }
  }

  @Test func provisionerCreatesOwnerOnlyHome() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "agent-profile-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let home = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)

    try AgentProfileHomeProvisioner.provision(home: home, base: root)

    let attributes = try FileManager.default.attributesOfItem(
      atPath: home.path(percentEncoded: false)
    )
    #expect((attributes[.posixPermissions] as? NSNumber)?.int16Value == 0o700)
  }

  // MARK: - Settings persistence

  @Test func globalSettingsDecodeLegacyJSONWithoutProfileFields() throws {
    let legacy = Data(#"{"customCommands":[]}"#.utf8)

    let decoded = try JSONDecoder().decode(UserGlobalSettings.self, from: legacy)

    #expect(decoded.agentProfiles.isEmpty)
    #expect(!decoded.didSeedAgentProfiles)
  }

  @Test func globalSettingsRoundTripKeepsProfilesAndSeedFlag() throws {
    let settings = UserGlobalSettings(
      customCommands: [],
      agentProfiles: [profile(name: "Codex · Work")],
      didSeedAgentProfiles: true
    )

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(UserGlobalSettings.self, from: data)

    #expect(decoded == settings)
  }

  @Test func repositorySettingsDecodeLegacyJSONWithoutProfileFields() throws {
    let legacy = Data(#"{"customCommands":[],"disabledGlobalCommandIDs":[]}"#.utf8)

    let decoded = try JSONDecoder().decode(UserRepositorySettings.self, from: legacy)

    #expect(decoded.defaultAgentProfileID == nil)
    #expect(decoded.lastLaunchedAgentProfileID == nil)
  }

  @Test func repositorySettingsRoundTripKeepsProfileReferences() throws {
    let designated = UUID()
    let remembered = UUID()
    let settings = UserRepositorySettings(
      customCommands: [],
      defaultAgentProfileID: designated,
      lastLaunchedAgentProfileID: remembered
    )

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(UserRepositorySettings.self, from: data)

    #expect(decoded.defaultAgentProfileID == designated)
    #expect(decoded.lastLaunchedAgentProfileID == remembered)
  }
}
