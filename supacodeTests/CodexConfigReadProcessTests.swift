import Foundation
import Testing

@testable import supacode

struct CodexConfigReadProcessTests {
  @Test func profileParserHomeIsOwnerOnlyAndRemovedAfterResponse() async throws {
    let root = temporaryDirectory("codex-process")
    let parser = root.appending(path: "parser", directoryHint: .isDirectory)
    let home = root.appending(path: "home", directoryHint: .isDirectory)
    let profile = home.appending(path: "selected.config.toml", directoryHint: .notDirectory)
    let report = root.appending(path: "report.json", directoryHint: .notDirectory)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try #"notify = ["/tmp/profile", "space value", ""]"#.write(
      to: profile,
      atomically: true,
      encoding: .utf8
    )
    let executable = try makeFakeCodex(in: root, report: report, sleeps: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let process = CodexConfigReadProcess(
      executableURL: executable,
      temporaryBaseDirectory: parser,
      timeout: 2
    )
    let query = CodexConfigQuery(
      kind: .profile(profile),
      codexHome: home,
      cwd: root,
      overrides: []
    )

    let transcript = try await process.query(query)

    #expect(try CodexConfigReadProtocol.decodeNotify(from: transcript) == ["/tmp/profile", "space value", ""])
    let observed = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: report)) as? [String: Any]
    )
    #expect((observed["directory_mode"] as? NSNumber)?.intValue == 0o700)
    #expect((observed["config_mode"] as? NSNumber)?.intValue == 0o600)
    #expect((try? FileManager.default.contentsOfDirectory(atPath: parser.path))?.isEmpty == true)
  }

  @Test func cancellationTerminatesParserAndRemovesScratchHomeWithoutDispatchSleep() async throws {
    let root = temporaryDirectory("codex-cancel")
    let parser = root.appending(path: "parser", directoryHint: .isDirectory)
    let home = root.appending(path: "home", directoryHint: .isDirectory)
    let profile = home.appending(path: "selected.config.toml", directoryHint: .notDirectory)
    let marker = root.appending(path: "started", directoryHint: .notDirectory)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try "notify = [\"/tmp/profile\"]".write(to: profile, atomically: true, encoding: .utf8)
    let executable = try makeFakeCodex(in: root, report: marker, sleeps: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let process = CodexConfigReadProcess(
      executableURL: executable,
      temporaryBaseDirectory: parser,
      timeout: 30
    )
    let task = Task {
      try await process.query(
        CodexConfigQuery(
          kind: .profile(profile),
          codexHome: home,
          cwd: root,
          overrides: []
        )
      )
    }
    for _ in 0..<10_000
    where ((try? FileManager.default.contentsOfDirectory(atPath: parser.path)) ?? []).isEmpty {
      await Task.yield()
    }
    #expect(((try? FileManager.default.contentsOfDirectory(atPath: parser.path)) ?? []).count == 1)

    task.cancel()
    await #expect(throws: (any Error).self) { try await task.value }
    #expect((try? FileManager.default.contentsOfDirectory(atPath: parser.path))?.isEmpty == true)
  }

  private func makeFakeCodex(in root: URL, report: URL, sleeps: Bool) throws -> URL {
    let executable = root.appending(path: "fake-codex.py", directoryHint: .notDirectory)
    let script = """
      #!/usr/bin/python3
      import json, os, pathlib, stat, sys, time
      for _ in range(3):
          sys.stdin.readline()
      home = pathlib.Path(os.environ["CODEX_HOME"])
      config = home / "config.toml"
      report = pathlib.Path(\(String(reflecting: report.path(percentEncoded: false))))
      if \(sleeps ? "True" : "False"):
          report.write_text("started")
          time.sleep(30)
      text = config.read_text() if config.exists() else ""
      notify = ["/tmp/profile", "space value", ""] if "space value" in text else None
      report.write_text(json.dumps({
          "directory_mode": stat.S_IMODE(home.stat().st_mode),
          "config_mode": stat.S_IMODE(config.stat().st_mode) if config.exists() else None
      }))
      print(json.dumps({"jsonrpc":"2.0","id":2,"result":{"config":{"notify":notify}}}), flush=True)
      time.sleep(30)
      """
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    return executable
  }

  private func temporaryDirectory(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appending(
      path: "prowl-tests-\(name)-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
  }
}
