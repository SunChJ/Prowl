import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

@MainActor
struct AppFeatureAgentSkillsTests {
  @Test(.dependencies) func skillLinkResultsShowToasts() async {
    var state = AppFeature.State(settings: SettingsFeature.State())
    state.settings.selection = .commandLineTool
    state.settings.agentSkills = .init()
    let store = TestStore(initialState: state) {
      AppFeature()
    }
    // The toast auto-dismiss sleeps on a real clock, exactly like the CLI install toast test.
    store.exhaustivity = .off

    await store.send(
      .settings(.agentSkills(.delegate(.linkChanged(.installed(skill: "prowl-cli", target: "Claude Code")))))
    )
    await store.receive(\.repositories.showToast) {
      $0.repositories.statusToast = .success("prowl-cli skill linked for Claude Code")
    }

    await store.send(.settings(.agentSkills(.delegate(.linkChanged(.removed(skill: "prowl-cli", target: "Codex"))))))
    await store.receive(\.repositories.showToast) {
      $0.repositories.statusToast = .success("prowl-cli skill link removed for Codex")
    }

    await store.send(.settings(.agentSkills(.delegate(.linkChanged(.failed(message: "boom"))))))
    await store.receive(\.repositories.showToast) {
      $0.repositories.statusToast = .warning("Skill link failed: boom")
    }
  }
}
