import Darwin
import Foundation
import Testing

@testable import supacode

struct CodexShellProbeProcessTests {
  @Test func hardTimeoutKillsLoginShellThatIgnoresTermination() async throws {
    let root = temporaryDirectory("shell-timeout")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let pidFile = root.appending(path: "pid", directoryHint: .notDirectory)
    let shell = try executableScript(
      in: root,
      name: "hang.sh",
      contents: """
        #!/bin/sh
        trap '' TERM
        printf '%s' "$$" > \(shellQuote(pidFile.path))
        while :; do sleep 1; done
        """
    )
    let process = CodexShellProbeProcess(
      timeout: 0.5,
      maximumOutputBytes: 1_024,
      shellOverride: shell
    )

    await #expect(throws: CodexShellProbeProcessError.timeout) {
      try await process.run(cwd: root, script: "ignored")
    }

    let pidText = try String(contentsOf: pidFile, encoding: .utf8)
    let pid = try #require(pid_t(pidText))
    #expect(kill(pid, 0) == -1)
    #expect(errno == ESRCH)
  }

  @Test func streamingOutputBoundStopsNoisyLoginShell() async throws {
    let root = temporaryDirectory("shell-output")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let shell = try executableScript(
      in: root,
      name: "noisy.sh",
      contents: """
        #!/bin/sh
        while :; do printf '0123456789abcdef'; done
        """
    )
    let process = CodexShellProbeProcess(
      timeout: 2,
      maximumOutputBytes: 128,
      shellOverride: shell
    )

    await #expect(throws: CodexShellProbeProcessError.outputTooLarge) {
      try await process.run(cwd: root, script: "ignored")
    }
  }

  private func executableScript(in root: URL, name: String, contents: String) throws -> URL {
    let url = root.appending(path: name, directoryHint: .notDirectory)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    return url
  }

  private func temporaryDirectory(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appending(
      path: "prowl-tests-\(name)-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
  }

  private func shellQuote(_ value: String) -> String {
    "'" + value.replacing("'", with: "'\"'\"'") + "'"
  }
}
