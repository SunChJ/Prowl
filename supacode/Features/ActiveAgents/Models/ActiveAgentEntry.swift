import Foundation

struct ActiveAgentEntry: Identifiable, Equatable, Sendable {
  let id: UUID
  /// The worktree that physically owns the agent's terminal surface (the tab's worktree).
  /// Drives navigation/focus (`focusSurface`/`selectWorktree`), so it must stay the surface's
  /// real owner even when the agent runs in a different directory. Display name/branch come from
  /// `workingDirectory` instead — see `SidebarListView.activeAgentRowDisplay`.
  let worktreeID: Worktree.ID
  let worktreeName: String
  /// The agent's current working directory at detection time, used to resolve the displayed
  /// repository/branch. `nil` when the terminal hasn't reported a directory, in which case the
  /// display falls back to `worktreeID`/`worktreeName`.
  let workingDirectory: URL?
  let tabID: TerminalTabID
  /// The title of the agent's own pane: the surface's live title when it has one,
  /// falling back to the tab's display title. Kept per-pane so agents in different
  /// splits of one tab don't all mirror the focused pane's title.
  let paneTitle: String
  let surfaceID: UUID
  let paneIndex: Int
  /// Command/process token used for row icon lookup. This can be more specific than
  /// `agent` for aliases that share one semantic agent, e.g. `omp` vs `pi`.
  let iconLookupToken: String
  let agent: DetectedAgent
  var session: AgentSession?
  let rawState: AgentRawState
  let displayState: AgentDisplayState
  let lastChangedAt: Date
  var displayName: String {
    Self.displayName(iconLookupToken: iconLookupToken, agent: agent)
  }

  /// The user-facing agent name: the launch command token (e.g. `omp`) when it
  /// maps to a known icon, else the semantic agent name (e.g. `pi`). Shared by
  /// the panel rows and the toolbar Agents capsule so both always agree.
  static func displayName(iconLookupToken: String, agent: DetectedAgent) -> String {
    let trimmed = iconLookupToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !trimmed.isEmpty,
      trimmed != "agent",
      CommandIconMap.iconForFirstToken(trimmed) != nil
    else {
      return agent.displayName
    }
    return trimmed
  }

  var iconSource: TabIconSource? {
    CommandIconMap.iconForFirstToken(iconLookupToken) ?? CommandIconMap.iconForFirstToken(agent.iconLookupToken)
  }
}
