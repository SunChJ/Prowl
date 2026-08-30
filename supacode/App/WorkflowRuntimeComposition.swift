// supacode/App/WorkflowRuntimeComposition.swift
// The live boundaries of the workflow runner (docs-ai 063 B3): the activation bridge over the
// dispatch store, the idle wait built on the #733 evidence rules, the profile launch with
// child-only workflow environment, the per-activation watchdog sources, admission facts, and the
// CLI coordinator. Nothing here holds run state; the reducer does.

import ComposableArchitecture
import Foundation

/// Lets the responder dependency (installed before the store exists) reach the coordinator that
/// is built with the CLI router.
@MainActor
final class WorkflowCoordinatorBox {
  var coordinator: WorkflowRuntimeCoordinator?
}

/// Everything the app installs for the workflow runner at its composition root.
struct WorkflowRuntimeInstallation {
  let coordinatorBox: WorkflowCoordinatorBox
  let activation: WorkflowActivationClient
  let runtime: WorkflowRuntimeClient
  let watchdog: WorkflowWatchdogClient
  let queue: WorkflowEffectQueueClient
  let responder: WorkflowCLIResponderClient

  func install(into values: inout DependencyValues) {
    values.workflowActivationClient = activation
    values.workflowRuntimeClient = runtime
    values.workflowWatchdogClient = watchdog
    values.workflowEffectQueue = queue
    values.workflowCLIResponder = responder
  }
}

extension SupacodeApp {
  private static let workflowLogger = SupaLogger("Workflow")

  @MainActor
  static func makeWorkflowRuntime(
    terminalManager: WorktreeTerminalManager,
    storeBox: SupacodeAppStoreBox
  ) -> WorkflowRuntimeInstallation {
    let bridge = makeWorkflowActivationBridge(terminalManager: terminalManager, storeBox: storeBox)
    let coordinatorBox = WorkflowCoordinatorBox()
    return WorkflowRuntimeInstallation(
      coordinatorBox: coordinatorBox,
      activation: makeWorkflowActivationClient(bridge: bridge),
      runtime: makeWorkflowRuntimeClient(terminalManager: terminalManager, storeBox: storeBox),
      watchdog: makeWorkflowWatchdogClient(
        terminalManager: terminalManager, activationBridge: bridge, storeBox: storeBox),
      queue: WorkflowEffectQueue().client,
      responder: WorkflowCLIResponderClient(respond: { requestID, resolution in
        coordinatorBox.coordinator?.resolve(requestID, resolution)
      })
    )
  }

  // MARK: - Activation bridge

  @MainActor
  static func makeWorkflowActivationBridge(
    terminalManager: WorktreeTerminalManager,
    storeBox: SupacodeAppStoreBox
  ) -> LiveWorkflowActivationBridge {
    LiveWorkflowActivationBridge(terminalManager: terminalManager) { surfaceID in
      guard let appStore = storeBox.store else { return nil }
      let resolver = makeTargetResolver(appStore: appStore, terminalManager: terminalManager)
      guard case .success(let target) = resolver.resolve(.pane(surfaceID.uuidString)) else {
        return nil
      }
      return TabResolvedTarget(from: target)
    }
  }

  @MainActor
  static func makeWorkflowActivationClient(bridge: LiveWorkflowActivationBridge)
    -> WorkflowActivationClient
  {
    WorkflowActivationClient(
      openMessage: { bridge.openMessageActivation(surfaceID: $0) },
      cancel: { bridge.cancelActivation(dispatchID: $0) },
      abandon: { bridge.abandonActivation(dispatchID: $0, reason: $1) },
      complete: { bridge.completeActivation(dispatchID: $0, summary: $1) },
      observe: { bridge.observeActivation(dispatchID: $0) }
    )
  }

  // MARK: - Evidence

  /// The same view of a pane `agents wait` and `agents dispatch` use (docs-ai 064.012/014).
  @MainActor
  static func makeWorkflowConditionSnapshot(
    surfaceID: UUID,
    terminalManager: WorktreeTerminalManager,
    storeBox: SupacodeAppStoreBox
  ) -> AgentConditionSnapshot {
    let observed = terminalManager.agentObservationSnapshot(surfaceID: surfaceID)
    let agent = storeBox.store?.state.repositories.activeAgents.entries.first {
      $0.surfaceID == surfaceID
    }
    let evidence = terminalManager.currentAgentSignalEvidence(surfaceID: surfaceID)
    return AgentConditionSnapshot(
      agent: agent,
      signal: evidence.activeTerminal,
      changedSignal: evidence.latest,
      revision: observed?.revision ?? 0,
      isLive: terminalManager.isSurfaceLive(surfaceID),
      signals: terminalManager.agentSignalsPayload(surfaceID: surfaceID)
    )
  }

