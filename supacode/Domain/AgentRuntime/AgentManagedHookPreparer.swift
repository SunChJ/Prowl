import Foundation

/// Droid's `--settings` takes a path only, so its merged object must be written to an
/// owner-only file before the argv can name it. The merge is pure; the write belongs to the
/// main-actor store, so the preparer hands this back and the manager completes it.
nonisolated struct PendingManagedHookSettingsFile: Equatable, Sendable {
  let data: Data
  let invocation: AgentInvocation
  let promptArgumentIndex: Int?
}

nonisolated struct AgentManagedHookPreparation: Equatable, Sendable {
  let preparedInvocation: AgentHookPreparedInvocation?
  let capability: AgentSignalHookCapability?
  let launchCWD: URL
  let forwardingArgv: [String]?
  var pendingSettingsFile: PendingManagedHookSettingsFile?
  let warning: LifecycleCommandWarning?
}

nonisolated enum AgentManagedHookPreparer {
  private struct CodexPreparationOptions {
    let promptIndex: Int?
    let shellEnvironment: CodexShellLaunchEnvironment?
    let configReadProcess: CodexConfigReadProcess
  }

  private struct CodexRenderingOptions {
    let promptIndex: Int?
    let forwardingArgv: [String]?
  }

  private struct SettingsRuntimeOptions {
    let promptIndex: Int?
    let droidSettingsEnvironmentResolver: DroidSettingsEnvironmentResolver?
    let settingsReadFile: (@Sendable (URL, Int) -> ClaudeSettingsReadResult)?
  }

  typealias DroidSettingsEnvironmentResolver =
    @Sendable (URL, String?) async -> DroidSettingsEnvironmentProbe.Resolution

  static func prepare(
    plan: AgentProfileLaunchPlan,
    inheritedCWD: URL,
    resources: AgentHookResources?,
    codexShellEnvironment: CodexShellLaunchEnvironment? = nil,
    codexConfigReadProcess: CodexConfigReadProcess = CodexConfigReadProcess(),
    droidSettingsEnvironmentResolver: DroidSettingsEnvironmentResolver? = nil,
    settingsReadFile: (@Sendable (URL, Int) -> ClaudeSettingsReadResult)? = nil
  ) async -> AgentManagedHookPreparation {
    guard
      let capability = AgentRuntimeAdapterRegistry.profileAdapter(for: plan.runtime)?.signalHooks
    else {
      return AgentManagedHookPreparation(
        preparedInvocation: nil,
        capability: nil,
        launchCWD: inheritedCWD,
        forwardingArgv: nil,
        pendingSettingsFile: nil,
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
          shellEnvironment: codexShellEnvironment,
          configReadProcess: codexConfigReadProcess
        )
      )
    case .copilot:
      return prepareCopilot(
        plan: plan,
        capability: capability,
        inheritedCWD: inheritedCWD,
        resources: resources,
        promptIndex: promptIndex
      )
    case .droid, .qoder:
      return await prepareSettingsRuntime(
        plan: plan,
        capability: capability,
        inheritedCWD: inheritedCWD,
        resources: resources,
        options: SettingsRuntimeOptions(
          promptIndex: promptIndex,
          droidSettingsEnvironmentResolver: droidSettingsEnvironmentResolver,
          settingsReadFile: settingsReadFile
        )
      )
    }
  }

  /// Copilot needs no merge: every `--plugin-dir` loads additively, so Prowl appends its
  /// bundled plugin and leaves the user's plugins and hook files untouched.
  private static func prepareCopilot(
    plan: AgentProfileLaunchPlan,
    capability: AgentSignalHookCapability,
    inheritedCWD: URL,
    resources: AgentHookResources,
    promptIndex: Int?
  ) -> AgentManagedHookPreparation {
    guard let pluginPath = resources.copilotPluginPath,
      pluginPath.hasPrefix("/"),
      FileManager.default.fileExists(atPath: pluginPath + "/hooks.json")
    else {
      return degraded(
        plan: plan,
        capability: capability,
        launchCWD: inheritedCWD,
        message: "The bundled Copilot hook plugin is unavailable."
      )
    }
    guard
      let launchCWD = ManagedHookWorkingDirectory.effective(
        inherited: inheritedCWD,
        scan: ManagedHookWorkingDirectory.scan(
          arguments: plan.invocation.arguments,
          optionNames: ["-C"],
          precedence: .lastWins,
          promptArgumentIndex: promptIndex
        )
      )
    else {
      return degraded(
        plan: plan,
        capability: capability,
        launchCWD: inheritedCWD,
        message: "The Copilot working directory option could not be resolved."
      )
    }
    return AgentManagedHookPreparation(
      preparedInvocation: CopilotHookPluginRenderer.prepare(
        invocation: plan.invocation,
        pluginDirectory: URL(filePath: pluginPath, directoryHint: .isDirectory),
        promptArgumentIndex: promptIndex
      ),
      capability: capability,
      launchCWD: launchCWD,
      forwardingArgv: nil,
      pendingSettingsFile: nil,
      warning: nil
    )
  }

  private struct DroidEnvironmentSettings {
    var path: String?
    var resolutionFailed = false
  }

  /// Resolve the effective `FACTORY_RUNTIME_SETTINGS_PATH` for Droid, whose managed `--settings`
  /// flag outranks it: a Profile override wins outright; otherwise the login shell is probed so a
  /// value exported in an rc file is still honored. The probe is skipped when a `--settings` flag
  /// is present (it wins anyway) or an override already answers the question. A probe that cannot
  /// run leaves the presence unknown, so the caller degrades rather than override.
  private static func resolveDroidEnvironmentSettings(
    plan: AgentProfileLaunchPlan,
    inheritedCWD: URL,
    promptIndex: Int?,
    resolver: DroidSettingsEnvironmentResolver?
  ) async -> DroidEnvironmentSettings {
    if let override = plan.profileEnvironmentOverrides[DroidSettingsEnvironmentProbe.variableName] {
      return DroidEnvironmentSettings(path: override)
    }
    let flagPresent =
      ManagedHookSettings.scanSettings(
        arguments: plan.invocation.arguments,
        optionName: ManagedHookSettings.settingsOptionName,
        precedence: .lastWins,
        promptArgumentIndex: promptIndex
      ) != .none
    guard !flagPresent, let resolver else { return DroidEnvironmentSettings() }
    switch await resolver(inheritedCWD, plan.profileEnvironmentOverrides["PATH"]) {
    case .value(let path): return DroidEnvironmentSettings(path: path)
    case .failed: return DroidEnvironmentSettings(resolutionFailed: true)
    }
  }

  /// Droid and Qoder both configure hooks through a settings object, but with opposite
  /// precedence, and only Qoder accepts it inline. Droid's merged object therefore has to be
  /// written to an owner-only file, which may hold user secrets.
  private static func prepareSettingsRuntime(
    plan: AgentProfileLaunchPlan,
    capability: AgentSignalHookCapability,
    inheritedCWD: URL,
    resources: AgentHookResources,
    options: SettingsRuntimeOptions
  ) async -> AgentManagedHookPreparation {
    let hookCommands = shellHookCommands(capability: capability, resources: resources)
    let invocation = plan.invocation
    let runtime = capability.runtime
    let promptIndex = options.promptIndex
    // The hooks report the directory the runtime changes into; the settings path is still
    // relative to where it was launched (both measured on Droid 0.203 and Qoder 1.1.29).
    let workingDirectoryScan = ManagedHookWorkingDirectory.scan(
      arguments: invocation.arguments,
      optionNames: runtime == .qoder ? ["-w", "--cwd"] : ["--cwd"],
      precedence: runtime == .qoder ? .firstWins : .lastWins,
      promptArgumentIndex: promptIndex
    )
    guard
      let launchCWD = ManagedHookWorkingDirectory.effective(
        inherited: inheritedCWD,
        scan: workingDirectoryScan
      )
    else {
      return degraded(
        plan: plan,
        capability: capability,
        launchCWD: inheritedCWD,
        message: "The \(runtime.rawValue) working directory option could not be resolved."
      )
    }
    let environment =
      runtime == .droid
      ? await resolveDroidEnvironmentSettings(
        plan: plan, inheritedCWD: inheritedCWD, promptIndex: promptIndex,
        resolver: options.droidSettingsEnvironmentResolver)
      : DroidEnvironmentSettings()
    let settingsReadFile = options.settingsReadFile

    return await Task.detached(priority: .userInitiated) {
      let readFile: (URL, Int) -> ClaudeSettingsReadResult =
        settingsReadFile ?? { ClaudeSettingsStableReader.read($0, maximumBytes: $1) }
      switch runtime {
      case .qoder:
        let outcome = QoderHookSettingsPreparer.prepare(
          invocation: invocation,
          launchDirectory: inheritedCWD,
          promptArgumentIndex: promptIndex,
          hookCommands: hookCommands,
          readFile: readFile
        )
        return AgentManagedHookPreparation(
          preparedInvocation: outcome.prepared,
          capability: capability,
          launchCWD: launchCWD,
          forwardingArgv: nil,
          pendingSettingsFile: nil,
          warning: outcome.warning
        )
      case .droid:
        let merged = DroidHookSettingsPreparer.mergedSettings(
          invocation: invocation,
          launchDirectory: inheritedCWD,
          promptArgumentIndex: promptIndex,
          hookCommands: hookCommands,
          // `FACTORY_RUNTIME_SETTINGS_PATH` (Profile override or shell-resolved) is a settings
          // source the managed `--settings` flag would otherwise override; merge it as the base.
          environmentSettingsPath: environment.path,
          environmentResolutionFailed: environment.resolutionFailed,
          readFile: readFile
        )
        return AgentManagedHookPreparation(
          preparedInvocation: nil,
          capability: capability,
          launchCWD: launchCWD,
          forwardingArgv: nil,
          pendingSettingsFile: merged.data.map {
            PendingManagedHookSettingsFile(
              data: $0,
              invocation: invocation,
              promptArgumentIndex: promptIndex
            )
          },
          warning: merged.warning
        )
      case .claude, .codex, .copilot:
        return AgentManagedHookPreparation(
          preparedInvocation: nil,
          capability: capability,
          launchCWD: launchCWD,
          forwardingArgv: nil,
          pendingSettingsFile: nil,
          warning: LifecycleCommandWarning(
            code: .managedHookDegraded,
            runtime: runtime.rawValue,
            message: "Managed hooks could not be prepared for this runtime."
          )
        )
      }
    }.value
  }

  /// One shell-quoted hook command per declared native event.
  private static func shellHookCommands(
    capability: AgentSignalHookCapability,
    resources: AgentHookResources
  ) -> [String: String] {
    var commands: [String: String] = [:]
    for event in capability.nativeEvents.keys.sorted() {
      commands[event] = [
        AgentInvocation.shellQuote(resources.bundledCLIPath),
        "agents",
        "_hook",
        capability.runtime.rawValue,
        event,
      ].joined(separator: " ")
    }
    return commands
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
        readFile: { ClaudeSettingsStableReader.read($0, maximumBytes: $1) }
      )
    }.value
    return AgentManagedHookPreparation(
      preparedInvocation: outcome.prepared,
      capability: capability,
      launchCWD: inheritedCWD,
      forwardingArgv: nil,
      pendingSettingsFile: nil,
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
    guard let shellEnvironment = options.shellEnvironment else {
      return degraded(
        plan: plan,
        capability: capability,
        launchCWD: inheritedCWD,
        message: "The effective Codex shell environment could not be resolved."
      )
    }
    let invocation = AgentInvocation(
      executable: shellEnvironment.executableURL.path(percentEncoded: false),
      arguments: plan.invocation.arguments
    )
    let context: CodexLaunchContext
    do {
      context = try CodexLaunchContext.capture(
        invocation: invocation,
        inheritedCWD: inheritedCWD,
        dedicatedHome: plan.dedicatedHome,
        environment: shellEnvironment.processEnvironment,
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
      query: options.configReadProcess.usingExecutable(shellEnvironment.executableURL).query
    )
    switch await resolver.resolve(context) {
    case .absent:
      return preparedCodex(
        invocation: invocation,
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
        invocation: invocation,
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
    invocation: AgentInvocation,
    capability: AgentSignalHookCapability,
    context: CodexLaunchContext,
    resources: AgentHookResources,
    options: CodexRenderingOptions
  ) -> AgentManagedHookPreparation {
    AgentManagedHookPreparation(
      preparedInvocation: CodexManagedNotifyRenderer.prepare(
        invocation: invocation,
        bundledCLIPath: resources.bundledCLIPath,
        promptArgumentIndex: options.promptIndex
      ),
      capability: capability,
      launchCWD: context.effectiveCWD,
      forwardingArgv: options.forwardingArgv,
      pendingSettingsFile: nil,
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
      pendingSettingsFile: nil,
      warning: LifecycleCommandWarning(
        code: .managedHookDegraded,
        runtime: plan.runtime.rawValue,
        message: message
      )
    )
  }
}
