import ComposableArchitecture
import Foundation
import Sharing
import SwiftUI

/// Settings → Agents: the global agent profile collection (docs-ai 053).
/// List order is the recommendation fallback order; edits persist to
/// `UserGlobalSettings` the same way global custom commands do.
@Reducer
struct AgentProfilesFeature {
  @ObservableState
  struct State: Equatable {
    var settings: UserGlobalSettings = .default
    var selectedProfileID: AgentProfile.ID?
    /// Passive filesystem check for the selected bound profile's home; never
    /// invokes a CLI (docs-ai 053: no login-status probing).
    var selectedHomeInitialized = false
    @Presents var alert: AlertState<Alert>?

    var selectedProfile: AgentProfile? {
      selectedProfileID.flatMap { id in settings.agentProfiles.first { $0.id == id } }
    }
  }

  enum Action: BindableAction {
    case task
    case settingsLoaded(UserGlobalSettings)
    case binding(BindingAction<State>)
    case addProfile(AgentProfileRuntime)
    case removeSelectedTapped
    case moveProfiles(IndexSet, Int)
    case selectProfile(AgentProfile.ID?)
    case revealProfileFiles
    case alert(PresentationAction<Alert>)
    case delegate(Delegate)
  }

  enum Alert: Equatable {
    case confirmUnrestricted(AgentProfile.ID)
    case removeKeepingFiles(AgentProfile.ID)
    case removeTrashingFiles(AgentProfile.ID)
  }

  @CasePathable
  enum Delegate: Equatable {
    case settingsChanged(UserGlobalSettings)
  }

  @Dependency(AgentProfileHomeClient.self) var homeClient
  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .task:
        return .run { send in
          @Shared(.userGlobalSettings) var settings
          await send(.settingsLoaded(settings))
        }

      case .settingsLoaded(let settings):
        state.settings = settings.normalized()
        if state.selectedProfileID == nil {
          state.selectedProfileID = state.settings.agentProfiles.first?.id
        }
        refreshHomeStatus(&state)
        return .none

      case .binding:
        // `.unrestricted` is never applied silently: the change reverts until
        // the user explicitly confirms it (docs-ai 053).
        @Shared(.userGlobalSettings) var persisted
        if let pendingID = newlyUnrestrictedProfileID(persisted: persisted, edited: state.settings) {
          revertExecutionMode(&state, profileID: pendingID, persisted: persisted)
          state.alert = Self.unrestrictedAlert(profileID: pendingID)
          return .none
        }
        // State deliberately stays as typed — normalizing here would fight
        // the Name field (trim trailing spaces mid-word) and drop the profile
        // outright the moment the field is cleared. Blank names are handled
        // at the persistence boundary instead.
        refreshHomeStatus(&state)
        return persist(state.settings)

      case .addProfile(let runtime):
        let profile = AgentProfile(
          id: uuid(),
          name: AgentRuntimeAdapterRegistry.displayName(for: runtime.agent),
          runtime: runtime
        )
        state.settings.agentProfiles.append(profile)
        state.settings = state.settings.normalized()
        state.selectedProfileID = profile.id
        refreshHomeStatus(&state)
        return persist(state.settings)

      case .removeSelectedTapped:
        guard let profile = state.selectedProfile else { return .none }
        guard profile.bindsDedicatedHome else {
          // Pure presets have no home reference: removal performs zero file
          // operations by construction.
          removeProfile(&state, id: profile.id)
          return persist(state.settings)
        }
        state.alert = Self.removalAlert(profile: profile)
        return .none

      case .moveProfiles(let source, let destination):
        state.settings.agentProfiles.move(fromOffsets: source, toOffset: destination)
        return persist(state.settings)

      case .selectProfile(let id):
        state.selectedProfileID = id
        refreshHomeStatus(&state)
        return .none

      case .revealProfileFiles:
        guard let profile = state.selectedProfile, profile.bindsDedicatedHome else { return .none }
        let id = profile.id
        let client = homeClient
        return .run { _ in client.revealHome(id) }

      case .alert(.presented(.confirmUnrestricted(let profileID))):
        guard let index = state.settings.agentProfiles.firstIndex(where: { $0.id == profileID })
        else { return .none }
        state.settings.agentProfiles[index].executionMode = .unrestricted
        return persist(state.settings)

