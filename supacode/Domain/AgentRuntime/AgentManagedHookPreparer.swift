import Foundation

nonisolated struct AgentManagedHookPreparation: Equatable, Sendable {
  let preparedInvocation: AgentHookPreparedInvocation?
  let capability: AgentSignalHookCapability?
  let launchCWD: URL
  let forwardingArgv: [String]?
  let warning: LifecycleCommandWarning?
}

nonisolated enum AgentManagedHookPreparer {
  private struct CodexPreparationOptions {
    let promptIndex: Int?
    let processEnvironment: [String: String]
    let configReadProcess: CodexConfigReadProcess
  }

  private struct CodexRenderingOptions {
    let promptIndex: Int?
    let forwardingArgv: [String]?
  }
  static func prepare(
    plan: AgentProfileLaunchPlan,
    inheritedCWD: URL,
    resources: AgentHookResources?,
    processEnvironment: [String: String],
    codexConfigReadProcess: CodexConfigReadProcess = CodexConfigReadProcess()
  ) async -> AgentManagedHookPreparation {
    guard
      let capability = AgentRuntimeAdapterRegistry.profileAdapter(for: plan.runtime)?.signalHooks
    else {
      return AgentManagedHookPreparation(
        preparedInvocation: nil,
        capability: nil,
        launchCWD: inheritedCWD,
        forwardingArgv: nil,
        warning: nil
      )
    }
    guard let resources,
      resources.bundledCLIPath.hasPrefix("/"),
      FileManager.default.isExecutableFile(atPath: resources.bundledCLIPath)
    else {
      return degraded(
        plan: plan,
        capability: capability,
        launchCWD: inheritedCWD,
        message: "The bundled Prowl hook bridge is unavailable."
      )
    }
    let promptIndex =
      plan.surfaceEnvironment[AgentProfileLaunchPlanner.promptCarrierName] == nil
      ? nil : plan.invocation.arguments.indices.last
    switch capability.runtime {
    case .claude:
      return await prepareClaude(
        plan: plan,
        capability: capability,
        inheritedCWD: inheritedCWD,
        resources: resources,
        promptIndex: promptIndex
      )
    case .codex:
      return await prepareCodex(
        plan: plan,
        capability: capability,
        inheritedCWD: inheritedCWD,
        resources: resources,
        options: CodexPreparationOptions(
          promptIndex: promptIndex,
          processEnvironment: processEnvironment,
          configReadProcess: codexConfigReadProcess
        )
      )
    }
  }

  private static func prepareClaude(
    plan: AgentProfileLaunchPlan,
    capability: AgentSignalHookCapability,
    inheritedCWD: URL,
    resources: AgentHookResources,
    promptIndex: Int?
  ) async -> AgentManagedHookPreparation {
    var hookCommands: [String: String] = [:]
    for event in capability.nativeEvents.keys.sorted() {
      hookCommands[event] = [
        AgentInvocation.shellQuote(resources.bundledCLIPath),
        "agents",
        "_hook",
        AgentNativeHookRuntime.claude.rawValue,
        event,
      ].joined(separator: " ")
    }
    let outcome = await Task.detached(priority: .userInitiated) {
      ClaudeHookSettingsPreparer.prepare(
        invocation: plan.invocation,
        launchDirectory: inheritedCWD,
        promptArgumentIndex: promptIndex,
        hookCommands: hookCommands,
        readFile: ClaudeSettingsStableReader.read
      )
    }.value
    return AgentManagedHookPreparation(
      preparedInvocation: outcome.prepared,
      capability: capability,
      launchCWD: inheritedCWD,
      forwardingArgv: nil,
      warning: outcome.warning
    )
  }

  private static func prepareCodex(
    plan: AgentProfileLaunchPlan,
    capability: AgentSignalHookCapability,
    inheritedCWD: URL,
    resources: AgentHookResources,
    options: CodexPreparationOptions
  ) async -> AgentManagedHookPreparation {
    let context: CodexLaunchContext
    do {
      context = try CodexLaunchContext.capture(
        invocation: plan.invocation,
        inheritedCWD: inheritedCWD,
        dedicatedHome: plan.dedicatedHome,
        environment: options.processEnvironment,
        promptArgumentIndex: options.promptIndex
      )
    } catch {
      return degraded(
        plan: plan,
        capability: capability,
        launchCWD: inheritedCWD,
        message: "The effective Codex launch context could not be resolved."
      )
    }
    let resolver = CodexEffectiveNotifyResolver(
      bundledCLIPath: resources.bundledCLIPath,
      query: options.configReadProcess.query
    )
    switch await resolver.resolve(context) {
    case .absent:
      return preparedCodex(
        plan: plan,
        capability: capability,
        context: context,
        resources: resources,
        options: CodexRenderingOptions(
          promptIndex: options.promptIndex,
          forwardingArgv: nil
        )
      )
    case .present(let argv):
      return preparedCodex(
        plan: plan,
        capability: capability,
        context: context,
        resources: resources,
        options: CodexRenderingOptions(
          promptIndex: options.promptIndex,
          forwardingArgv: argv
        )
      )
    case .degraded(let message):
      return degraded(
        plan: plan,
        capability: capability,
        launchCWD: context.effectiveCWD,
        message: message
      )
    }
  }

  private static func preparedCodex(
    plan: AgentProfileLaunchPlan,
    capability: AgentSignalHookCapability,
    context: CodexLaunchContext,
    resources: AgentHookResources,
    options: CodexRenderingOptions
  ) -> AgentManagedHookPreparation {
    AgentManagedHookPreparation(
      preparedInvocation: CodexManagedNotifyRenderer.prepare(
        invocation: plan.invocation,
        bundledCLIPath: resources.bundledCLIPath,
        promptArgumentIndex: options.promptIndex
      ),
      capability: capability,
      launchCWD: context.effectiveCWD,
      forwardingArgv: options.forwardingArgv,
      warning: nil
    )
  }

  private static func degraded(
    plan: AgentProfileLaunchPlan,
    capability: AgentSignalHookCapability,
    launchCWD: URL,
    message: String
  ) -> AgentManagedHookPreparation {
    AgentManagedHookPreparation(
      preparedInvocation: nil,
      capability: capability,
      launchCWD: launchCWD,
      forwardingArgv: nil,
      warning: LifecycleCommandWarning(
        code: .managedHookDegraded,
        runtime: plan.runtime.rawValue,
        message: message
      )
    )
  }
}
