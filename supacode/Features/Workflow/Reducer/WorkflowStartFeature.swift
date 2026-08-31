// supacode/Features/Workflow/Reducer/WorkflowStartFeature.swift
// The start sheet's interaction state (docs-ai 063 C2, 011 decisions 2-6). The sheet gathers
// the same overrides/inputs/skips `workflow run` accepts and submits through
// WorkflowStartClient.run; it presents the resolver's answers and never re-derives eligibility.

import ComposableArchitecture
import Foundation

@Reducer
struct WorkflowStartFeature {
  @ObservableState
  struct State: Equatable {
    let context: WorkflowStartContext
    var selectedSourceSurfaceID: UUID?
    /// Launch role name → chosen profile. Pre-filled from the resolver's answer.
    var launchSelections: [String: UUID]
    /// Pick role name → chosen pane.
    var pickSelections: [String: UUID] = [:]
    /// Input name → current value. Pre-filled from declared defaults.
    var inputValues: [String: String]
    var skippedSteps: Set<String> = []
    var dontAskAgain: Bool
    /// The launch role whose inline "create from suggestion" confirm block is open.
    var creatingSuggestionForRole: String?
    var suggestionProfileName: String = ""
    var isSubmitting = false
    var submissionError: String?
    /// Starts as the context's snapshot and flips when the inline Install succeeds.
    var cliInstalled: Bool

    init(context: WorkflowStartContext) {
      self.context = context
      cliInstalled = context.cliInstalled
      selectedSourceSurfaceID = context.source?.preselectedSurfaceID
      launchSelections = Dictionary(
        uniqueKeysWithValues: context.launchRoles.compactMap { role in
          role.resolvedProfileID.map { (role.name, $0) }
        })
      inputValues = Dictionary(
        uniqueKeysWithValues: context.definition.inputs.compactMap { input in
          input.defaultValue.map { (input.name, $0.stringValue) }
        })
      dontAskAgain = context.bindModeOverride == .auto
    }

    /// Whether the chosen source must host a detected agent, given the current skip choices.
    var sourceRequiresAgent: Bool {
      WorkflowRunAdmission.deliversToCurrentRole(context.definition, skipped: skippedSteps)
    }

    /// The §5 Skip rule for one step, aware of the other skips already chosen.
    func skipConsequence(for stepID: String) -> WorkflowSkipConsequence? {
      WorkflowRunMachine.startSkipConsequence(
        forStep: stepID, definition: context.definition,
        alreadySkipped: skippedSteps.subtracting([stepID]))
    }

    var canRun: Bool {
      guard !isSubmitting, cliInstalled, context.item.isRunnable else { return false }
      if let source = context.source {
        guard let selected = selectedSourceSurfaceID,
          let candidate = source.candidates.first(where: { $0.surfaceID == selected })
        else { return false }
        if sourceRequiresAgent, candidate.agentToken == nil { return false }
      }
      for role in context.launchRoles {
        guard let chosen = launchSelections[role.name],
          let candidate = role.candidates.first(where: { $0.profileID == chosen }),
          candidate.unavailableReason == nil
        else { return false }
      }
      let picks = context.pickRoles.compactMap { pickSelections[$0.name] }
      guard picks.count == context.pickRoles.count, Set(picks).count == picks.count else {
        return false
      }
      if context.source != nil, let source = selectedSourceSurfaceID, picks.contains(source) {
        return false
      }
      for input in context.definition.inputs where input.defaultValue == nil {
        guard let value = inputValues[input.name],
          !value.trimmingCharacters(in: .whitespaces).isEmpty
        else { return false }
      }
      return true
    }

    /// The submission in the CLI's own vocabulary (011 decision 1).
    var request: WorkflowStartRequest {
      WorkflowStartRequest(
        workflowID: context.item.workflowID,
        worktreeID: context.worktreeID,
        sourceSurfaceID: context.source != nil ? selectedSourceSurfaceID : nil,
        roleBindings: context.launchRoles.compactMap { role in
          launchSelections[role.name].map { "\(role.name)=\($0.uuidString)" }
        }
          + context.pickRoles.compactMap { role in
            pickSelections[role.name].map { "\(role.name)=\($0.uuidString)" }
          },
        inputValues: context.definition.inputs.compactMap { input in
          guard let value = inputValues[input.name] else { return nil }
          return value == input.defaultValue?.stringValue ? nil : "\(input.name)=\(value)"
        },
        skippedSteps: skippedSteps.sorted())
    }
  }

  enum Action: Equatable {
    case sourceSelected(UUID?)
    case launchProfileSelected(role: String, profileID: UUID?)
    case pickPaneSelected(role: String, surfaceID: UUID?)
    case inputChanged(name: String, value: String)
    case skipToggled(stepID: String)
    case dontAskAgainToggled(Bool)
    case createSuggestionTapped(role: String)
    case suggestionNameChanged(String)
    case createSuggestionConfirmed
    case createSuggestionCancelled
    case installCLITapped
    case cliInstallCompleted(success: Bool)
    case cancelTapped
    case runTapped
    case runResponse(WorkflowStartOutcome)
    case delegate(Delegate)

    enum Delegate: Equatable {
      case dismiss
      case started
    }
  }