      case .alert(.presented(.removeKeepingFiles(let profileID))):
        removeProfile(&state, id: profileID)
        return persist(state.settings)

      case .alert(.presented(.removeTrashingFiles(let profileID))):
        removeProfile(&state, id: profileID)
        let client = homeClient
        return .merge(
          persist(state.settings),
          .run { _ in
            do {
              try await client.trashHome(profileID)
            } catch {
              SupaLogger("Settings").warning("Unable to trash profile home: \(error)")
            }
          }
        )

      case .alert:
        return .none

      case .delegate:
        return .none
      }
    }
    .ifLet(\.$alert, action: \.alert)
  }

  private func persist(_ settings: UserGlobalSettings) -> Effect<Action> {
    .run { send in
      @Shared(.userGlobalSettings) var storedSettings
      let sanitized = Self.sanitizedForPersistence(settings, persisted: storedSettings)
      $storedSettings.withLock { $0 = sanitized }
      await send(.delegate(.settingsChanged(sanitized)))
    }
  }

  /// A blank name must never reach disk: decode-time normalization drops
  /// blank-named profiles, which would silently delete the profile (and
  /// orphan a bound home) on the next load. An in-progress blank name keeps
  /// its last persisted name — standard rename-revert semantics — while the
  /// editor state keeps whatever the user is typing.
  nonisolated static func sanitizedForPersistence(
    _ edited: UserGlobalSettings,
    persisted: UserGlobalSettings
  ) -> UserGlobalSettings {
    var settings = edited
    settings.agentProfiles = settings.agentProfiles.map { profile in
      var profile = profile
      if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        profile.name =
          persisted.agentProfiles.first { $0.id == profile.id }?.name
          ?? AgentRuntimeAdapterRegistry.displayName(for: profile.runtime.agent)
      }
      return profile
    }
    return settings.normalized()
  }

  private func removeProfile(_ state: inout State, id: AgentProfile.ID) {
    state.settings.agentProfiles.removeAll { $0.id == id }
    if state.selectedProfileID == id {
      state.selectedProfileID = state.settings.agentProfiles.first?.id
    }
    refreshHomeStatus(&state)
  }

  private func refreshHomeStatus(_ state: inout State) {
    guard let profile = state.selectedProfile, profile.bindsDedicatedHome else {
      state.selectedHomeInitialized = false
      return
    }
    state.selectedHomeInitialized = homeClient.homeExists(profile.id)
  }

  private func newlyUnrestrictedProfileID(
    persisted: UserGlobalSettings,
    edited: UserGlobalSettings
  ) -> AgentProfile.ID? {
    edited.agentProfiles.first { profile in
      profile.executionMode == .unrestricted
        && persisted.agentProfiles.first { $0.id == profile.id }?.executionMode != .unrestricted
    }?.id
  }

  private func revertExecutionMode(
    _ state: inout State,
    profileID: AgentProfile.ID,
    persisted: UserGlobalSettings
  ) {
    guard let index = state.settings.agentProfiles.firstIndex(where: { $0.id == profileID })
    else { return }
    state.settings.agentProfiles[index].executionMode =
      persisted.agentProfiles.first { $0.id == profileID }?.executionMode ?? .standard
  }

  static func unrestrictedAlert(profileID: AgentProfile.ID) -> AlertState<Alert> {
    AlertState {
      TextState("Allow Unrestricted Execution?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmUnrestricted(profileID)) {
        TextState("Allow Unrestricted")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState(
        "The agent will run without permission prompts or sandboxing. "
          + "It can execute any command and modify any file your user can."
      )
    }
  }

  static func removalAlert(profile: AgentProfile) -> AlertState<Alert> {
    AlertState {
      TextState("Remove “\(profile.name)”?")
    } actions: {
      ButtonState(action: .removeKeepingFiles(profile.id)) {
        TextState("Remove Profile")
      }
      ButtonState(role: .destructive, action: .removeTrashingFiles(profile.id)) {
        TextState("Remove and Trash Files")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState(
        "This profile has its own home with login credentials and files. "
          + "“Remove Profile” keeps them on disk; “Remove and Trash Files” moves the folder to the Trash."
      )
    }
  }
}
