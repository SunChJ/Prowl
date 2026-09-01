import ComposableArchitecture
import SwiftUI

struct AgentIslandSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>
  @State private var displayCatalog = AgentIslandDisplayCatalog.shared

  var body: some View {
    Form {
      Section("Agent Island") {
        Toggle("Show Agent Island", isOn: $store.agentIslandEnabled)
          .help("Show active agent status at the top of the selected display")
        Picker("Display", selection: $store.agentIslandDisplayPreference) {
          Text("Automatic").tag(AgentIslandDisplayPreference.automatic)
          ForEach(displayPreferences, id: \.self) { preference in
            Text(preference.displayName).tag(preference)
          }
        }
        .help("Choose where Agent Island appears")
        .disabled(!store.agentIslandEnabled)
        Text(displayCaption)
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Section("Behavior") {
        LabeledContent("Working") {
          Text("Compact carousel")
            .foregroundStyle(.secondary)
        }
        LabeledContent("Blocked and Done") {
          Text("Expanded attention card")
            .foregroundStyle(.secondary)
        }
        LabeledContent("Idle") {
          Text("Expanded roster only")
            .foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
  }

  private var displayPreferences: [AgentIslandDisplayPreference] {
    var preferences = displayCatalog.screens.map {
      AgentIslandDisplayPreference.display(id: $0.id, name: $0.name)
    }
    if case .display(let id, _) = store.agentIslandDisplayPreference,
      !displayCatalog.screens.contains(where: { $0.id == id })
    {
      preferences.append(store.agentIslandDisplayPreference)
    }
    return preferences
  }

  private var displayCaption: String {
    switch store.agentIslandDisplayPreference {
    case .automatic:
      return "Follows the display containing Prowl's main window."
    case .display(let id, let name):
      if displayCatalog.screens.contains(where: { $0.id == id }) {
        return "Pinned to \(name)."
      }
      return "\(name) is disconnected. Using Automatic until it returns."
    }
  }
}

extension AgentIslandDisplayPreference {
  fileprivate var displayName: String {
    switch self {
    case .automatic:
      return "Automatic"
    case .display(_, let name):
      return name
    }
  }
}
