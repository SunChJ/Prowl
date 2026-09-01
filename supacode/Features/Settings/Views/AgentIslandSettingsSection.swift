import ComposableArchitecture
import SwiftUI

struct AgentIslandSettingsSection: View {
  @Bindable var store: StoreOf<SettingsFeature>
  @State private var displayCatalog = AgentIslandDisplayCatalog.shared

  var body: some View {
    Section("Agent Island") {
      Toggle(isOn: $store.agentIslandEnabled) {
        Text("Show Agent Island")
        Text("Working stays compact. Blocked and Done appear as stronger agent notifications.")
      }
      .help("Show active agent status at the top of the selected display")
      Picker(selection: $store.agentIslandDisplayPreference) {
        Text("Automatic").tag(AgentIslandDisplayPreference.automatic)
        ForEach(displayPreferences, id: \.self) { preference in
          Text(preference.displayName).tag(preference)
        }
      } label: {
        Text("Display")
        Text(displayCaption)
      }
      .help("Choose where Agent Island appears")
      .disabled(!store.agentIslandEnabled)
    }
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