  // MARK: - Watchdog

  @MainActor
  static func makeWorkflowWatchdogClient(
    terminalManager: WorktreeTerminalManager,
    activationBridge: LiveWorkflowActivationBridge,
    storeBox: SupacodeAppStoreBox
  ) -> WorkflowWatchdogClient {
    WorkflowWatchdogClient(arm: { _, request in
      let sources = WorkflowWatchdog.Sources(
        observeAgent: { terminalManager.observeAgentState(surfaceID: request.surfaceID) },
        observeDispatch: {
          request.dispatchID.flatMap { activationBridge.observeActivation(dispatchID: $0) }
        },
        snapshot: {
          WorkflowWatchdog.snapshot(
            from: makeWorkflowConditionSnapshot(
              surfaceID: request.surfaceID, terminalManager: terminalManager, storeBox: storeBox))
        }
      )
      let watchdog = WorkflowWatchdog(
        request: request, settings: WorkflowWatchdogSettings(), sources: sources)
      return WorkflowWatchdogHandle(verdicts: watchdog.start(), cancel: { watchdog.cancel() })
    })
  }

  // MARK: - Runtime

  /// How long a pane without a detected agent may take to show one before the idle wait gives up
  /// (the CLI wait's appearance grace), and how long a heuristic `blocked` must persist (the
  /// watchdog's blocked grace).
  nonisolated static let workflowRoleWaitPollMilliseconds = 250
  nonisolated static let workflowRoleWaitAppearanceMilliseconds = 10_000
  nonisolated static let workflowRoleWaitBlockedMilliseconds = 30_000

  @MainActor
  static func makeWorkflowRuntimeClient(
    terminalManager: WorktreeTerminalManager,
    storeBox: SupacodeAppStoreBox
  ) -> WorkflowRuntimeClient {
    WorkflowRuntimeClient(
      waitForRole: { surfaceID in
        await waitForWorkflowRole(
          surfaceID: surfaceID, terminalManager: terminalManager, storeBox: storeBox)
      },
      deliverLine: { worktree, surfaceID, line in
        guard let state = terminalManager.stateIfExists(for: worktree.id) else {
          return .insertFailed
        }
        guard state.insertCommittedText(line, in: surfaceID) else { return .insertFailed }
        return state.submitLine(in: surfaceID) ? .delivered : .submitFailed
      },
      launch: { worktree, frozenPlan, request in
        await launchWorkflowRole(
          worktree: worktree, frozenPlan: frozenPlan, request: request,
          terminalManager: terminalManager,
          storeBox: storeBox)
      },
      close: { worktree, surfaceID in
        _ = terminalManager.stateIfExists(for: worktree.id)?.closeSurface(
          id: surfaceID, confirmation: .skip)
      },
      notify: { worktree, text in
        workflowLogger.notice("[\(worktree.name)] \(text)")
        guard let appStore = storeBox.store, appStore.state.settings.systemNotificationsEnabled
        else { return }
        @Dependency(SystemNotificationClient.self) var notifications
        Task { @MainActor in
          await notifications.send("Workflow · \(worktree.name)", text, worktree.id, nil)
        }
      }
    )
  }

