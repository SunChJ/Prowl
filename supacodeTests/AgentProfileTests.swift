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
    #expect(decoded.icon == nil)
    #expect(decoded.executionMode == .standard)
    #expect(decoded.placement == .tab)
    #expect(decoded.splitDirection == .right)
    #expect(decoded.extraArguments.isEmpty)
    #expect(!decoded.bindsDedicatedHome)
  }

  @Test func profileIconUsesCustomSymbolThenRuntimeBrandFallback() throws {
    let custom = AgentProfile(name: "Codex · Work", runtime: .codex, icon: "wand.and.stars")
    #expect(
      AgentProfileIconResolver.source(for: custom.iconSource)
        == TabIconSource(systemSymbol: "wand.and.stars")
    )

    let fallback = AgentProfile(name: "Claude Code", runtime: .claude)
    let expected = try #require(CommandIconMap.iconForFirstToken(fallback.runtime.agent.iconLookupToken))
    #expect(AgentProfileIconResolver.source(for: fallback.iconSource) == expected)
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

  @Test func effectiveExecutionModeNeverClaimsStandardItCannotProve() {
    var codex = profile(name: "Codex")
    #expect(codex.effectiveExecutionMode == .standard)

    // Recognized bypass flags upgrade the claim to unrestricted.
    codex.extraArguments = "--search --yolo"
    #expect(codex.effectiveExecutionMode == .unrestricted)
    codex.extraArguments = "--dangerously-bypass-approvals-and-sandbox"
    #expect(codex.effectiveExecutionMode == .unrestricted)

    // Unrecognized safety-relevant overrides must not read as Standard:
    // the claim defers to the command line instead.
    codex.extraArguments = "--sandbox danger-full-access"
    #expect(codex.effectiveExecutionMode == .followsExtraArguments)
    codex.extraArguments = "--ask-for-approval never"
    #expect(codex.effectiveExecutionMode == .followsExtraArguments)
    codex.extraArguments = "-c approval_policy=never"
    #expect(codex.effectiveExecutionMode == .followsExtraArguments)

    var claude = profile(name: "Claude", runtime: .claude)
    claude.extraArguments = "--permission-mode bypassPermissions"
    #expect(claude.effectiveExecutionMode == .unrestricted)

    // Harmless flags also defer — any extra argument voids the Standard claim.
    claude.extraArguments = "--verbose"
    #expect(claude.effectiveExecutionMode == .followsExtraArguments)
    claude.executionMode = .unrestricted
    #expect(claude.effectiveExecutionMode == .unrestricted)
  }

  @Test func physicalContainmentRejectsSymlinkLeafAndEscapingTargets() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
      .appending(path: "agent-profile-symlink-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? fileManager.removeItem(at: root) }
    let base = root.appending(path: "agent-profiles", directoryHint: .isDirectory)
    let outside = root.appending(path: "fake-codex-home", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)

    // A <uuid> leaf replaced by a symlink to a directory outside the base
    // must be rejected before any file operation.
    let linkedHome = base.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try fileManager.createSymbolicLink(at: linkedHome, withDestinationURL: outside)
    #expect(throws: AgentProfileLaunchPlanError.self) {
      try AgentProfileHomeProvisioner.provision(home: linkedHome, base: base)
    }
    #expect(throws: AgentProfileLaunchPlanError.self) {
      try AgentProfileHomeProvisioner.validatePhysicalContainment(home: linkedHome, base: base)
    }

    // A symlinked *base* (e.g. ~/.prowl on a synced volume) stays legal:
    // both sides of the comparison resolve consistently.
    let baseLink = root.appending(path: "agent-profiles-link", directoryHint: .isDirectory)
    try fileManager.createSymbolicLink(at: baseLink, withDestinationURL: base)
    let homeViaLink = baseLink.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try AgentProfileHomeProvisioner.provision(home: homeViaLink, base: baseLink)
    #expect(fileManager.fileExists(atPath: AgentProfileLaunchPlanner.pathString(homeViaLink)))
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
