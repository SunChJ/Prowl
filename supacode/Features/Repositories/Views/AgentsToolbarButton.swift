import SwiftUI

/// What the Agents capsule shows for the selected pane's detected agent.
/// nil means no detected agent: the capsule renders its generic form and the
/// popover becomes the profile launcher (docs-ai 053).
struct AgentsCapsuleState: Equatable {
  let displayName: String
  /// Resolved branded icon; nil falls back to a generic symbol. Resolved by
  /// the assembler with the same two-step token fallback the Active Agents
  /// panel uses, so a wrapper process name never loses the brand icon.
  let iconSource: TabIconSource?
  /// Plain-language explanation of the hand-off action, shown under its
  /// title in the popover row; varies with the source session's state.
  let infoLine: String
}

/// One launchable agent profile row in the Agents popover (docs-ai 053).
struct AgentsLauncherItem: Equatable, Identifiable {
  let id: AgentProfile.ID
  let name: String
  let runtimeName: String
  let isRecommended: Bool
  /// Why the row is disabled ("Claude Code is not installed"); nil = launchable.
  let unavailableReason: String?
}

/// Toolbar entry point for agent-scoped actions, left of the branch title.
/// The capsule identifies the selected pane's agent (the hand-off source);
/// clicking it opens a popover that hosts the agent actions — hand-off when
/// an agent is detected, plus the profile launcher and the manage entry
/// (docs-ai 049/053). The popover is always available: the launcher must not
/// require a detected agent. Live status stays with the terminal, the Active
/// Agents panel, and the central status toast — the capsule deliberately
/// carries no state indicator. A `Menu` cannot host this control: macOS
/// toolbars flatten custom menu labels to their text, dropping the badge, so
/// the popover is the durable container here.
struct AgentsToolbarButton: View {
  let capsule: AgentsCapsuleState?
  let launcherItems: [AgentsLauncherItem]
  let onHandOff: () -> Void
  let onLaunchProfile: (AgentProfile.ID) -> Void
  let onManageProfiles: () -> Void
  @State private var isPopoverPresented = false
  @State private var isHovered = false

  var body: some View {
    Button {
      isPopoverPresented.toggle()
    } label: {
      label
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Capsule())
    }
    // The item opts out of the navigation group's shared background
    // (`sharedBackgroundVisibility(.hidden)`) to stay separate from the
    // branch title, and draws its own glass capsule. `.plain` + an explicit
    // glass background keeps the horizontal padding as tight as the other
    // toolbar buttons; `.buttonStyle(.glass)` pads noticeably wider.
    .buttonStyle(.plain)
    // Hover feedback must live in the glass material itself: a translucent
    // fill layered under `glassEffect` gets swallowed by the material
    // compositing, and `.interactive()` only adds press feedback on macOS.
    .glassEffect(
      isHovered
        ? .regular.tint(.primary.opacity(0.12)).interactive()
        : .regular.interactive(),
      in: Capsule()
    )
    .onHover { isHovered = $0 }
    .help(helpText)
    .accessibilityLabel(accessibilityText)
    .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
      AgentsPopoverContent(
        capsule: capsule,
        launcherItems: launcherItems,
        onHandOff: {
          isPopoverPresented = false
          onHandOff()
        },
        onLaunchProfile: { id in
          isPopoverPresented = false
          onLaunchProfile(id)
        },
        onManageProfiles: {
          isPopoverPresented = false
          onManageProfiles()
        }
      )
    }
  }

  /// Mirrors `WorktreeDetailTitleView`'s label metrics (title3 medium,
  /// 20pt icon slot) so the two neighboring pills read as one family.
  @ViewBuilder
  private var label: some View {
    HStack(spacing: 6) {
      if let capsule {
        agentIcon(capsule)
          .frame(width: 20, height: 20)
        Text(capsule.displayName)
      } else {
        Image(systemName: "sparkles")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
          .frame(width: 20, height: 20)
        Text("Agents")
      }
    }
    .font(.title3.weight(.medium))
  }

  @ViewBuilder
  private func agentIcon(_ capsule: AgentsCapsuleState) -> some View {
    if let source = capsule.iconSource {
      TabIconImage(rawName: source.storageString, pointSize: 17)
    } else {
      Image(systemName: "sparkle")
        .accessibilityHidden(true)
    }
  }

  private var helpText: String {
    guard let capsule else {
      return "Launch an agent profile in this worktree"
    }
    return "Agent actions for \(capsule.displayName)"
  }

  private var accessibilityText: String {
    guard let capsule else { return "Agents" }
    return "Agents: \(capsule.displayName)"
  }
}

/// The agent-actions popover. Each action is one full row — title with a
/// plain-language explanation underneath, highlighted together on hover.
/// Hand-off leads when an agent is detected; the launcher rows follow with
/// the recommended profile first, and the manage entry closes the list.
private struct AgentsPopoverContent: View {
  let capsule: AgentsCapsuleState?
  let launcherItems: [AgentsLauncherItem]
  let onHandOff: () -> Void
  let onLaunchProfile: (AgentProfile.ID) -> Void
  let onManageProfiles: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let capsule {
        AgentsPopoverRow(
          title: "Hand Off…",
          subtitle: capsule.infoLine,
          systemImage: "arrow.left.arrow.right",
          action: onHandOff
        )
        if !launcherItems.isEmpty {
          Divider().padding(.vertical, 4)
        }
      }
      ForEach(launcherItems) { item in
        AgentsPopoverRow(
          title: item.isRecommended ? "Launch \(item.name) ★" : "Launch \(item.name)",
          subtitle: item.unavailableReason
            ?? "New agent in this worktree · \(item.runtimeName)",
          systemImage: "play.circle",
          isEnabled: item.unavailableReason == nil,
          action: { onLaunchProfile(item.id) }
        )
      }
      Divider().padding(.vertical, 4)
      AgentsPopoverRow(
        title: "Manage Agent Profiles…",
        subtitle: "Add presets, models, and accounts in Settings",
        systemImage: "slider.horizontal.3",
        action: onManageProfiles
      )
    }
    .padding(6)
    .frame(width: 280, alignment: .leading)
  }
}

private struct AgentsPopoverRow: View {
  let title: String
  let subtitle: String
  let systemImage: String
  var isEnabled: Bool = true
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: systemImage)
          .frame(width: 16)
          .padding(.top, 2)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.5)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(isHovered && isEnabled ? Color.accentColor.opacity(0.2) : Color.clear)
    )
    .onHover { isHovered = $0 }
  }
}
