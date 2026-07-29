import Foundation

/// The compiled result of resolving a profile for one launch (docs-ai 053):
/// every decision is already made, downstream layers only execute. The same
/// plan feeds the settings editor's launch preview and the actual launch.
nonisolated struct AgentProfileLaunchPlan: Equatable, Sendable {
  let profileID: UUID
  let profileName: String
  let invocation: AgentInvocation
  let placement: AgentProfilePlacement
  let splitDirection: UserCustomSplitDirection
  /// Environment patch for the new surface. Non-empty only for account-bound
  /// profiles; additive over the shell's normal environment, never a scrub.
  let environment: [String: String]
  /// Dedicated home to provision before launch; nil for pure presets.
  let dedicatedHome: URL?

  var terminalInput: String { invocation.terminalInput }

  /// Human-readable launch preview: env prefix plus the exact rendered
  /// invocation. Shares the launch rendering so the preview can never lie.
  var previewText: String {
    let prefix = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    return (prefix + [invocation.terminalInput]).joined(separator: " ")
  }
}

/// What the editor may honestly claim about a profile's execution mode.
/// CLI flag surfaces evolve (`--sandbox danger-full-access`,
/// `--ask-for-approval never`, arbitrary `-c` overrides), so any recognition
/// list goes stale: instead of chasing it, unrecognized extra arguments
/// downgrade the claim to "follows your command line" — the display never
/// asserts Standard it cannot prove (docs-ai 053, review round 2).
nonisolated enum AgentProfileEffectiveExecutionMode: Equatable, Sendable {
  case standard
  case unrestricted
  case followsExtraArguments
}

nonisolated extension AgentProfile {
  /// Extra arguments are respected as explicit user configuration — never
  /// blocked or stripped. A bypass flag the adapter's `observe` recognizes
  /// (`--yolo`, `--dangerously-*`, `--permission-mode bypassPermissions`)
  /// upgrades the claim to `.unrestricted`; any other extra argument defers
  /// the claim entirely.
  var effectiveExecutionMode: AgentProfileEffectiveExecutionMode {
    if executionMode == .unrestricted { return .unrestricted }
    let tokens = ShellWordSplitter.split(extraArguments)
    guard !tokens.isEmpty else { return .standard }
    let observed = AgentRuntimeAdapterRegistry.observe(agent: runtime.agent, arguments: tokens)
    return observed.executionMode == .unrestricted ? .unrestricted : .followsExtraArguments
  }
}

nonisolated enum AgentProfileLaunchPlanError: Error, Equatable, Sendable {
  case runtimeUnavailable(AgentProfileRuntime)
  case accountIsolationUnsupported(AgentProfileRuntime)
  case homeEscapesBase(URL)
  case homeIsSymbolicLink(URL)
}