  /// The #733 idle precondition without its five-second cap (docs-ai 063.007, "What B3 must do
  /// with each effect"): exact idle evidence returns at once, a detector-only idle view must stay
  /// stable for two seconds, `working` keeps waiting, an exact `needs-input` or a heuristic
  /// `blocked` that persists for the blocked grace ends the wait as blocked.
  @MainActor
  private static func waitForWorkflowRole(
    surfaceID: UUID,
    terminalManager: WorktreeTerminalManager,
    storeBox: SupacodeAppStoreBox
  ) async -> WorkflowRoleWaitOutcome {
    let clock = ContinuousClock()
    var elapsed = 0
    var stabilizer = AgentConditionEvidence.HeuristicStabilizer()
    var blockedSince: Int?
    while !Task.isCancelled {
      let snapshot = makeWorkflowConditionSnapshot(
        surfaceID: surfaceID, terminalManager: terminalManager, storeBox: storeBox)
      guard snapshot.isLive else { return .gone }
      if let pending = terminalManager.pendingAgentDispatchSnapshot(surfaceID: surfaceID) {
        return .dispatchPending(pending.record.id)
      }
      if snapshot.agent == nil {
        if elapsed >= workflowRoleWaitAppearanceMilliseconds { return .noAgent }
      } else {
        switch AgentConditionEvidence.idleVerdict(for: snapshot) {
        case .idle:
          return .idle
        case .settling(let state):
          blockedSince = nil
          let detectorCandidate =
            AgentConditionEvidence.detectorReports(.idle, normalizedState: state)
            && AgentConditionEvidence.allowsHeuristic(.auto, condition: .idle, snapshot: snapshot)
          if stabilizer.observe(
            candidate: detectorCandidate ? state : nil, elapsedMilliseconds: elapsed)
          {
            return .idle
          }
        case .busy(let state):
          _ = stabilizer.observe(candidate: nil, elapsedMilliseconds: elapsed)
          if let signal = snapshot.signal, signal.event == .needsInput,
            AgentConditionEvidence.accepts(signal.confidence, minimum: .auto)
          {
            return .blocked
          }
          if AgentConditionEvidence.detectorReports(.blocked, normalizedState: state) {
            let since = blockedSince ?? elapsed
            blockedSince = since
            if elapsed - since >= workflowRoleWaitBlockedMilliseconds { return .blocked }
          } else {
            blockedSince = nil
          }
        }
      }
      do {
        try await clock.sleep(for: .milliseconds(workflowRoleWaitPollMilliseconds))
      } catch {
        return .cancelled
      }
      elapsed += workflowRoleWaitPollMilliseconds
    }
    return .cancelled
  }

  /// A2's plan → prepare → launch sequence for a `launch` role: the dispatch record is issued
  /// first (when the step expects a delivery), the frozen plan is prepared with its placeholder
  /// prompt, the rendered kickoff prompt and the child-only `PROWL_WORKFLOW_*` values are attached
  /// after preflight (like `attachingDispatch`), and the record is bound to the new pane. Every
  /// failure after a step rolls the earlier ones back: the issuance is cancelled and the pane closed.
  @MainActor
  private static func launchWorkflowRole(
    worktree: Worktree,
    frozenPlan: AgentProfileLaunchPlan,
    request: WorkflowLaunchRequest,
    terminalManager: WorktreeTerminalManager,
    storeBox: SupacodeAppStoreBox
  ) async -> Result<WorkflowLaunchResult, WorkflowLaunchError> {
    var dispatchID: String?
    if request.expectsDelivery {
      do {
        dispatchID = try terminalManager.issueAgentDispatch().record.id
      } catch {
        return .failure(.failed("the launch activation could not be issued: \(error)"))
      }
    }
    func rollback(closing surfaceID: UUID?) {
      if let dispatchID { terminalManager.cancelAgentDispatchIssuance(dispatchID: dispatchID) }
      if let surfaceID {
        _ = terminalManager.stateIfExists(for: worktree.id)?.closeSurface(
          id: surfaceID, confirmation: .skip)
      }
    }
    let attached: PreparedAgentProfileLaunch
    let prepared = await prepareWorkflowLaunch(
      worktree: worktree, frozenPlan: frozenPlan, request: request, terminalManager: terminalManager)
    switch prepared {
    case .failure(let error):
      rollback(closing: nil)
      return .failure(error)
    case .success(let value):
      attached = value
    }
    let launched: LaunchedSurface
    switch terminalManager.launchPreparedAgentProfile(attached, in: worktree) {
    case .failure(let error):
      rollback(closing: nil)
      return .failure(.failed("the profile could not be launched: \(error)"))
    case .success(let value):
      launched = value
    }
    guard let appStore = storeBox.store else {
      rollback(closing: launched.surfaceID)
      return .failure(.failed("the app store is unavailable"))
    }
    let resolver = makeTargetResolver(appStore: appStore, terminalManager: terminalManager)
    guard case .success(let target) = resolver.resolve(.pane(launched.surfaceID.uuidString)) else {
      rollback(closing: launched.surfaceID)
      return .failure(.failed("the launched pane could not be resolved"))
    }
    if let dispatchID {
      do {
        try terminalManager.bindAgentDispatch(
          dispatchID: dispatchID, target: TabResolvedTarget(from: target))
      } catch {
        rollback(closing: launched.surfaceID)
        return .failure(.failed("the launch activation could not be bound: \(error)"))
      }
    }
    if !request.background {
      selectCLIWorktreeContext(
        worktreeID: worktree.id, appStore: appStore, terminalManager: terminalManager)
      terminalManager.state(for: worktree).selectTab(launched.tabID)
    }
    let snapshot = TargetResolutionSnapshotBuilder.makeSnapshot(
      repositoriesState: appStore.state.repositories,
      terminalManager: terminalManager
    )
    let handle = snapshot.worktrees.flatMap(\.tabs).flatMap(\.panes).first {
      $0.id == launched.surfaceID
    }?.handle
    return .success(
      WorkflowLaunchResult(
        pane: WorkflowPaneIdentity(
          surfaceID: launched.surfaceID,
          tabID: launched.tabID.rawValue,
          handle: handle.map { "p\($0)" } ?? launched.surfaceID.uuidString,
          displayName: request.profile.name,
          agent: request.profile.agent),
        dispatchID: dispatchID))
  }

