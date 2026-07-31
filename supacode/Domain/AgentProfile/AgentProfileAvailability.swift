import Foundation

/// One shared availability judgment for every profile launcher surface
/// (Agents popover, Command Palette), so entry points can never disagree
/// (docs-ai 053/005). The installation heuristic is deliberately soft — the
/// runtime's default home exists iff the CLI has ever run — so a non-nil
/// warning must gray a row, never block the launch: a false negative
/// (installed but never run, or a dedicated-home-only login) would otherwise
/// lock out a perfectly launchable profile.
nonisolated enum AgentProfileAvailability {
  static func launchWarning(
    for profile: AgentProfile,
    isRuntimeInstalled: (AgentProfileRuntime) -> Bool = isRuntimeInstalled
  ) -> String? {
    guard !isRuntimeInstalled(profile.runtime) else { return nil }
    let name = AgentRuntimeAdapterRegistry.displayName(for: profile.runtime.agent)
    return "\(name) may not be installed"
  }

  /// The runtime's default home exists iff the CLI has ever run; PATH lookups
  /// from a GUI app are unreliable (docs-ai 053). Also the seeding heuristic.
  static func isRuntimeInstalled(_ runtime: AgentProfileRuntime) -> Bool {
    let home = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: runtime.defaultHomeDirectoryName, directoryHint: .isDirectory)
    return FileManager.default.fileExists(atPath: home.path(percentEncoded: false))
  }
}
