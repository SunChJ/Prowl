import Dependencies
import Foundation
import Sharing

extension SharedReaderKey where Self == InMemoryKey<[AgentProfileRuntime: Bool]>.Default {
  /// Session cache of the login-shell executable probe. A missing entry means
  /// the probe has not answered for that runtime yet this session.
  static var agentRuntimeProbedAvailability: Self {
    Self[.inMemory("agentRuntimeProbedAvailability"), default: [:]]
  }
}

extension AgentProfileAvailability {
  /// The launcher surfaces' judgment: the session probe cache first, the
  /// home-directory heuristic while a runtime is unanswered.
  @MainActor
  static func launchWarning(for profile: AgentProfile) -> String? {
    @Shared(.agentRuntimeProbedAvailability) var probed
    return launchWarning(for: profile, probedAvailable: probed[profile.runtime])
  }
}

/// Resolves each runtime's executable through the user's login shell — the
/// same resolution a profile launch uses, so a positive answer means the
/// launch will find the binary (docs-ai 053/005). A GUI app's own PATH is the
/// launchd default and useless for this; the login shell's rc-built PATH is
/// the truth. Results cache for the session: a positive is final, while a
/// negative or unanswered runtime re-probes on the next refresh (opening the
/// Agents popover), so installing a CLI mid-session clears its warning
/// without a relaunch.
@MainActor
enum AgentRuntimeAvailabilityProbe {
  static func refresh() async {
    @Shared(.agentRuntimeProbedAvailability) var probed
    let pending = AgentProfileRuntime.allCases.filter { probed[$0] != true }
    guard !pending.isEmpty else { return }
    await withTaskGroup(of: (AgentProfileRuntime, Bool?).self) { group in
      for runtime in pending {
        group.addTask { (runtime, await probeAvailability(of: runtime)) }
      }
      for await (runtime, availability) in group {
        guard let availability else { continue }
        $probed.withLock { $0[runtime] = availability }
      }
    }
  }

  /// true/false when the login shell answered; nil when the probe itself
  /// could not run (spawn failure) — an unanswered probe must not masquerade
  /// as "not installed".
  private static func probeAvailability(of runtime: AgentProfileRuntime) async -> Bool? {
    guard
      let executable = try? AgentRuntimeAdapterRegistry.makeStartInvocation(
        AgentStartRequest(agent: runtime.agent, intent: .interactive)
      ).executable
    else { return nil }
    @Dependency(ShellClient.self) var shell
    do {
      // `command -v` is a shell builtin, so it runs in an inner /bin/sh that
      // inherits the PATH the outer login shell built from the user's rc.
      _ = try await shell.runLogin(
        URL(fileURLWithPath: "/bin/sh"),
        ["-c", "command -v -- '\(executable)'"],
        nil,
        log: false
      )
      return true
    } catch let error as ShellClientError {
      return error.exitCode > 0 ? false : nil
    } catch {
      return nil
    }
  }
}
