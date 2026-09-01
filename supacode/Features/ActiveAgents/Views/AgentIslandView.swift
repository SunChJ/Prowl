import ComposableArchitecture
import Observation
import Sharing
import SwiftUI

@MainActor
@Observable
final class AgentIslandPresentationModel {
  var isNotched = false
}

struct AgentIslandView: View {
  @Bindable private var appStore: StoreOf<AppFeature>
  @Bindable private var agentsStore: StoreOf<ActiveAgentsFeature>
  @Bindable private var presentation: AgentIslandPresentationModel
  @Shared(.repositoryAppearances) private var repositoryAppearances
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let presentationChanged: (Bool, AgentIslandDisplayPreference, CGSize) -> Void
  @State private var contentSize = CGSize(width: 420, height: 40)

  init(
    store: StoreOf<AppFeature>,
    presentation: AgentIslandPresentationModel,
    presentationChanged: @escaping (Bool, AgentIslandDisplayPreference, CGSize) -> Void
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
    VStack(spacing: 6) {
      compactIsland
      if agentsStore.isIslandRosterExpanded {
        rosterIsland
          .transition(expansionTransition)
      } else if let attention = agentsStore.islandAttentionEntries.first {
        attentionIsland(attention)
          .transition(expansionTransition)
      }
    }
    .frame(width: 420)
    .fixedSize(horizontal: false, vertical: true)
    .onGeometryChange(for: CGSize.self) { proxy in
      proxy.size
    } action: { newSize in
      contentSize = newSize
      publishPresentation(size: newSize)
    }
    .onChange(of: isVisible, initial: true) { _, _ in
      publishPresentation()
    }
    .onChange(of: appStore.settings.agentIslandDisplayPreference, initial: true) { _, _ in
      publishPresentation()
    }
    .animation(
      reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.28), value: displayMode
    )
    .preferredColorScheme(.dark)
  }

  private var compactIsland: some View {
    Button {
      agentsStore.send(.islandToggleRoster)
    } label: {
      HStack(spacing: 9) {
        compactContent
        Image(systemName: agentsStore.isIslandRosterExpanded ? "chevron.up" : "chevron.down")
          .font(.caption2.weight(.bold))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 14)
      .frame(width: presentation.isNotched ? 360 : 300, height: 40)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .background(.black, in: compactShape)
    .shadow(color: .black.opacity(presentation.isNotched ? 0 : 0.28), radius: 8, y: 3)
    .help(agentsStore.isIslandRosterExpanded ? "Hide Active Agents" : "Show Active Agents")
    .accessibilityLabel(
      agentsStore.isIslandRosterExpanded ? "Hide Active Agents" : "Show Active Agents"
    )
    .accessibilityIdentifier("agent-island-compact")
    .onHover { isHovered in
      agentsStore.send(.islandHoverChanged(isHovered))
    }
  }

  @ViewBuilder
  private var compactContent: some View {
    if let entry = agentsStore.islandCarouselEntry {
      HStack(spacing: 8) {
        agentIcon(entry)
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
        HStack(spacing: 4) {
          BaguaWorkingIndicator()
          if agentsStore.islandWorkingEntries.count > 1 {
            Text("\(agentsStore.islandWorkingEntries.count)")
              .font(.caption2.monospacedDigit().weight(.semibold))
          }
        }
        .foregroundStyle(.orange)
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
        Text("Idle")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    }
  }

  private func attentionIsland(_ entry: ActiveAgentEntry) -> some View {
    Button {
      agentsStore.send(.islandEntryTapped(entry.id))
    } label: {
      HStack(spacing: 10) {
        agentIcon(entry)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(entry.displayState == .blocked ? "Needs input" : "Completed")
              .font(.headline)
              .foregroundStyle(entry.displayState.foregroundStyle)
            Text(entry.displayName)
              .font(.callout.weight(.medium))
              .foregroundStyle(.primary)
              .lineLimit(1)
          }
          Text(repositoryName(for: entry))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        let additionalCount = agentsStore.islandAttentionEntries.count - 1
        if additionalCount > 0 {
          Text("+\(additionalCount)")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.secondary)
        }
        Image(systemName: "arrow.up.forward.app")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 14)
      .frame(width: 380)
      .frame(minHeight: 68)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .background(.black, in: RoundedRectangle(cornerRadius: 17))
    .overlay {
      RoundedRectangle(cornerRadius: 17)
        .stroke(entry.displayState.foregroundStyle.opacity(0.45), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
    .help("Open \(entry.displayName) in Prowl")
    .accessibilityIdentifier("agent-island-attention")
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

      ActiveAgentsListContent(
        store: agentsStore,
        rowDisplays: rowDisplays,
        selectedSurfaceID: agentsStore.focusedSurfaceID,
        showTabTitles: appStore.repositories.showActiveAgentTabTitles,
        entryAction: ActiveAgentsFeature.Action.islandEntryTapped
      )
      .frame(height: min(CGFloat(agentsStore.entries.count) * 54, 360))
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
    let metadata = ActiveAgentRowDisplayResolver.worktreeMetadata(
      repositories: repositories,
      customTitles: appStore.repositories.repositoryCustomTitles,
      repositoryAppearances: repositoryAppearances
    )
    return ActiveAgentRowDisplayResolver.rowDisplays(
      entries: agentsStore.entries,
      repositories: repositories,
      metadata: metadata
    )
  }

  private func repositoryName(for entry: ActiveAgentEntry) -> String {
    rowDisplays[entry.id]?.repositoryName ?? entry.worktreeName
  }

  private func agentIcon(_ entry: ActiveAgentEntry) -> some View {
    Group {
      if let icon = entry.iconSource {
        TabIconImage(rawName: icon.storageString, pointSize: 17)
      } else {
        Image(systemName: "sparkle")
      }
    }
    .frame(width: 21, height: 21)
    .accessibilityHidden(true)
  }

  private var compactShape: AnyShape {
    if presentation.isNotched {
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

  private var isVisible: Bool {
    appStore.settings.agentIslandEnabled && !agentsStore.entries.isEmpty
  }

  private var displayMode: String {
    if agentsStore.isIslandRosterExpanded { return "roster" }
    if let entry = agentsStore.islandAttentionEntries.first { return "attention-\(entry.id)" }
    return "compact"
  }

  private var expansionTransition: AnyTransition {
    reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
  }

  private func publishPresentation(size: CGSize? = nil) {
    presentationChanged(
      isVisible,
      appStore.settings.agentIslandDisplayPreference,
      size ?? contentSize
    )
  }
}
