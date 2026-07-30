import ComposableArchitecture
import SwiftUI

/// Settings → Agents → drill-in editor page for one profile. Presented by
/// `AgentProfilesSettingsView` via `navigationDestination`; owns the alert
/// presentation because its feature owns the alert state.
struct AgentProfileEditorView: View {
  @Bindable var store: StoreOf<AgentProfileEditorFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Form {
        profileSection
        advancedSection
        removalSection
      }
      .formStyle(.grouped)
    }
    .task { store.send(.task) }
    .alert($store.scope(state: \.alert, action: \.alert))
  }

  /// Page header: back capsule plus the profile identity. The window title
  /// stays a constant "Agents", so the drill-in page names itself here.
  private var header: some View {
    HStack(spacing: 12) {
      Button {
        store.send(.backTapped)
      } label: {
        Label("Back", systemImage: "chevron.left")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.glass)
      .keyboardShortcut("[", modifiers: .command)
      .help("Back to Agent Profiles (⌘[)")

      VStack(alignment: .leading, spacing: 2) {
        Text(store.profile.name)
          .font(.title3.weight(.semibold))
        Text(AgentRuntimeAdapterRegistry.displayName(for: store.profile.runtime.agent))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.leading, 4)
  }

  private var profileSection: some View {
    Section("Profile") {
      TextField("Name", text: $store.profile.name)
      Picker("Agent", selection: $store.profile.runtime) {
        ForEach(AgentProfileRuntime.allCases) { runtime in
          Text(AgentRuntimeAdapterRegistry.displayName(for: runtime.agent)).tag(runtime)
        }
      }
      optionalTextRow(
        title: "Model",
        prompt: "Runtime default",
        text: $store.profile.model
      )
      effortRow
      Picker("Execution Mode", selection: $store.profile.executionMode) {
        Text("Standard").tag(AgentExecutionMode.standard)
        Text("Unrestricted").tag(AgentExecutionMode.unrestricted)
      }
      switch store.profile.effectiveExecutionMode {
      case .standard:
        EmptyView()
      case .unrestricted:
        Text(
          store.profile.executionMode == .unrestricted
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
      Picker("Open In", selection: $store.profile.placement) {
        Text("New Tab").tag(AgentProfilePlacement.tab)
        Text("New Split").tag(AgentProfilePlacement.split)
      }
      if store.profile.placement == .split {
        Picker("Split Direction", selection: $store.profile.splitDirection) {
          ForEach(UserCustomSplitDirection.allCases) { direction in
            Text(direction.title).tag(direction)
          }
        }
      }
    }
  }

  private var advancedSection: some View {
    Section("Advanced") {
      optionalTextRow(
        title: "Extra Arguments",
        prompt: "--flag value",
        text: Binding(
          get: { store.profile.extraArguments.isEmpty ? nil : store.profile.extraArguments },
          set: { $store.profile.extraArguments.wrappedValue = $0 ?? "" }
        )
      )
      Toggle("Use Dedicated Home", isOn: $store.profile.bindsDedicatedHome)
        .help("Keep a separate login, usage, and configuration for this profile")
      if store.profile.bindsDedicatedHome {
        Text(
          "This profile gets its own runtime home: separate login and usage, "
            + "but also separate skills, global instructions, and session history. "
            + "The first launch signs in through the agent itself."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        LabeledContent(
          "Profile Home",
          value: store.homeInitialized ? "Initialized" : "Not initialized yet"
        )
        Button("Reveal Profile Files") {
          store.send(.revealProfileFiles)
        }
        .help("Open the profile's home folder in Finder")
      }
      launchPreview
    }
  }

  private var removalSection: some View {
    Section {
      Button(role: .destructive) {
        store.send(.removeTapped)
      } label: {
        Text("Remove Profile…")
      }
      .help("Remove this profile")
    }
  }

  private var effortRow: some View {
    HStack {
      optionalTextRow(
        title: "Reasoning Effort",
        prompt: "Runtime default",
        text: $store.profile.reasoningEffort
      )
      Menu {
        ForEach(effortSuggestions, id: \.self) { suggestion in
          Button(suggestion) { $store.profile.reasoningEffort.wrappedValue = suggestion }
        }
        Button("Runtime Default") { $store.profile.reasoningEffort.wrappedValue = nil }
      } label: {
        Image(systemName: "chevron.up.chevron.down")
          .accessibilityLabel("Effort suggestions")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help("Pick a known effort level, or type any value")
    }
  }

  private var launchPreview: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Launch Preview")
      Text(previewText)
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

  private var previewText: String {
    let plan = try? AgentProfileLaunchPlanner.plan(
      for: store.profile,
      homeBaseDirectory: SupacodePaths.agentProfileHomesDirectory
    )
    return plan?.previewText ?? "Unavailable"
  }

  private var effortSuggestions: [String] {
    AgentRuntimeAdapterRegistry.adapter(for: store.profile.runtime.agent)?.reasoningEffortSuggestions
      ?? []
  }
}
