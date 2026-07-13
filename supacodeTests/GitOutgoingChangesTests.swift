import Foundation
import Testing

@testable import supacode

actor OutgoingChangesShellCallStore {
  private(set) var calls: [[String]] = []

  func record(_ arguments: [String]) {
    calls.append(arguments)
  }
}

struct GitOutgoingChangesTests {
  @Test func baseRefUsesPullRequestTargetRemoteIncludingEnterpriseHostAndSSHPort() async {
    let store = OutgoingChangesShellCallStore()
    let shell = ShellClient(
      run: { _, arguments, _ in
        await store.record(arguments)
        if arguments.contains("get-url") {
          switch arguments.last {
          case "origin":
            return ShellOutput(stdout: "git@ghe.example:fork/project.git\n", stderr: "", exitCode: 0)
          case "upstream":
            return ShellOutput(
              stdout: "ssh://git@ghe.example:2222/target/project.git\n",
              stderr: "",
              exitCode: 0
            )
          default:
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
          }
        }
        if arguments.contains("remote") {
          return ShellOutput(stdout: "origin\nupstream\n", stderr: "", exitCode: 0)
        }
        if arguments.contains("rev-parse") {
          return ShellOutput(stdout: "0123456789abcdef\n", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let baseRef = await client.outgoingChangesBaseRef(
      pullRequestURL: "https://ghe.example/target/project/pull/42",
      baseRefName: "main",
      in: URL(fileURLWithPath: "/tmp/repo")
    )

    #expect(baseRef == "upstream/main")
    let calls = await store.calls
    #expect(calls.contains { $0.last == "origin" })
    #expect(calls.contains { $0.last == "upstream" })
    #expect(calls.contains { $0.contains("upstream/main") })
  }

  @Test func baseRefDoesNotFallBackToOriginWhenTargetRemoteDoesNotMatch() async {
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("get-url") {
          return ShellOutput(stdout: "git@github.com:fork/project.git\n", stderr: "", exitCode: 0)
        }
        if arguments.contains("remote") {
          return ShellOutput(stdout: "origin\n", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let baseRef = await client.outgoingChangesBaseRef(
      pullRequestURL: "https://github.com/upstream/project/pull/42",
      baseRefName: "main",
      in: URL(fileURLWithPath: "/tmp/repo")
    )

    #expect(baseRef == nil)
  }

  @Test func outgoingDiffNameStatusUsesCapturedRevisionsAndPreservesUnicodePaths() async throws {
    let store = OutgoingChangesShellCallStore()
    let shell = ShellClient(
      run: { _, arguments, _ in
        await store.record(arguments)
        return ShellOutput(stdout: "M\t中文.swift\n", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)
    let comparison = GitOutgoingChangesComparison(
      baseRef: "upstream/main",
      mergeBase: "merge-base-oid",
      head: "head-oid"
    )

    let output = try await client.outgoingDiffNameStatus(
      for: comparison,
      at: URL(fileURLWithPath: "/tmp/repo")
    )

    #expect(output.contains("中文.swift"))
    let calls = await store.calls
    #expect(calls.count == 1)
    let arguments = calls[0]
    #expect(arguments.contains("core.quotePath=false"))
    #expect(arguments.contains("merge-base-oid"))
    #expect(arguments.contains("head-oid"))
  }

  @Test func outgoingComparisonUsesMergeBaseAndHeadAndExcludesWorkingTreeChanges() async throws {
    let repositoryURL = FileManager.default.temporaryDirectory.appending(
      path: "prowl-outgoing-changes-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: repositoryURL) }

    try runOutgoingChangesGit(["init", repositoryURL.path(percentEncoded: false)])
    try runOutgoingChangesGit([
      "-C", repositoryURL.path(percentEncoded: false), "config", "user.email", "test@example.com",
    ])
    try runOutgoingChangesGit(["-C", repositoryURL.path(percentEncoded: false), "config", "user.name", "Test User"])

    let trackedURL = repositoryURL.appending(path: "tracked.txt")
    try "base\n".write(to: trackedURL, atomically: true, encoding: .utf8)
    try runOutgoingChangesGit(["-C", repositoryURL.path(percentEncoded: false), "add", "tracked.txt"])
    try runOutgoingChangesGit(["-C", repositoryURL.path(percentEncoded: false), "commit", "-m", "base"])
    try runOutgoingChangesGit(["-C", repositoryURL.path(percentEncoded: false), "branch", "-M", "main"])

    try runOutgoingChangesGit(["-C", repositoryURL.path(percentEncoded: false), "checkout", "-b", "feature"])
    try "feature\n".write(to: trackedURL, atomically: true, encoding: .utf8)
    try "feature only\n".write(
      to: repositoryURL.appending(path: "feature-only.txt"),
      atomically: true,
      encoding: .utf8
    )
    try runOutgoingChangesGit([
      "-C", repositoryURL.path(percentEncoded: false), "add", "tracked.txt", "feature-only.txt",
    ])
    try runOutgoingChangesGit(["-C", repositoryURL.path(percentEncoded: false), "commit", "-m", "feature"])

    try runOutgoingChangesGit(["-C", repositoryURL.path(percentEncoded: false), "checkout", "main"])
    try "main advanced\n".write(to: trackedURL, atomically: true, encoding: .utf8)
    try runOutgoingChangesGit(["-C", repositoryURL.path(percentEncoded: false), "add", "tracked.txt"])
    try runOutgoingChangesGit(["-C", repositoryURL.path(percentEncoded: false), "commit", "-m", "main advanced"])
    try runOutgoingChangesGit(["-C", repositoryURL.path(percentEncoded: false), "checkout", "feature"])

    try "uncommitted\n".write(to: trackedURL, atomically: true, encoding: .utf8)
    try "untracked\n".write(
      to: repositoryURL.appending(path: "untracked.txt"),
      atomically: true,
      encoding: .utf8
    )

    let client = GitClient()
    let comparison = try await client.outgoingChangesComparison(from: "main", at: repositoryURL)
    let files = DiffChangedFile.parseNameStatus(
      try await client.outgoingDiffNameStatus(for: comparison, at: repositoryURL)
    )
    let oldContents = await client.showFile("tracked.txt", at: comparison.mergeBase, in: repositoryURL)
    let newContents = await client.showFile("tracked.txt", at: comparison.head, in: repositoryURL)

    #expect(comparison.baseRef == "main")
    #expect(files.map(\.displayPath).sorted() == ["feature-only.txt", "tracked.txt"])
    #expect(!files.contains { $0.displayPath == "untracked.txt" })
    #expect(oldContents == "base")
    #expect(newContents == "feature")
  }
}

private struct OutgoingChangesGitCommandError: Error {
  let output: String
}

@discardableResult
private func runOutgoingChangesGit(_ arguments: [String]) throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  process.arguments = arguments
  var environment = ProcessInfo.processInfo.environment
  environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
  process.environment = environment
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe
  try process.run()
  process.waitUntilExit()
  let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  guard process.terminationStatus == 0 else {
    throw OutgoingChangesGitCommandError(output: output)
  }
  return output
}
