import Foundation
import Testing

@testable import supacode

struct CodexShellLaunchEnvironmentTests {
  @Test func probeUsesLoginShellAndReturnsOnlyValidatedLaunchFacts() async throws {
    let cwd = URL(filePath: "/tmp/Project Space/界", directoryHint: .isDirectory)
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { executable, arguments, currentDirectory, log in
        #expect(executable.path(percentEncoded: false) == "/bin/sh")
        #expect(arguments.first == "-c")
        #expect(currentDirectory == cwd)
        #expect(!log)
        return ShellOutput(
          stdout: """
            __PROWL_CODEX_EXECUTABLE__/opt/custom/bin/codex
            __PROWL_CODEX_HOME_BASE__/Users/tester
            __PROWL_CODEX_HOME__/tmp/codex-home

            """,
          stderr: "ignored",
          exitCode: 0
        )
      }
    )

    let environment = try #require(
      await CodexShellLaunchEnvironmentProbe.resolve(
        cwd: cwd,
        shell: shell,
        isExecutable: { $0 == "/opt/custom/bin/codex" }
      )
    )

    #expect(environment.executableURL.path(percentEncoded: false) == "/opt/custom/bin/codex")
    #expect(
      environment.processEnvironment == [
        "HOME": "/Users/tester",
        "CODEX_HOME": "/tmp/codex-home",
      ])
  }

  @Test func malformedNonAbsoluteAndFailedProbeDegrade() async {
    for output in [
      ShellOutput(stdout: "not-json", stderr: "", exitCode: 0),
      ShellOutput(
        stdout: """
          __PROWL_CODEX_EXECUTABLE__codex
          __PROWL_CODEX_HOME_BASE__/Users/tester
          __PROWL_CODEX_HOME__

          """,
        stderr: "",
        exitCode: 0
      ),
      ShellOutput(
        stdout: """
          __PROWL_CODEX_EXECUTABLE__/opt/codex
          __PROWL_CODEX_HOME_BASE__/Users/tester
          __PROWL_CODEX_HOME__

          """,
        stderr: "",
        exitCode: 1
      ),
    ] {
      let shell = ShellClient(
        run: { _, _, _ in output },
        runLoginImpl: { _, _, _, _ in output }
      )
      #expect(
        await CodexShellLaunchEnvironmentProbe.resolve(
          cwd: URL(filePath: "/tmp", directoryHint: .isDirectory),
          shell: shell,
          isExecutable: { $0 == "/opt/codex" }
        ) == nil
      )
    }
  }

  @Test func capturedShellHomeDefinesDefaultCodexHome() throws {
    let shell = CodexShellLaunchEnvironment(
      executableURL: URL(filePath: "/opt/codex"),
      processEnvironment: ["HOME": "/Users/shell-home"]
    )
    let context = try CodexLaunchContext.capture(
      invocation: AgentInvocation(executable: "/opt/codex", arguments: []),
      inheritedCWD: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      environment: shell.processEnvironment
    )

    #expect(context.codexHome.path(percentEncoded: false) == "/Users/shell-home/.codex/")
  }
}
