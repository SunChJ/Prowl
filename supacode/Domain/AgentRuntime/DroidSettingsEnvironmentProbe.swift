import Foundation

/// Resolves `FACTORY_RUNTIME_SETTINGS_PATH` from the user's login shell so a value exported in
/// an rc file (not just a Prowl Profile override) is visible before Prowl injects its own
/// `--settings`. Droid's flag outranks the variable, so overriding it silently would drop the
/// user's models, keys, and hooks; the caller merges the resolved file as the base instead, and
/// degrades — never injects — when the probe cannot run.
nonisolated enum DroidSettingsEnvironmentProbe {
  static let variableName = "FACTORY_RUNTIME_SETTINGS_PATH"

  enum Resolution: Equatable, Sendable {
    /// The shell answered: `path` is the exported value, or `nil` when the variable is unset.
    case value(String?)
    /// The shell could not be consulted, so the variable's presence is unknown.
    case failed
  }

  private static let startMarker = "__PROWL_DROID_SETTINGS__"
  private static let endMarker = "__PROWL_DROID_END__"
  private static let script = """
    printf '%s%s\\n' '\(startMarker)' "${\(variableName)-}"
    printf '%s\\n' '\(endMarker)'
    """

  static func resolve(
    cwd: URL,
    pathOverride: String? = nil,
    run: (@Sendable (URL, String) async throws -> ShellOutput)? = nil
  ) async -> Resolution {
    let execute =
      run ?? { cwd, script in
        try await CodexShellProbeProcess().run(cwd: cwd, script: script)
      }
    let effectiveScript: String
    if let pathOverride {
      effectiveScript = "PATH=\(AgentInvocation.shellQuote(pathOverride)); export PATH\n" + script
    } else {
      effectiveScript = script
    }
    guard
      let output = try? await execute(cwd, effectiveScript),
      output.exitCode == 0,
      output.stdout.utf8.count <= 16 * 1_024,
      let value = parse(output.stdout)
    else { return .failed }
    // Droid treats a blank value as unset; trim so trailing shell whitespace does not become a path.
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return .value(trimmed.isEmpty ? nil : trimmed)
  }

  private static func parse(_ output: String) -> String? {
    let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard
      lines.count(where: { $0.hasPrefix(startMarker) }) == 1,
      lines.count(where: { $0 == endMarker }) == 1,
      let startIndex = lines.firstIndex(where: { $0.hasPrefix(startMarker) }),
      lines.indices.contains(startIndex + 1),
      lines[startIndex + 1] == endMarker
    else { return nil }
    return String(lines[startIndex].dropFirst(startMarker.count))
  }
}
