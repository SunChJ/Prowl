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
    shell: ShellClient = .live,
    isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
  ) async -> CodexShellLaunchEnvironment? {
    guard
      let output = try? await shell.runLogin(
        URL(filePath: "/bin/sh", directoryHint: .notDirectory),
        ["-c", script],
        cwd,
        log: false
      ),
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
    let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count == 4, lines.last?.isEmpty == true else { return nil }
    var values: [String: String] = [:]
    for line in lines.dropLast() {
      let value = String(line)
      guard
        let marker = [executableMarker, homeMarker, codexHomeMarker].first(where: value.hasPrefix),
        values[marker] == nil
      else { return nil }
      values[marker] = String(value.dropFirst(marker.count))
    }
    return values.count == 3 ? values : nil
  }
}