  /// Placement, A2 preflight with the placeholder prompt, then the kickoff prompt and the
  /// `PROWL_WORKFLOW_*` carriers attached to the prepared plan.
  @MainActor
  private static func prepareWorkflowLaunch(
    worktree: Worktree,
    frozenPlan: AgentProfileLaunchPlan,
    request: WorkflowLaunchRequest,
    terminalManager: WorktreeTerminalManager
  ) async -> Result<PreparedAgentProfileLaunch, WorkflowLaunchError> {
    let placement: AgentProfileLaunchRequest.Placement
    switch request.placement {
    case .tab:
      placement = .tab(background: request.background)
    case .split:
      placement = .split(
        anchor: request.anchorSurfaceID,
        direction: splitDirection(request.direction),
        background: request.background
      )
    }
    let launchRequest = AgentProfileLaunchRequest(
      plan: frozenPlan,
      placement: placement,
      workingDirectoryOverride: worktree.workingDirectory,
      inheritanceAnchor: request.anchorSurfaceID,
      title: request.profile.name
    )
    let preparation: PreparedAgentProfileLaunch
    switch await terminalManager.prepareAgentProfileLaunch(launchRequest, in: worktree) {
    case .failure(let error):
      return .failure(.failed("the profile launch could not be prepared: \(error)"))
    case .success(let value):
      preparation = value
    }
    let attachedPlan: AgentProfileLaunchPlan
    do {
      attachedPlan = try preparation.context.request.plan.attachingWorkflow(
        prompt: request.prompt, environment: request.environment)
    } catch {
      return .failure(.failed("the kickoff prompt could not be attached: \(error)"))
    }
    let attached = PreparedAgentProfileLaunch(
      context: FrozenAgentProfileLaunchContext(
        request: AgentProfileLaunchRequest(
          plan: attachedPlan,
          placement: preparation.context.request.placement,
          workingDirectoryOverride: preparation.context.request.workingDirectoryOverride,
          inheritanceAnchor: preparation.context.request.inheritanceAnchor,
          title: preparation.context.request.title),
        inheritedCWD: preparation.context.inheritedCWD,
        anchorSurfaceID: preparation.context.anchorSurfaceID,
        tracksFocusedAnchor: preparation.context.tracksFocusedAnchor,
        tracksInheritedCWD: preparation.context.tracksInheritedCWD),
      warnings: preparation.warnings)
    return .success(attached)
  }

  nonisolated private static func splitDirection(_ direction: WorkflowSplitDirection)
    -> UserCustomSplitDirection
  {
    switch direction {
    case .right: .right
    case .left: .left
    case .top: .top
    case .down: .down
    }
  }

  // MARK: - Admission and coordination

