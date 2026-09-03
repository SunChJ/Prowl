import ComposableArchitecture
import Observation
import Sharing
import SwiftUI

@MainActor
@Observable
final class AgentIslandPresentationModel {
  var notchSize: CGSize?
}

struct AgentIslandRootLayout {
  static let floatingCompactWidth: CGFloat = 300
  static let rosterWidth: CGFloat = 420

  static func width(
    notchCompactWidth: CGFloat?,
    isRosterExpanded: Bool,
    attentionEntryCount: Int
  ) -> CGFloat {
    let compactWidth = notchCompactWidth ?? floatingCompactWidth
    if isRosterExpanded {
      return max(compactWidth, rosterWidth)
    }
    guard attentionEntryCount > 0 else { return compactWidth }
    let attentionWidth = AgentIslandAttentionLayout.layout(entryCount: attentionEntryCount).width
    return max(compactWidth, attentionWidth)
  }
}

struct AgentIslandView: View {
  @Bindable private var appStore: StoreOf<AppFeature>
  @Bindable private var agentsStore: StoreOf<ActiveAgentsFeature>
  @Bindable private var presentation: AgentIslandPresentationModel
  private let terminalManager: WorktreeTerminalManager
  @Shared(.repositoryAppearances) private var repositoryAppearances

  let presentationChanged: (Bool, Bool, AgentIslandDisplayPreference, CGSize) -> Void
  @State private var contentSize = CGSize(width: 420, height: 40)

  init(
    store: StoreOf<AppFeature>,
    terminalManager: WorktreeTerminalManager,
    presentation: AgentIslandPresentationModel,
    presentationChanged: @escaping (Bool, Bool, AgentIslandDisplayPreference, CGSize) -> Void
  ) {
    appStore = store
    agentsStore = store.scope(
      state: \.repositories.activeAgents,
      action: \.repositories.activeAgents
    )
    self.terminalManager = terminalManager
    self.presentation = presentation
    self.presentationChanged = presentationChanged
  }

