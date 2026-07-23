// supacode/CLIService/CLICommandContext.swift
// Per-connection context threaded from the socket server to handlers.

import Foundation

/// Connection-scoped facts about the calling `prowl` process. Handlers that
/// need caller identity (handoff's caller-pane resolution) read it; every
/// other handler ignores it via the protocol's default forwarding.
struct CLICommandContext: Sendable, Equatable {
  /// PID of the peer process on the socket (`LOCAL_PEERPID`), when the kernel
  /// reported one.
  let callerProcessID: pid_t?

  init(callerProcessID: pid_t? = nil) {
    self.callerProcessID = callerProcessID
  }
}

/// A pane owned by the process ancestry of a CLI caller.
struct CallerPane: Sendable, Equatable {
  let worktreeID: Worktree.ID
  let surfaceID: UUID
}

/// Resolves the calling `prowl` process to the pane whose shell spawned it by
/// walking the caller's process ancestry against the live shell-PID map. A
/// caller outside any Prowl pane (another terminal app, a script, tmux's
/// server-owned processes) resolves to nil — never to a guess.
nonisolated enum CallerPaneResolver {
  static func pane(
    forCallerProcess callerPID: pid_t,
    paneByShellPID: [pid_t: CallerPane],
    parentProcessID: (pid_t) -> pid_t? = { pid in
      ProcessDetection.processBSDInfo(pid: pid).map { pid_t($0.pbi_ppid) }
    }
  ) -> CallerPane? {
    var pid = callerPID
    var hops = 0
    while pid > 1, hops < 32 {
      if let pane = paneByShellPID[pid] {
        return pane
      }
      guard let parent = parentProcessID(pid), parent != pid else { return nil }
      pid = parent
      hops += 1
    }
    return nil
  }
}
