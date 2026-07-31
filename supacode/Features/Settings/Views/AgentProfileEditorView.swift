import ComposableArchitecture
import SwiftUI

/// Settings → Agents → native drill-in editor for one profile. The feature
/// owns the alert presentation because its state lives with this destination.
struct AgentProfileEditorView: View {
  @Bindable var store: StoreOf<AgentProfileEditorFeature>

  var body: some View {
    Form {
      launchPreviewSection
      profileSection
      advancedSection
      removalSection
    }
    .formStyle(.grouped)
    .navigationTitle(store.profile.name)
    .task { store.send(.task) }
    .alert($store.scope(state: \.alert, action: \.alert))
  }

  private var profileSection: some View {
    Section("Profile") {
      TextField("Name", text: $store.profile.name)
      Picker("Agent", selection: $store.profile.runtime) {
        ForEach(AgentProfileRuntime.allCases) { runtime in
          Text(AgentRuntimeAdapterRegistry.displayName(for: runtime.agent)).tag(runtime)
        }
      }
      suggestedTextRow(
        title: "Model",
        prompt: "Runtime default",
        text: $store.profile.model,
        suggestions: modelSuggestions
      )
      suggestedTextRow(
        title: "Reasoning Effort",
        prompt: "Runtime default",
        text: $store.profile.reasoningEffort,
        suggestions: effortSuggestions
      )
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

  private var launchPreviewSection: some View {
    Section("Launch Preview") {
      Text("Prowl will execute this exact command.")
        .font(.caption)
        .foregroundStyle(.secondary)
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
    LabeledContent(title) {
      TextField("", text: optionalTextBinding(for: text), prompt: Text(prompt))
    }
  }

  private func suggestedTextRow(
    title: String,
    prompt: String,
    text: Binding<String?>,
    suggestions: [String]
  ) -> some View {
    LabeledContent(title) {
      HStack(spacing: 4) {
        TextField("", text: optionalTextBinding(for: text), prompt: Text(prompt))
        Picker("", selection: suggestionIndex(for: text, suggestions: suggestions)) {
          Text("Runtime Default").tag(0)
          ForEach(suggestions.indices, id: \.self) { index in
            Text(suggestions[index]).tag(index + 1)
          }
        }
        .labelsHidden()
        .frame(width: 28)
        .padding(.trailing, 4)
        .accessibilityLabel("\(title) suggestions")
        .help("Pick a known value, or type any value.")
      }
    }
  }

  private func optionalTextBinding(for text: Binding<String?>) -> Binding<String> {
    Binding(
      get: { text.wrappedValue ?? "" },
      set: { value in
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        text.wrappedValue = trimmed.isEmpty ? nil : value
      }
    )
  }

  private func suggestionIndex(for text: Binding<String?>, suggestions: [String]) -> Binding<Int> {
    Binding(
      get: {
        guard let value = text.wrappedValue, let index = suggestions.firstIndex(of: value) else {
          return 0
        }
        return index + 1
      },
      set: { index in
        text.wrappedValue = index == 0 ? nil : suggestions[index - 1]
      }
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

  private var modelSuggestions: [String] {
    AgentRuntimeAdapterRegistry.adapter(for: store.profile.runtime.agent)?.modelSuggestions ?? []
  }
}
