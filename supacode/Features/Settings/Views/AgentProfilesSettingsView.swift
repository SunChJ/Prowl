import ComposableArchitecture
import SwiftUI

/// Settings → Agents: profile list plus the editor for the selected profile.
/// List order is the recommendation fallback order.
struct AgentProfilesSettingsView: View {
  @Bindable var store: StoreOf<AgentProfilesFeature>

  var body: some View {
    Form {
      profileListSection
      if let profile = store.selectedProfile, let binding = profileBinding(profile.id) {
        editorSection(profile: profile, binding: binding)
        advancedSection(profile: profile, binding: binding)
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task { store.send(.task) }
    .alert($store.scope(state: \.alert, action: \.alert))
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

        Button {
          store.send(.removeSelectedTapped)
        } label: {
          Label("Remove", systemImage: "minus")
        }
        .disabled(store.selectedProfile == nil)
        .help("Remove the selected profile")
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
        store.send(.selectProfile(profile.id))
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
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Edit this profile")
    }
    .listRowBackground(
      store.selectedProfileID == profile.id
        ? Color.accentColor.opacity(0.12) : Color.clear
    )
    .contextMenu {
      Button("Move Up") { move(profile.id, by: -1) }
        .disabled(index(of: profile.id) == 0)
      Button("Move Down") { move(profile.id, by: 1) }
        .disabled(index(of: profile.id) == store.settings.agentProfiles.count - 1)
    }
  }

  private func editorSection(profile: AgentProfile, binding: Binding<AgentProfile>) -> some View {
    Section("Profile") {
      TextField("Name", text: binding.name)
      Picker("Agent", selection: binding.runtime) {
        ForEach(AgentProfileRuntime.allCases) { runtime in
          Text(AgentRuntimeAdapterRegistry.displayName(for: runtime.agent)).tag(runtime)
        }
      }
      optionalTextRow(
        title: "Model",
        prompt: "Runtime default",
        text: binding.model
      )
      effortRow(profile: profile, binding: binding)
      Picker("Execution Mode", selection: binding.executionMode) {
        Text("Standard").tag(AgentExecutionMode.standard)
        Text("Unrestricted").tag(AgentExecutionMode.unrestricted)
      }
      switch profile.effectiveExecutionMode {
      case .standard:
        EmptyView()
      case .unrestricted:
        Text(
          profile.executionMode == .unrestricted
            ? "Runs without permission prompts or sandboxing."
            : "Extra arguments enable unrestricted execution — no permission prompts or sandboxing."
        )
        .font(.caption)
        .foregroundStyle(.red)
      case .followsExtraArguments:
        Text("Effective execution mode follows your extra arguments.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Picker("Open In", selection: binding.placement) {
        Text("New Tab").tag(AgentProfilePlacement.tab)
        Text("New Split").tag(AgentProfilePlacement.split)
      }
      if profile.placement == .split {
        Picker("Split Direction", selection: binding.splitDirection) {
          ForEach(UserCustomSplitDirection.allCases) { direction in
            Text(direction.title).tag(direction)
          }
        }
      }
    }
  }

  private func advancedSection(profile: AgentProfile, binding: Binding<AgentProfile>) -> some View {
    Section("Advanced") {
      optionalTextRow(
        title: "Extra Arguments",
        prompt: "--flag value",
        text: Binding(
          get: { profile.extraArguments.isEmpty ? nil : profile.extraArguments },
          set: { binding.wrappedValue.extraArguments = $0 ?? "" }
        )
      )
      Toggle("Use Dedicated Home", isOn: binding.bindsDedicatedHome)
        .help("Keep a separate login, usage, and configuration for this profile")
      if profile.bindsDedicatedHome {
        Text(
          "This profile gets its own runtime home: separate login and usage, "
            + "but also separate skills, global instructions, and session history. "
            + "The first launch signs in through the agent itself."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        LabeledContent(
          "Profile Home",
          value: store.selectedHomeInitialized ? "Initialized" : "Not initialized yet"
        )
        Button("Reveal Profile Files") {
          store.send(.revealProfileFiles)
        }
        .help("Open the profile's home folder in Finder")
      }
      launchPreview(profile: profile)
    }
  }

  private func effortRow(profile: AgentProfile, binding: Binding<AgentProfile>) -> some View {
    HStack {
      optionalTextRow(
        title: "Reasoning Effort",
        prompt: "Runtime default",
        text: binding.reasoningEffort
      )
      Menu {
        ForEach(effortSuggestions(for: profile.runtime), id: \.self) { suggestion in
          Button(suggestion) { binding.wrappedValue.reasoningEffort = suggestion }
        }
        Button("Runtime Default") { binding.wrappedValue.reasoningEffort = nil }
      } label: {
        Image(systemName: "chevron.up.chevron.down")
          .accessibilityLabel("Effort suggestions")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help("Pick a known effort level, or type any value")
    }
  }

  private func launchPreview(profile: AgentProfile) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Launch Preview")
      Text(previewText(for: profile))
        .font(.callout.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .lineLimit(nil)
    }
  }

  private func optionalTextRow(
    title: String,
    prompt: String,
    text: Binding<String?>
  ) -> some View {
    TextField(
      title,
      text: Binding(
        get: { text.wrappedValue ?? "" },
        set: { value in
          let trimmed = value.trimmingCharacters(in: .whitespaces)
          text.wrappedValue = trimmed.isEmpty ? nil : value
        }
      ),
      prompt: Text(prompt)
    )
  }

  private func previewText(for profile: AgentProfile) -> String {
    let plan = try? AgentProfileLaunchPlanner.plan(
      for: profile,
      homeBaseDirectory: SupacodePaths.agentProfileHomesDirectory
    )
    return plan?.previewText ?? "Unavailable"
  }

  private func effortSuggestions(for runtime: AgentProfileRuntime) -> [String] {
    AgentRuntimeAdapterRegistry.adapter(for: runtime.agent)?.reasoningEffortSuggestions ?? []
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
