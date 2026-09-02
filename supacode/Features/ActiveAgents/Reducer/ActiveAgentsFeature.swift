import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Sharing

nonisolated private enum AgentIslandCarouselCancelID: Hashable, Sendable {
  case timer
}

@Reducer
struct ActiveAgentsFeature {
  static let islandCarouselInterval: Duration = .seconds(4)
  static let minimumPanelHeight = 120.0
  static let maximumPanelHeight = 560.0
  static let reservedSidebarListHeight = 200.0

  /// Direction for keyboard navigation across the agent list.
  enum NavigationDirection {
    case next
    case previous
  }

  @ObservableState
  struct State: Equatable {
    var entries: IdentifiedArrayOf<ActiveAgentEntry> = []
    /// Surface that currently has terminal focus, mirrored from `focusChanged` events.
    /// Used as the anchor for keyboard list navigation; not persisted.
    var focusedSurfaceID: UUID?
    var isIslandEnabled = false
    var isIslandRosterExpanded = false
    var isIslandHovered = false
    var islandCarouselEntryID: ActiveAgentEntry.ID?
    @Shared(.appStorage("activeAgentsPanelHidden")) var isPanelHidden: Bool = false
    @Shared(.appStorage("activeAgentsPanelHeight")) var panelHeight: Double = 200
  }

  enum Action: Equatable {
    case agentEntryChanged(ActiveAgentEntry, autoShowPanel: Bool)
    case agentEntryRemoved(ActiveAgentEntry.ID)
    case entryTapped(ActiveAgentEntry.ID)
    /// Context-menu "Hand Off…": parents perform the selection (Repositories)
    /// and open the HUD for this entry's pane (App).
    case handOffTapped(ActiveAgentEntry.ID)
    /// Context-menu "Run Workflow ▸": parents select the entry (Repositories) and open the
    /// start sheet with this entry's pane fixed as the source (App, docs-ai 063 C2).
    case runWorkflowTapped(ActiveAgentEntry.ID, workflowKey: String)
    /// Context-menu "Mark as Read": handled by RepositoriesFeature.
    case markAsReadTapped(ActiveAgentEntry.ID)
    case focusedSurfaceChanged(UUID?)
    case islandEnabledChanged(Bool)
    case islandToggleRoster
    case islandCollapseRoster
    case islandHoverChanged(Bool)
    case islandCarouselTick
    case islandEntryTapped(ActiveAgentEntry.ID)
    case islandHandOffTapped(ActiveAgentEntry.ID)
    case islandRunWorkflowTapped(ActiveAgentEntry.ID, workflowKey: String)
    case islandOpenProwlTapped
    case selectNextEntry
    case selectPreviousEntry
    case togglePanelVisibility
    case panelHeightChanged(Double)
  }

  @Dependency(\.continuousClock) private var clock

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .agentEntryChanged(let entry, let autoShowPanel):
        let previousWorkingEntryIDs = state.islandWorkingEntries.map(\.id)
        state.entries[id: entry.id] = entry
        if autoShowPanel, state.isPanelHidden {
          state.$isPanelHidden.withLock { $0 = false }
        }
        return updateIslandCarouselIfNeeded(
          &state,
          previousWorkingEntryIDs: previousWorkingEntryIDs
        )

      case .agentEntryRemoved(let id):
        let previousWorkingEntryIDs = state.islandWorkingEntries.map(\.id)
        state.entries.remove(id: id)
        if state.entries.isEmpty {
          state.isIslandRosterExpanded = false
        }
        return updateIslandCarouselIfNeeded(
          &state,
          previousWorkingEntryIDs: previousWorkingEntryIDs
        )

      case .entryTapped(let id), .handOffTapped(let id), .runWorkflowTapped(let id, _),
        .islandEntryTapped(let id), .islandHandOffTapped(let id),
        .islandRunWorkflowTapped(let id, _):
        // Mirror the tapped surface into the focus anchor so the panel highlight and
        // keyboard navigation step from the just-selected agent immediately. The async
        // `focusChanged` event can't be relied on here: it is deduplicated per worktree
        // (`emitFocusChangedIfNeeded`), so re-focusing a worktree's previously focused
        // surface emits nothing and would leave the anchor stale.
        state.focusedSurfaceID = state.entries[id: id]?.surfaceID
        switch action {
        case .islandEntryTapped, .islandHandOffTapped, .islandRunWorkflowTapped:
          state.isIslandRosterExpanded = false
          return updateIslandCarousel(state)
        default:
          return .none
        }

      case .markAsReadTapped:
        return .none

      case .focusedSurfaceChanged(let surfaceID):
        state.focusedSurfaceID = surfaceID
        return .none

      case .islandEnabledChanged(let isEnabled):
        state.isIslandEnabled = isEnabled
        if !isEnabled {
          state.isIslandRosterExpanded = false
          state.isIslandHovered = false
        }
        if state.islandCarouselEntryID == nil {
          state.islandCarouselEntryID = state.mostRecentWorkingEntry?.id
        }
        return updateIslandCarousel(state)

      case .islandToggleRoster:
        state.isIslandRosterExpanded.toggle()
        return updateIslandCarousel(state)

      case .islandCollapseRoster:
        state.isIslandRosterExpanded = false
        return updateIslandCarousel(state)