  @Dependency(WorkflowStartClient.self) var workflowStartClient
  @Dependency(CLIInstallClient.self) var cliInstallClient
  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      handle(state: &state, action: action)
    }
  }

  private func handle(state: inout State, action: Action) -> Effect<Action> {
    switch action {
      case .sourceSelected(let surfaceID):
        state.selectedSourceSurfaceID = surfaceID
        return .none

      case .launchProfileSelected(let role, let profileID):
        state.launchSelections[role] = profileID
        return .none

      case .pickPaneSelected(let role, let surfaceID):
        state.pickSelections[role] = surfaceID
        return .none

      case .inputChanged(let name, let value):
        state.inputValues[name] = value
        return .none

      case .skipToggled(let stepID):
        if state.skippedSteps.contains(stepID) {
          state.skippedSteps.remove(stepID)
          return .none
        }
        // §9: a step without an `expect` offers no skip choice, and a skip whose output a
        // later step needs is refused by admission; the sheet shows the consequence and
        // never arms either.
        guard let consequence = state.skipConsequence(for: stepID) else { return .none }
        if case .endsRun = consequence { return .none }
        state.skippedSteps.insert(stepID)
        return .none

      case .dontAskAgainToggled(let isOn):
        state.dontAskAgain = isOn
        return .none

      case .createSuggestionTapped(let role):
        state.creatingSuggestionForRole = role
        state.suggestionProfileName = Self.suggestedProfileName(role: role, state: state)
        return .none

      case .suggestionNameChanged(let name):
        state.suggestionProfileName = name
        return .none

      case .createSuggestionConfirmed:
        guard let roleName = state.creatingSuggestionForRole,
          let role = state.context.launchRoles.first(where: { $0.name == roleName }),
          let profile = Self.profile(
            from: role.suggestion, name: state.suggestionProfileName, id: uuid())
        else {
          state.creatingSuggestionForRole = nil
          return .none
        }
        // Synchronous inside the reducer, like AgentProfilesFeature.persist: a cancelled
        // effect must not drop the new profile.
        @Shared(.userGlobalSettings) var settings
        $settings.withLock {
          $0.agentProfiles = AgentProfile.normalizedProfiles($0.agentProfiles + [profile])
        }
        state.launchSelections[roleName] = profile.id
        state.creatingSuggestionForRole = nil
        state.suggestionProfileName = ""
        return .none

      case .createSuggestionCancelled:
        state.creatingSuggestionForRole = nil
        state.suggestionProfileName = ""
        return .none

      case .installCLITapped:
        return .run { [cliInstallClient] send in
          do {
            try await cliInstallClient.install(cliDefaultInstallPath)
            await send(.cliInstallCompleted(success: true))
          } catch {
            await send(.cliInstallCompleted(success: false))
          }
        }

      case .cliInstallCompleted(let success):
        if success {
          state.cliInstalled = true
        } else {
          state.submissionError = "The prowl command line tool could not be installed."
        }
        return .none

      case .cancelTapped:
        return .send(.delegate(.dismiss))

      case .runTapped:
        guard state.canRun else { return .none }
        state.isSubmitting = true
        state.submissionError = nil
        let request = state.request
        return .run { send in
          await send(.runResponse(workflowStartClient.run(request)))
        }

      case .runResponse(.started):
        state.isSubmitting = false
        Self.persistBindModeChoice(state: state)
        return .send(.delegate(.started))

      case .runResponse(.failed(_, let message)):
        state.isSubmitting = false
        state.submissionError = message
        return .none

    case .delegate:
      return .none
    }
  }

  /// "Don't ask again" writes the tri-state override (011 decision 5): checked persists
  /// `auto`; unchecked clears a previously persisted `auto` and otherwise leaves the
  /// stored mode (D1's Settings control owns `ask`) alone.
  private static func persistBindModeChoice(state: State) {
    @Shared(.userGlobalSettings) var settings
    let key = state.context.item.key
    if state.dontAskAgain {
      $settings.withLock { $0.setWorkflowBindMode(.auto, for: key) }
    } else if state.context.bindModeOverride == .auto {
      $settings.withLock { $0.setWorkflowBindMode(nil, for: key) }
    }
  }

  private static func suggestedProfileName(role: String, state: State) -> String {
    let launchRole = state.context.launchRoles.first { $0.name == role }
    let runtimeName =
      launchRole?.suggestion?.agent
      .flatMap { AgentProfileRuntime(rawValue: $0) }
      .map { AgentRuntimeAdapterRegistry.displayName(for: $0) }
    let roleTitle = role.prefix(1).uppercased() + role.dropFirst()
    return runtimeName.map { "\(roleTitle) (\($0))" } ?? roleTitle
  }

  /// A real, Settings-manageable profile from the workflow author's `suggest` block.
  private static func profile(
    from suggestion: WorkflowProfileSuggestion?, name: String, id: UUID
  ) -> AgentProfile? {
    guard let suggestion, let agent = suggestion.agent,
      let runtime = AgentProfileRuntime(rawValue: agent)
    else { return nil }
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    return AgentProfile(
      id: id,
      name: trimmed,
      runtime: runtime,
      model: suggestion.model,
      reasoningEffort: suggestion.reasoningEffort,
      executionMode: suggestion.executionMode.flatMap { AgentExecutionMode(rawValue: $0) }
        ?? .standard)
  }
}
