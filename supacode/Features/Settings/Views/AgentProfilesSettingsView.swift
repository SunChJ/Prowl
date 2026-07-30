import ComposableArchitecture
import SwiftUI

/// Settings → Agents: the profile list, with a drill-in editor page per
/// profile (System Settings style). The drill-in is a state-driven content
/// swap, not a nested `NavigationStack`: a stack inside the split view's
/// detail column drops the first programmatic push, blocks sidebar-driven
/// detail switches while pushed, and reconfigures the titlebar layout.
/// List order is the recommendation fallback order.
struct AgentProfilesSettingsView: View {
  @Bindable var store: StoreOf<AgentProfilesFeature>

  var body: some View {
    Group {
      if let editorStore = store.scope(state: \.editor, action: \.editor.presented) {
        AgentProfileEditorView(store: editorStore)
          .transition(.push(from: .trailing))
      } else {
        Form {
          profileListSection
        }
        .formStyle(.grouped)
        .transition(.push(from: .leading))
      }
    }
    .animation(.default, value: store.editor == nil)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task { store.send(.task) }
  }

  private var profileListSection: some View {
    Section {
      if store.settings.agentProfiles.isEmpty {
        Text("No agent profiles yet. Add one to launch agents from the Agents menu.")
          .foregroundStyle(.secondary)
      }
      ForEach(store.settings.agentProfiles) { profile in
        profileRow(profile)
      }
      HStack(spacing: 8) {
        Menu {
          ForEach(AgentProfileRuntime.allCases) { runtime in
            Button(AgentRuntimeAdapterRegistry.displayName(for: runtime.agent)) {
              store.send(.addProfile(runtime))
            }
          }
        } label: {
          Label("Add Profile", systemImage: "plus")
        }
        .fixedSize()
        .help("Add a new agent profile")
        Spacer()
      }
    } header: {
      VStack(alignment: .leading, spacing: 4) {
        Text("Agent Profiles")
        Text(
          "Named launch presets for verified agents, available from the toolbar Agents menu "
            + "and the Command Palette. The first enabled profile is the recommendation fallback."
        )
        .foregroundStyle(.secondary)
      }
    }
  }

  private func profileRow(_ profile: AgentProfile) -> some View {
    HStack(spacing: 8) {
      if let binding = profileBinding(profile.id) {
        Toggle("", isOn: binding.isEnabled)
          .labelsHidden()
          .toggleStyle(.checkbox)
          .help("Show this profile in the Agents menu")
      }
      Button {
        store.send(.profileTapped(profile.id))
      } label: {
        HStack(spacing: 8) {
          Text(profile.name)
          if profile.bindsDedicatedHome {
            Image(systemName: "person.crop.circle.badge.checkmark")
              .foregroundStyle(.secondary)
              .accessibilityLabel("Dedicated account")
              .help("Uses a dedicated home with its own account")
          }
          Spacer()
          Text(AgentRuntimeAdapterRegistry.displayName(for: profile.runtime.agent))
            .foregroundStyle(.secondary)
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Edit this profile")
    }
    .contextMenu {
      Button("Move Up") { move(profile.id, by: -1) }
        .disabled(index(of: profile.id) == 0)
      Button("Move Down") { move(profile.id, by: 1) }
        .disabled(index(of: profile.id) == store.settings.agentProfiles.count - 1)
    }
  }

  private func index(of id: AgentProfile.ID) -> Int? {
    store.settings.agentProfiles.firstIndex { $0.id == id }
  }

  private func move(_ id: AgentProfile.ID, by offset: Int) {
    guard let index = index(of: id) else { return }
    let destination = offset > 0 ? index + 2 : index - 1
    store.send(.moveProfiles(IndexSet(integer: index), destination))
  }

  private func profileBinding(_ id: AgentProfile.ID) -> Binding<AgentProfile>? {
    guard let index = store.settings.agentProfiles.firstIndex(where: { $0.id == id }) else {
      return nil
    }
    return $store.settings.agentProfiles[index]
  }
}
