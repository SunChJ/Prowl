import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Sharing
import Testing

@testable import supacode

@MainActor
struct AgentProfileEditorFeatureTests {
  @Test(.dependencies) func editsDelegateProfileEdited() async {
    let profile = AgentProfile(name: "Codex", runtime: .codex)
    let store = TestStore(initialState: AgentProfileEditorFeature.State(profile: profile)) {
      AgentProfileEditorFeature()
    }

    var edited = profile
    edited.name = "Codex · Deep"
    await store.send(.binding(.set(\.profile, edited))) {
      $0.profile.name = "Codex · Deep"
    }
    await store.receive(\.delegate.profileEdited)
  }

  @Test(.dependencies) func unrestrictedRequiresExplicitConfirmation() async {
    let profile = AgentProfile(name: "Codex", runtime: .codex)
    let storage = SettingsTestStorage()
    let (store, persisted) = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      @Shared(.userGlobalSettings) var settings
      $settings.withLock { $0.agentProfiles = [profile] }
      let store = TestStore(initialState: AgentProfileEditorFeature.State(profile: profile)) {
        AgentProfileEditorFeature()
      }
      return (store, $settings)
    }

    var edited = profile
    edited.executionMode = .unrestricted

    // The binding write reverts and asks first.
    await store.send(.binding(.set(\.profile, edited))) {
      $0.alert = AgentProfileEditorFeature.unrestrictedAlert()
    }

    await store.send(.alert(.presented(.confirmUnrestricted))) {
      $0.alert = nil
      $0.profile.executionMode = .unrestricted
    }
    await store.receive(\.delegate.profileEdited)
    #expect(persisted.wrappedValue.agentProfiles.first?.executionMode == .standard)
  }

  @Test(.dependencies) func removingBoundProfileConfirmsAndDelegatesTrash() async {
    var bound = AgentProfile(name: "Codex · Work", runtime: .codex)
    bound.bindsDedicatedHome = true
    let store = TestStore(initialState: AgentProfileEditorFeature.State(profile: bound)) {
      AgentProfileEditorFeature()
    }

    await store.send(.removeTapped) {
      $0.alert = AgentProfileEditorFeature.removalAlert(profile: bound)
    }
    await store.send(.alert(.presented(.removeTrashingFiles))) {
      $0.alert = nil
    }
    await store.receive(\.delegate.removeProfile)
  }

  @Test(.dependencies) func unboundProfileWithHomeOnDiskStillConfirmsRemoval() async {
    // bind → launch (home created) → unbind → remove: the gate keys on the
    // disk fact, so the credentials never get orphaned silently.
    let unbound = AgentProfile(name: "Codex · Was Bound", runtime: .codex)
    let store = TestStore(initialState: AgentProfileEditorFeature.State(profile: unbound)) {
      AgentProfileEditorFeature()
    } withDependencies: {
      $0[AgentProfileHomeClient.self].homeExists = { _ in true }
    }

    await store.send(.removeTapped) {
      $0.alert = AgentProfileEditorFeature.removalAlert(profile: unbound)
    }
    await store.send(.alert(.presented(.removeKeepingFiles))) {
      $0.alert = nil
    }
    await store.receive(\.delegate.removeProfile)
  }

  @Test(.dependencies) func removingPurePresetSkipsConfirmation() async {
    let preset = AgentProfile(name: "Claude", runtime: .claude)
    let store = TestStore(initialState: AgentProfileEditorFeature.State(profile: preset)) {
      AgentProfileEditorFeature()
    }

    // No confirmation and no file operations for a preset with no home.
    await store.send(.removeTapped)
    await store.receive(\.delegate.removeProfile)
  }

  @Test(.dependencies) func revealRefreshesThePassiveHomeStatus() async {
    var bound = AgentProfile(name: "Codex · Work", runtime: .codex)
    bound.bindsDedicatedHome = true
    let homeOnDisk = LockIsolated(false)
    let store = TestStore(initialState: AgentProfileEditorFeature.State(profile: bound)) {
      AgentProfileEditorFeature()
    } withDependencies: {
      $0[AgentProfileHomeClient.self].homeExists = { _ in homeOnDisk.value }
      $0[AgentProfileHomeClient.self].revealHome = { _ in homeOnDisk.setValue(true) }
    }

    await store.send(.revealProfileFiles)
    await store.receive(\.homeStatusRefreshed) {
      $0.homeInitialized = true
    }
  }
}