  @MainActor
  static func makeWorkflowAdmissionEnvironment(
    appStore: StoreOf<AppFeature>,
    terminalManager: WorktreeTerminalManager
  ) -> WorkflowAdmissionEnvironment {
    @Shared(.userGlobalSettings) var settings
    let profiles = settings.agentProfiles
    let bundledSkills =
      Bundle.main.resourceURL.flatMap { try? ProwlSkills.bundled(resourcesURL: $0) } ?? []
    return WorkflowAdmissionEnvironment(
      profiles: profiles,
      recommendation: { repositoryRootURL in
        @Shared(.userRepositorySettings(repositoryRootURL)) var repositorySettings
        return (
          repositorySettings.defaultAgentProfileID, repositorySettings.lastLaunchedAgentProfileID
        )
      },
      rememberedBinding: { key in
        @Shared(.userGlobalSettings) var settings
        return settings.rememberedWorkflowBinding(for: key)
      },
      detectedAgent: { surfaceID in
        appStore.state.repositories.activeAgents.entries.first { $0.surfaceID == surfaceID }.map {
          WorkflowDetectedAgent(token: $0.agent.rawValue, displayName: $0.agent.displayName)
        }
      },
      pendingDispatchID: { surfaceID in
        terminalManager.pendingAgentDispatchSnapshot(surfaceID: surfaceID)?.record.id
      },
      worktree: { id in
        resolveCLITerminalWorktree(
          id: id, repositories: Array(appStore.state.repositories.repositories))
      },
      branchName: { worktree in
        WorktreeBranchReader.branchName(of: worktree.workingDirectory) ?? worktree.name
      },
      makeLaunchPlan: { profile in
        try AgentProfileLaunchPlanner.plan(
          for: profile,
          intent: .prompt(WorkflowRunAdmissionPlaceholder.prompt),
          homeBaseDirectory: SupacodePaths.agentProfileHomesDirectory)
      },
      bundledSkill: { id in bundledSkills.first { $0.id == id } }
    )
  }

  @MainActor
  static func makeWorkflowCoordinator(
    appStore: StoreOf<AppFeature>,
    terminalManager: WorktreeTerminalManager,
    rendezvous: WorkflowCLIRendezvous
  ) -> WorkflowRuntimeCoordinator {
    WorkflowRuntimeCoordinator(
      dependencies: WorkflowRuntimeCoordinator.Dependencies(
        admissionEnvironment: {
          makeWorkflowAdmissionEnvironment(appStore: appStore, terminalManager: terminalManager)
        },
        sessions: { Array(appStore.state.workflowRuns.sessions.values) },
        send: { appStore.send(.workflowRuns($0)) },
        pendingDispatchID: {
          terminalManager.pendingAgentDispatchSnapshot(surfaceID: $0)?.record.id
        },
        worktreeRoots: {
          workflowRunRoots(of: Array(appStore.state.repositories.repositories)).map {
            URL(filePath: $0, directoryHint: .isDirectory)
          }
        },
        rendezvous: rendezvous
      ))
  }

  /// The `WORKFLOW_DELIVERY_REQUIRED` refusal of `agents dispatch-complete` for a pane whose
  /// pending record is a workflow activation (decision W3).
  @MainActor
  static func workflowDeliveryRefusal(
    surfaceID: UUID,
    appStore: StoreOf<AppFeature>,
    terminalManager: WorktreeTerminalManager
  ) -> CommandError? {
    guard
      let dispatchID = terminalManager.pendingAgentDispatchSnapshot(surfaceID: surfaceID)?.record.id
    else {
      return nil
    }
    for session in appStore.state.workflowRuns.activeSessions {
      guard let activation = session.run.activation(forDispatchID: dispatchID) else { continue }
      return CommandError(
        code: CLIErrorCode.workflowDeliveryRequired,
        message: activation.completion.deliveryRequiredMessage(
          runID: session.run.id.uuidString, stepID: activation.stepID))
    }
    return nil
  }
}

/// The prompt a frozen `launch` plan is compiled with; `attachingWorkflow` replaces it at launch.
nonisolated enum WorkflowRunAdmissionPlaceholder {
  static let prompt = "[Prowl workflow kickoff]"
}

/// `git symbolic-ref --short HEAD` of a worktree, synchronously and cheaply; nil outside Git.
nonisolated enum WorktreeBranchReader {
  static func branchName(of worktree: URL) -> String? {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/git")
    process.arguments = [
      "-C", worktree.path(percentEncoded: false), "symbolic-ref", "--short", "-q", "HEAD",
    ]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return nil
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    guard let branch = String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !branch.isEmpty
    else { return nil }
    return branch
  }
}