  var body: some View {
    Group {
      if isVisible {
        islandContent
      } else {
        Color.clear
          .frame(width: 1, height: 1)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .onGeometryChange(for: CGSize.self) { proxy in
      proxy.size
    } action: { newSize in
      guard isVisible else { return }
      contentSize = newSize
      publishPresentation(size: newSize)
    }
    .onChange(of: isVisible, initial: true) { _, _ in
      publishPresentation()
    }
    .onChange(of: agentsStore.isIslandRosterExpanded, initial: true) { _, _ in
      publishPresentation()
    }
    .onChange(of: appStore.settings.agentIslandDisplayPreference, initial: true) { _, _ in
      publishPresentation()
    }
    // The panel is resized to fit after SwiftUI has laid out the new content. Without an explicit
    // top alignment the hosting view centers the content vertically, so for that one pass a taller
    // or shorter island is offset from the top edge and every animated child springs back into
    // place once the frame catches up. Pinning to the top keeps the compact bar at y = 0 throughout.
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .preferredColorScheme(.dark)
  }

  private var islandContent: some View {
    VStack(spacing: 6) {
      compactIsland
      if agentsStore.isIslandRosterExpanded {
        rosterIsland
      } else if !agentsStore.islandAttentionEntries.isEmpty {
        AgentIslandAttentionCollection(
          entries: agentsStore.islandAttentionEntries,
          rowDisplays: rowDisplays,
          workflowBadges: appStore.repositories.workflowRoleBadgesBySurfaceID,
          showTabTitles: appStore.repositories.showActiveAgentTabTitles,
          onTap: { agentsStore.send(.island(.entryTapped($0))) }
        )
      }
    }
    .frame(width: rootWidth)
  }

  private var compactIsland: some View {
    Button {
      agentsStore.send(.islandToggleRoster)
    } label: {
      Group {
        if let notchLayout {
          notchedCompactContent(layout: notchLayout)
        } else {
          HStack(spacing: 9) {
            compactContent
            compactChevron
          }
          .padding(.horizontal, 14)
          .frame(width: 300, height: 40)
        }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .background(.black, in: compactShape)
    .help(agentsStore.isIslandRosterExpanded ? "Hide Active Agents" : "Show Active Agents")
    .accessibilityLabel(
      agentsStore.isIslandRosterExpanded ? "Hide Active Agents" : "Show Active Agents"
    )
    .accessibilityIdentifier("agent-island-compact")
  }

  private func notchedCompactContent(layout: AgentIslandNotchLayout) -> some View {
    HStack(spacing: 0) {
      notchedLeadingContent
        .padding(.leading, 12)
        .frame(width: layout.wingWidth, alignment: .leading)
      Color.clear
        .frame(width: layout.cutoutSize.width)
        .accessibilityHidden(true)
      notchedTrailingContent
        .padding(.trailing, 12)
        .frame(width: layout.wingWidth, alignment: .trailing)
    }
    .frame(width: layout.compactWidth, height: layout.compactHeight)
  }

  private var notchedLeadingContent: some View {
    AgentIslandStateSummaryView(summary: stateSummary, size: .compact)
  }

  private var notchedTrailingContent: some View {
    HStack(spacing: 5) {
      AgentIslandIconCluster(entries: islandEntries, pointSize: 20)
      compactChevron
    }
  }

  private var compactChevron: some View {
    Image(systemName: agentsStore.isIslandRosterExpanded ? "chevron.up" : "chevron.down")
      .font(.caption2.weight(.bold))
      .foregroundStyle(.secondary)
      .accessibilityHidden(true)
  }

  /// The floating pill shows the same per-state counts as the notched wing, one size up.
  private var compactContent: some View {
    HStack(spacing: 8) {
      AgentIslandStateSummaryView(summary: stateSummary, size: .regular)
      Spacer(minLength: 6)
      AgentIslandIconCluster(entries: islandEntries)
    }
  }

  private var stateSummary: AgentIslandStateSummary {
    AgentIslandStateSummary(entries: islandEntries)
  }

  /// Same source as the sidebar overlay: the terminal manager's active surface for the selected
  /// worktree. The reducer's `focusedSurfaceID` is a keyboard-navigation anchor fed by
  /// per-worktree deduplicated `focusChanged` events, so re-selecting a worktree leaves it
  /// pointing at the previously selected worktree's pane.
  private var selectedSurfaceID: UUID? {
    terminalManager.selectedWorktreeID.flatMap { worktreeID in
      terminalManager.stateIfExists(for: worktreeID)?.activeSurfaceID
    }
  }

  private var rosterIsland: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Active Agents")
          .font(.headline)
        Spacer()
        Button {
          agentsStore.send(.islandOpenProwlTapped)
        } label: {
          Label("Open Prowl", systemImage: "arrow.up.forward.app")
        }
        .buttonStyle(.borderless)
        .help("Bring Prowl to the front")
        .accessibilityIdentifier("agent-island-open-prowl")
      }
      .padding(.horizontal, 14)
      .frame(height: 44)

      Divider()

      AgentIslandRosterContent(
        store: agentsStore,
        rowDisplays: rowDisplays,
        workflowBadges: appStore.repositories.workflowRoleBadgesBySurfaceID,
        selectedSurfaceID: selectedSurfaceID
      )
    }
    // Same width as the bar above it: the notched bar is wider than the floating roster.
    .frame(width: rootWidth)
    .background(.black, in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(.separator.opacity(0.55), lineWidth: 1)
    }
    .accessibilityIdentifier("agent-island-roster")
  }

  private var rowDisplays: [ActiveAgentEntry.ID: ActiveAgentRowDisplay] {
    let repositories = appStore.repositories.repositories
    let metadata = SidebarListView.activeAgentWorktreeMetadata(
      repositories: repositories,
      customTitles: appStore.repositories.repositoryCustomTitles,
      repositoryAppearances: repositoryAppearances
    )
    return SidebarListView.activeAgentRowDisplays(
      entries: agentsStore.entries,
      repositories: repositories,
      metadata: metadata
    )
  }

  private var islandEntries: [ActiveAgentEntry] {
    Array(agentsStore.entries)
  }

  private var compactShape: AnyShape {
    if notchLayout != nil {
      return AnyShape(
        UnevenRoundedRectangle(
          topLeadingRadius: 0,
          bottomLeadingRadius: 12,
          bottomTrailingRadius: 12,
          topTrailingRadius: 0
        )
      )
    }
    return AnyShape(Capsule())
  }

  private var notchLayout: AgentIslandNotchLayout? {
    presentation.notchSize.map { AgentIslandNotchLayout(cutoutSize: $0) }
  }

  private var rootWidth: CGFloat {
    AgentIslandRootLayout.width(
      notchCompactWidth: notchLayout?.compactWidth,
      isRosterExpanded: agentsStore.isIslandRosterExpanded,
      attentionEntryCount: agentsStore.islandAttentionEntries.count
    )
  }

  private var isVisible: Bool {
    appStore.settings.agentIslandEnabled && !agentsStore.entries.isEmpty
  }

  private func publishPresentation(size: CGSize? = nil) {
    presentationChanged(
      isVisible,
      agentsStore.isIslandRosterExpanded,
      appStore.settings.agentIslandDisplayPreference,
      size ?? contentSize
    )
  }
}
