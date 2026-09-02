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
  @Shared(.repositoryAppearances) private var repositoryAppearances
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let presentationChanged: (Bool, Bool, AgentIslandDisplayPreference, CGSize) -> Void
  @State private var contentSize = CGSize(width: 420, height: 40)

  init(
    store: StoreOf<AppFeature>,
    presentation: AgentIslandPresentationModel,
    presentationChanged: @escaping (Bool, Bool, AgentIslandDisplayPreference, CGSize) -> Void
  ) {
    appStore = store
    agentsStore = store.scope(
      state: \.repositories.activeAgents,
      action: \.repositories.activeAgents
    )
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
          showTabTitles: appStore.repositories.showActiveAgentTabTitles,
          onTap: { agentsStore.send(.islandEntryTapped($0)) }
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
    .shadow(color: .black.opacity(notchLayout == nil ? 0.28 : 0), radius: 8, y: 3)
    .help(agentsStore.isIslandRosterExpanded ? "Hide Active Agents" : "Show Active Agents")
    .accessibilityLabel(
      agentsStore.isIslandRosterExpanded ? "Hide Active Agents" : "Show Active Agents"
    )
    .accessibilityIdentifier("agent-island-compact")
    .onHover { isHovered in
      agentsStore.send(.islandHoverChanged(isHovered))
    }
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

  @ViewBuilder
  private var notchedLeadingContent: some View {
    if let entry = agentsStore.islandCarouselEntry {
      Text(entry.displayName)
        .font(.callout.weight(.semibold))
        .lineLimit(1)
        .id(entry.id)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    } else {
      HStack(spacing: 7) {
        Image(systemName: "person.crop.rectangle.stack")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Text("\(agentsStore.entries.count) \(agentsStore.entries.count == 1 ? "Agent" : "Agents")")
          .font(.callout.weight(.semibold))
          .lineLimit(1)
      }
    }
  }

  private var notchedTrailingContent: some View {
    HStack(spacing: 5) {
      AgentIslandIconCluster(entries: islandEntries)
      compactChevron
    }
  }

  private var compactChevron: some View {
    Image(systemName: agentsStore.isIslandRosterExpanded ? "chevron.up" : "chevron.down")
      .font(.caption2.weight(.bold))
      .foregroundStyle(.secondary)
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private var compactContent: some View {
    if let entry = agentsStore.islandCarouselEntry {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          Text(entry.displayName)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
          Text(repositoryName(for: entry))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 6)
        AgentIslandIconCluster(entries: islandEntries)
      }
      .id(entry.id)
      .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    } else {
      HStack(spacing: 8) {
        Image(systemName: "person.crop.rectangle.stack")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Text("\(agentsStore.entries.count) \(agentsStore.entries.count == 1 ? "Agent" : "Agents")")
          .font(.callout.weight(.semibold))
        Spacer(minLength: 6)
        AgentIslandIconCluster(entries: islandEntries)
      }
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
        selectedSurfaceID: agentsStore.focusedSurfaceID,
        showTabTitles: appStore.repositories.showActiveAgentTabTitles,
        entryAction: ActiveAgentsFeature.Action.islandEntryTapped
      )
    }
    .frame(width: 420)
    .background(.black, in: RoundedRectangle(cornerRadius: 19))
    .overlay {
      RoundedRectangle(cornerRadius: 19)
        .stroke(.separator.opacity(0.55), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
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

  private func repositoryName(for entry: ActiveAgentEntry) -> String {
    rowDisplays[entry.id]?.repositoryName ?? entry.worktreeName
  }

  private var islandEntries: [ActiveAgentEntry] {
    Array(agentsStore.entries)
  }

  private var compactShape: AnyShape {
    if notchLayout != nil {
      return AnyShape(
        UnevenRoundedRectangle(
          topLeadingRadius: 0,
          bottomLeadingRadius: 17,
          bottomTrailingRadius: 17,
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
