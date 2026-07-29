import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Sharing
import Testing

@testable import supacode

@MainActor
struct AgentProfilesFeatureTests {
  @Test(.dependencies) func taskLoadsSettingsAndSelectsFirstProfile() async {
    let profile = AgentProfile(name: "Codex", runtime: .codex)
    let storage = SettingsTestStorage()
    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      @Shared(.userGlobalSettings) var settings
      $settings.withLock { $0.agentProfiles = [profile] }
      return TestStore(initialState: AgentProfilesFeature.State()) {
        AgentProfilesFeature()
      }
    }

    await store.send(.task)
    await store.receive(\.settingsLoaded) {
      $0.settings.agentProfiles = [profile]
      $0.selectedProfileID = profile.id
    }
  }

  @Test(.dependencies) func addProfileAppendsSelectsAndPersists() async {
    let storage = SettingsTestStorage()
    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      TestStore(initialState: AgentProfilesFeature.State()) {
        AgentProfilesFeature()
      } withDependencies: {
        $0.uuid = .incrementing
      }
    }

    let expected = AgentProfile(
      id: UUID(0),
      name: "Claude Code",
      runtime: .claude
    )
    await store.send(.addProfile(.claude)) {
      $0.settings.agentProfiles = [expected]
      $0.selectedProfileID = expected.id
    }
    await store.receive(\.delegate.settingsChanged)
  }

  @Test(.dependencies) func unrestrictedRequiresExplicitConfirmation() async {
    let profile = AgentProfile(name: "Codex", runtime: .codex)
    let storage = SettingsTestStorage()
    let (store, persisted) = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      @Shared(.userGlobalSettings) var settings
      $settings.withLock { $0.agentProfiles = [profile] }
      var initial = AgentProfilesFeature.State()
      initial.settings = settings
      initial.selectedProfileID = profile.id
      let store = TestStore(initialState: initial) {
        AgentProfilesFeature()
      }
      return (store, $settings)
    }

    var edited = store.state.settings
    edited.agentProfiles[0].executionMode = .unrestricted

    // The binding write reverts and asks first.
    await store.send(.binding(.set(\.settings, edited))) {
      $0.alert = AgentProfilesFeature.unrestrictedAlert(profileID: profile.id)
    }

    await store.send(.alert(.presented(.confirmUnrestricted(profile.id)))) {
      $0.alert = nil
      $0.settings.agentProfiles[0].executionMode = .unrestricted
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(persisted.wrappedValue.agentProfiles.first?.executionMode == .unrestricted)
  }

  @Test(.dependencies) func removingBoundProfileConfirmsAndCanTrashHome() async {
    var bound = AgentProfile(name: "Codex · Work", runtime: .codex)
    bound.bindsDedicatedHome = true
    let storage = SettingsTestStorage()
    let trashed = LockIsolated<[AgentProfile.ID]>([])
    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      @Shared(.userGlobalSettings) var settings
      $settings.withLock { $0.agentProfiles = [bound] }
      var initial = AgentProfilesFeature.State()
      initial.settings = settings
      initial.selectedProfileID = bound.id
      return TestStore(initialState: initial) {
        AgentProfilesFeature()
      } withDependencies: {
        $0[AgentProfileHomeClient.self].trashHome = { id in
          trashed.withValue { $0.append(id) }
        }
      }
    }

    await store.send(.removeSelectedTapped) {
      $0.alert = AgentProfilesFeature.removalAlert(profile: bound)
    }
    await store.send(.alert(.presented(.removeTrashingFiles(bound.id)))) {
      $0.alert = nil
      $0.settings.agentProfiles = []
      $0.selectedProfileID = nil
    }
    await store.receive(\.delegate.settingsChanged)
    await store.finish()
    #expect(trashed.value == [bound.id])
  }

  @Test(.dependencies) func removingPurePresetSkipsConfirmationAndFileOperations() async {
    let preset = AgentProfile(name: "Claude", runtime: .claude)
    let storage = SettingsTestStorage()
    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      @Shared(.userGlobalSettings) var settings
      $settings.withLock { $0.agentProfiles = [preset] }
      var initial = AgentProfilesFeature.State()
      initial.settings = settings
      initial.selectedProfileID = preset.id
      return TestStore(initialState: initial) {
        AgentProfilesFeature()
      }
    }

    await store.send(.removeSelectedTapped) {
      $0.settings.agentProfiles = []
      $0.selectedProfileID = nil
    }
    await store.receive(\.delegate.settingsChanged)
  }

  @Test(.dependencies) func moveReordersFallbackPriority() async {
    let first = AgentProfile(name: "First", runtime: .codex)
    let second = AgentProfile(name: "Second", runtime: .claude)
    let storage = SettingsTestStorage()
    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      @Shared(.userGlobalSettings) var settings
      $settings.withLock { $0.agentProfiles = [first, second] }
      var initial = AgentProfilesFeature.State()
      initial.settings = settings
      return TestStore(initialState: initial) {
        AgentProfilesFeature()
      }
    }

    await store.send(.moveProfiles(IndexSet(integer: 1), 0)) {
      $0.settings.agentProfiles = [second, first]
    }
    await store.receive(\.delegate.settingsChanged)
  }

  @Test(.dependencies) func repositoryDefaultAgentProfilePersistsThroughDedicatedAction() async throws {
    let rootURL = URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)")
    let localStorage = RepositoryLocalSettingsTestStorage()
    let profileID = UUID()
    let store = TestStore(
      initialState: RepositorySettingsFeature.State(
        rootURL: rootURL,
        repositoryKind: .plain,
        settings: .default,
        userSettings: .default
      )
    ) {
      RepositorySettingsFeature()
    } withDependencies: {
      $0.repositoryLocalSettingsStorage = localStorage.storage
    }

    await store.send(.setDefaultAgentProfileID(profileID)) {
      $0.userSettings.defaultAgentProfileID = profileID
    }
    await store.receive(\.delegate.settingsChanged)

    let persisted = try JSONDecoder().decode(
      UserRepositorySettings.self,
      from: #require(localStorage.data(at: SupacodePaths.userRepositorySettingsURL(for: rootURL)))
    )
    #expect(persisted.defaultAgentProfileID == profileID)

    await store.send(.setDefaultAgentProfileID(nil)) {
      $0.userSettings.defaultAgentProfileID = nil
    }
    await store.receive(\.delegate.settingsChanged)
  }
}
