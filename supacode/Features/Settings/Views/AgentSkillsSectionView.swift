import ComposableArchitecture
import SwiftUI

/// Settings → Agents → Command Line Tool → Agent Skills: one row per bundled `user`
/// skill with a status chip and one action per detected target. Link behavior stays
/// in `AgentSkillsFeature`; this view only presents it.
struct AgentSkillsSectionView: View {
  @Bindable var store: StoreOf<AgentSkillsFeature>

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .task { store.send(.task) }
      .alert($store.scope(state: \.alert, action: \.alert))
    } header: {
      VStack(alignment: .leading, spacing: 4) {
        Text("Agent Skills")
        Text(
          "Link the skills bundled in this app into your agents' skill folders, so every agent "
            + "reads the version that matches the installed app. Same status as prowl skills list."
        )
        .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if let loadError = store.loadError {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.yellow)
          .accessibilityLabel("Unavailable")
        VStack(alignment: .leading, spacing: 2) {
          Text("Bundled skills are unavailable.")
          Text(loadError)
            .foregroundStyle(.secondary)
        }
      }
      .font(.callout)
    } else if store.skills.isEmpty {
      Text("This app bundles no installable skills.")
        .foregroundStyle(.secondary)
        .font(.callout)
    } else {
      if store.noTargetsDetected {
        Text(
          "No agent skill folder was found in your home directory. Run Claude Code, Codex, or another "
            + "agent once so it creates its folder, or create one from a terminal with "
            + "prowl skills install --target claude|codex|agents."
        )
        .foregroundStyle(.secondary)
        .font(.callout)
      }
      ForEach(store.skills) { row in
        skillRow(row)
        if row.id != store.skills.last?.id {
          Divider()
        }
      }
    }
  }

  private func skillRow(_ row: AgentSkillsFeature.SkillRow) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(row.skill.name)
          .font(.headline)
        if row.skill.name != row.skill.id {
          Text(row.skill.id)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Reveal") {
          store.send(.revealSkillButtonTapped(skillID: row.id))
        }
        .help("Show the bundled \(row.skill.id) skill folder in Finder")
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
      Text(row.skill.description)
        .foregroundStyle(.secondary)
        .font(.callout)
        .lineLimit(3)
        .help(row.skill.description)
      ForEach(row.links) { link in
        linkRow(skill: row.skill, link: link)
      }
    }
  }

  private func linkRow(skill: BundledSkill, link: AgentSkillsFeature.SkillLink) -> some View {
    HStack(spacing: 8) {
      HStack(spacing: 6) {
        statusIcon(link.status)
        Text(link.target.displayName)
        Text(statusText(link.status))
          .foregroundStyle(.secondary)
      }
      .font(.callout)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(.quaternary, in: Capsule())
      .help(link.linkPath)

      if let destination = link.status.destination {
        Text("→ \(destination)")
          .font(.callout.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(destination)
      }

      Spacer()

      actionButton(skill: skill, link: link)
    }
  }

  @ViewBuilder
  private func actionButton(skill: BundledSkill, link: AgentSkillsFeature.SkillLink) -> some View {
    switch link.status {
    case .notInstalled:
      Button("Install") {
        store.send(.installLink(skillID: skill.id, targetID: link.id))
      }
      .help("Link the bundled \(skill.id) skill into \(link.linkPath)")
      .buttonStyle(.bordered)
      .controlSize(.small)
    case .installed:
      Button("Remove") {
        store.send(.removeLink(skillID: skill.id, targetID: link.id))
      }
      .help("Remove the \(skill.id) skill link at \(link.linkPath); the bundled skill stays in the app")
      .buttonStyle(.bordered)
      .controlSize(.small)
    case .broken:
      Button("Repair") {
        store.send(.installLink(skillID: skill.id, targetID: link.id))
      }
      .help("Replace the broken link at \(link.linkPath) with this app's bundled \(skill.id) skill")
      .buttonStyle(.bordered)
      .controlSize(.small)
    case .installedDifferentSource(_, let destination):
      if destination != nil {
        Button("Replace") {
          store.send(.installLink(skillID: skill.id, targetID: link.id))
        }
        .help("Replace the link to another Prowl build at \(link.linkPath) with this app's bundled \(skill.id) skill")
        .buttonStyle(.bordered)
        .controlSize(.small)
      } else {
        Text("Prowl never deletes it; remove it manually to link here.")
          .foregroundStyle(.secondary)
          .font(.callout)
      }
    }
  }

  @ViewBuilder
  private func statusIcon(_ status: SymlinkInstallStatus) -> some View {
    switch status {
    case .installed:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .accessibilityLabel("Installed")
    case .notInstalled:
      Image(systemName: "xmark.circle")
        .foregroundStyle(.secondary)
        .accessibilityLabel("Not installed")
    case .installedDifferentSource, .broken:
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.yellow)
        .accessibilityLabel(statusText(status))
    }
  }

  private func statusText(_ status: SymlinkInstallStatus) -> String {
    switch status {
    case .installed: "Installed"
    case .notInstalled: "Not installed"
    case .installedDifferentSource(_, let destination): destination == nil ? "Real file or directory" : "Linked elsewhere"
    case .broken: "Broken link"
    }
  }
}
