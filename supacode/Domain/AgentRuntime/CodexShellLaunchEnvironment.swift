import Foundation

nonisolated struct CodexShellLaunchEnvironment: Equatable, Sendable {
  let executableURL: URL
  let processEnvironment: [String: String]
}

nonisolated enum CodexShellLaunchEnvironmentProbe {
  private static let executableMarker = "__PROWL_CODEX_EXECUTABLE__"
  private static let homeMarker = "__PROWL_CODEX_HOME_BASE__"
  private static let codexHomeMarker = "__PROWL_CODEX_HOME__"
  private static let script = """
    executable="$(command -v -- codex)" || exit 1
    printf '%s%s\n' '\(executableMarker)' "$executable"
    printf '%s%s\n' '\(homeMarker)' "${HOME-}"
    printf '%s%s\n' '\(codexHomeMarker)' "${CODEX_HOME-}"
    """

  static func resolve(
    cwd: URL,
    pathOverride: String? = nil,
    run: (@Sendable (URL, String) async throws -> ShellOutput)? = nil,
    isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
  ) async -> CodexShellLaunchEnvironment? {
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
      let values = parse(output.stdout),
      let executable = values[executableMarker], executable.hasPrefix("/"),
      isExecutable(executable),
      let home = values[homeMarker], home.hasPrefix("/")
    else { return nil }

    var environment = ["HOME": home]
    if let codexHome = values[codexHomeMarker], !codexHome.isEmpty {
      guard codexHome.hasPrefix("/") else { return nil }
      environment["CODEX_HOME"] = codexHome
    }
    return CodexShellLaunchEnvironment(
      executableURL: URL(filePath: executable, directoryHint: .notDirectory).standardizedFileURL,
      processEnvironment: environment
    )
  }

  private static func parse(_ output: String) -> [String: String]? {
    let markers = [executableMarker, homeMarker, codexHomeMarker]
    var values: [String: String] = [:]
    for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
      let value = String(line)
      guard let marker = markers.first(where: value.hasPrefix) else { continue }
      guard values[marker] == nil else { return nil }
      values[marker] = String(value.dropFirst(marker.count))
    }
    return values.count == markers.count ? values : nil
  }
}