nonisolated enum AgentProfileLaunchPlanner {
  /// Resolves a profile into one launch plan. Pure: no filesystem access —
  /// home provisioning happens at the launch boundary, not here.
  static func plan(
    for profile: AgentProfile,
    homeBaseDirectory: URL
  ) throws -> AgentProfileLaunchPlan {
    guard let adapter = AgentRuntimeAdapterRegistry.adapter(for: profile.runtime.agent) else {
      throw AgentProfileLaunchPlanError.runtimeUnavailable(profile.runtime)
    }
    let configuration = AgentLaunchConfiguration(
      model: profile.model,
      executionMode: profile.executionMode,
      reasoningEffort: profile.reasoningEffort,
      extraArguments: ShellWordSplitter.split(profile.extraArguments)
    )
    let invocation = try AgentRuntimeAdapterRegistry.makeStartInvocation(
      AgentStartRequest(agent: profile.runtime.agent, intent: .interactive, configuration: configuration)
    )

    var environment: [String: String] = [:]
    var dedicatedHome: URL?
    if profile.bindsDedicatedHome {
      guard let variable = adapter.accountHomeEnvironmentVariable else {
        throw AgentProfileLaunchPlanError.accountIsolationUnsupported(profile.runtime)
      }
      let home = dedicatedHomeDirectory(for: profile.id, base: homeBaseDirectory)
      guard isContained(home, in: homeBaseDirectory) else {
        throw AgentProfileLaunchPlanError.homeEscapesBase(home)
      }
      environment[variable] = pathString(home)
      dedicatedHome = home
    }

    return AgentProfileLaunchPlan(
      profileID: profile.id,
      profileName: profile.name,
      invocation: invocation,
      placement: profile.placement,
      splitDirection: profile.splitDirection,
      environment: environment,
      dedicatedHome: dedicatedHome
    )
  }

  /// Homes derive from the UUID alone — never from the display name or any
  /// user-supplied path (docs-ai 053).
  static func dedicatedHomeDirectory(for profileID: UUID, base: URL) -> URL {
    base
      .appending(path: profileID.uuidString, directoryHint: .isDirectory)
      .standardizedFileURL
  }

  /// Directory URLs render with a trailing slash in `path()`; environment
  /// values and comparisons want the bare path.
  static func pathString(_ url: URL) -> String {
    let path = url.standardizedFileURL.path(percentEncoded: false)
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }

  static func isContained(_ url: URL, in base: URL) -> Bool {
    let baseComponents = base.standardizedFileURL.pathComponents
    let urlComponents = url.standardizedFileURL.pathComponents
    guard urlComponents.count > baseComponents.count else { return false }
    return Array(urlComponents.prefix(baseComponents.count)) == baseComponents
  }
}

/// Creates a dedicated profile home right before launch. The containment
/// check is the same hard gate used for deletion: file operations only ever
/// touch UUID-derived paths inside the base — never a real agent home.
nonisolated enum AgentProfileHomeProvisioner {
  static func provision(home: URL, base: URL, fileManager: FileManager = .default) throws {
    guard AgentProfileLaunchPlanner.isContained(home, in: base) else {
      throw AgentProfileLaunchPlanError.homeEscapesBase(home)
    }
    try validatePhysicalContainment(home: home, base: base, fileManager: fileManager)
    try fileManager.createDirectory(
      at: home,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    // createDirectory attributes only apply on creation; enforce owner-only
    // permissions for pre-existing homes as well.
    try fileManager.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: home.path(percentEncoded: false)
    )
  }

  /// Lexical containment is not enough: a `<uuid>` leaf replaced by a symlink
  /// to a real agent home (`~/.codex`) passes the string check while every
  /// following file operation lands on the link target. Reject a symlink leaf
  /// outright, then require the *canonical* home to stay inside the
  /// *canonical* base — which deliberately keeps a symlinked base itself
  /// legal (e.g. `~/.prowl` living on a synced volume resolves consistently
  /// on both sides of the comparison).
  static func validatePhysicalContainment(
    home: URL,
    base: URL,
    fileManager: FileManager = .default
  ) throws {
    let homePath = AgentProfileLaunchPlanner.pathString(home)
    if let attributes = try? fileManager.attributesOfItem(atPath: homePath),
      attributes[.type] as? FileAttributeType == .typeSymbolicLink
    {
      throw AgentProfileLaunchPlanError.homeIsSymbolicLink(home)
    }
    // `resolvingSymlinksInPath()` leaves ancestors unresolved when the leaf
    // does not exist yet (first provision), so resolve the parent — which
    // must exist for the comparison to mean anything — and reattach the leaf.
    // The leaf itself was just proven not to be a symlink.
    let canonicalHome =
      home
      .deletingLastPathComponent()
      .resolvingSymlinksInPath()
      .appending(path: home.lastPathComponent, directoryHint: .isDirectory)
    let canonicalBase = base.resolvingSymlinksInPath()
    guard AgentProfileLaunchPlanner.isContained(canonicalHome, in: canonicalBase) else {
      throw AgentProfileLaunchPlanError.homeEscapesBase(home)
    }
  }
}
