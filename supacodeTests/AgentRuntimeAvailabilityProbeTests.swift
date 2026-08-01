import Dependencies
import DependenciesTestSupport
import Foundation
import Sharing
import Testing

@testable import supacode

@MainActor
struct AgentRuntimeAvailabilityProbeTests {
  @Test(.dependencies) func refreshRecordsShellAnswersPerRuntime() async {
    await withDependencies {
      $0.shellClient = ShellClient(
        run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
        runLoginImpl: { _, arguments, _, _ in
          let command = arguments.joined(separator: " ")
          if command.contains("'codex'") {
            return ShellOutput(stdout: "/opt/homebrew/bin/codex", stderr: "", exitCode: 0)
          }
          // `command -v` answers "not found" with a non-zero exit, which the
          // shell client surfaces as a thrown error.
          throw ShellClientError(command: command, stdout: "", stderr: "", exitCode: 1)
        }
      )
    } operation: {
      await AgentRuntimeAvailabilityProbe.refresh()

      @Shared(.agentRuntimeProbedAvailability) var probed
      #expect(probed[.codex] == true)
      #expect(probed[.claude] == false)
    }
  }

  @Test(.dependencies) func refreshLeavesFailedProbesUnansweredAndSkipsPositives() async {
    let probeCalls = LockIsolated(0)
    await withDependencies {
      $0.shellClient = ShellClient(
        run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
        runLoginImpl: { _, _, _, _ in
          probeCalls.withValue { $0 += 1 }
          // A spawn-level failure (not a shell answer) must not masquerade as
          // "not installed".
          throw CocoaError(.fileNoSuchFile)
        }
      )
    } operation: {
      @Shared(.agentRuntimeProbedAvailability) var probed
      // A positive answer is final for the session: no re-probe.
      $probed.withLock { $0[.codex] = true }

      await AgentRuntimeAvailabilityProbe.refresh()

      #expect(probeCalls.value == AgentProfileRuntime.allCases.count - 1)
      #expect(probed[.codex] == true)
      #expect(probed[.claude] == nil)
    }
  }
}