      case .islandHoverChanged(let isHovered):
        state.isIslandHovered = isHovered
        return updateIslandCarousel(state)

      case .islandCarouselTick:
        state.islandCarouselEntryID = state.nextIslandWorkingEntryID
        return .none

      case .islandOpenProwlTapped:
        state.isIslandRosterExpanded = false
        return updateIslandCarousel(state)

      case .selectNextEntry:
        return navigate(&state, direction: .next)

      case .selectPreviousEntry:
        return navigate(&state, direction: .previous)

      case .togglePanelVisibility:
        state.$isPanelHidden.withLock { $0.toggle() }
        return .none

      case .panelHeightChanged(let height):
        state.$panelHeight.withLock { $0 = Self.clampedPanelHeight(height) }
        return .none
      }
    }
  }

  private func updateIslandCarousel(_ state: State) -> Effect<Action> {
    guard
      state.isIslandEnabled,
      !state.isIslandRosterExpanded,
      !state.isIslandHovered,
      state.islandWorkingEntries.count > 1
    else {
      return .cancel(id: AgentIslandCarouselCancelID.timer)
    }
    return .run { send in
      while !Task.isCancelled {
        try await clock.sleep(for: Self.islandCarouselInterval)
        await send(.islandCarouselTick)
      }
    }
    .cancellable(id: AgentIslandCarouselCancelID.timer, cancelInFlight: true)
  }

  private func updateIslandCarouselIfNeeded(
    _ state: inout State,
    previousWorkingEntryIDs: [ActiveAgentEntry.ID]
  ) -> Effect<Action> {
    let workingEntryIDs = state.islandWorkingEntries.map(\.id)
    guard workingEntryIDs != previousWorkingEntryIDs else {
      return .none
    }
    state.islandCarouselEntryID = state.mostRecentWorkingEntry?.id
    return updateIslandCarousel(state)
  }

  /// Moves the keyboard anchor to the neighbouring entry and reuses `entryTapped`
  /// so the parent reducer performs the actual worktree selection + surface focus.
  private func navigate(_ state: inout State, direction: NavigationDirection) -> Effect<Action> {
    guard
      let targetID = Self.entryID(
        navigatingFrom: state.focusedSurfaceID,
        direction: direction,
        in: state.entries
      )
    else {
      return .none
    }
    state.focusedSurfaceID = state.entries[id: targetID]?.surfaceID
    return .send(.entryTapped(targetID))
  }

  /// Resolves the entry to navigate to, anchored on the focused surface.
  ///
  /// When no entry matches the focused surface the list wraps from an edge:
  /// `.next` starts at the first entry and `.previous` at the last. With a known
  /// anchor it steps one position and wraps around the ends.
  static func entryID(
    navigatingFrom focusedSurfaceID: UUID?,
    direction: NavigationDirection,
    in entries: IdentifiedArrayOf<ActiveAgentEntry>
  ) -> ActiveAgentEntry.ID? {
    guard !entries.isEmpty else { return nil }
    let anchorIndex = focusedSurfaceID.flatMap { surfaceID in
      entries.firstIndex { $0.surfaceID == surfaceID }
    }
    switch direction {
    case .next:
      guard let anchorIndex else { return entries.first?.id }
      return entries[(anchorIndex + 1) % entries.count].id
    case .previous:
      guard let anchorIndex else { return entries.last?.id }
      return entries[(anchorIndex - 1 + entries.count) % entries.count].id
    }
  }

  static func clampedPanelHeight(_ height: Double) -> Double {
    min(maximumPanelHeight, max(minimumPanelHeight, height))
  }

  static func maximumPanelHeight(forContainerHeight height: Double) -> Double {
    max(minimumPanelHeight, min(maximumPanelHeight, height - reservedSidebarListHeight))
  }
}

extension ActiveAgentsFeature.State {
  var islandWorkingEntries: [ActiveAgentEntry] {
    entries.enumerated()
      .filter { $0.element.displayState == .working }
      .sorted { lhs, rhs in
        if lhs.element.lastChangedAt != rhs.element.lastChangedAt {
          return lhs.element.lastChangedAt > rhs.element.lastChangedAt
        }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
  }

  var islandAttentionEntries: [ActiveAgentEntry] {
    entries.filter { $0.displayState == .blocked || $0.displayState == .done }
      .sorted { lhs, rhs in
        let lhsPriority = lhs.displayState == .blocked ? 0 : 1
        let rhsPriority = rhs.displayState == .blocked ? 0 : 1
        if lhsPriority != rhsPriority {
          return lhsPriority < rhsPriority
        }
        return lhs.lastChangedAt > rhs.lastChangedAt
      }
  }

  var mostRecentWorkingEntry: ActiveAgentEntry? {
    islandWorkingEntries.first
  }

  var islandCarouselEntry: ActiveAgentEntry? {
    islandCarouselEntryID.flatMap { entries[id: $0] } ?? mostRecentWorkingEntry
  }

  var nextIslandWorkingEntryID: ActiveAgentEntry.ID? {
    let working = islandWorkingEntries
    guard !working.isEmpty else { return nil }
    guard
      let islandCarouselEntryID,
      let index = working.firstIndex(where: { $0.id == islandCarouselEntryID })
    else {
      return working.first?.id
    }
    return working[(index + 1) % working.count].id
  }
}
