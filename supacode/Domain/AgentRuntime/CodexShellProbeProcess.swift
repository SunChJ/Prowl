import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

nonisolated enum CodexShellProbeProcessError: Error, Equatable, Sendable {
  case cancelled
  case outputTooLarge
  case processFailed
  case timeout
}

nonisolated struct CodexShellProbeProcess: Sendable {
  private struct RunOptions {
    let timeout: TimeInterval
    let maximumOutputBytes: Int
    let shellOverride: URL?
  }

  private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func install(_ process: Process) {
      lock.withLock { self.process = process }
    }

    func terminate() {
      lock.withLock {
        if process?.isRunning == true { process?.terminate() }
      }
    }
  }

  let timeout: TimeInterval
  let maximumOutputBytes: Int
  let shellOverride: URL?

  init(
    timeout: TimeInterval = 1,
    maximumOutputBytes: Int = 16 * 1_024,
    shellOverride: URL? = nil
  ) {
    self.timeout = max(0.05, timeout)
    self.maximumOutputBytes = max(1, maximumOutputBytes)
    self.shellOverride = shellOverride
  }

  func run(cwd: URL, script: String) async throws -> ShellOutput {
    let processBox = ProcessBox()
    let task = Task.detached(priority: .userInitiated) {
      try Self.runSynchronously(
        cwd: cwd,
        script: script,
        options: RunOptions(
          timeout: timeout,
          maximumOutputBytes: maximumOutputBytes,
          shellOverride: shellOverride
        ),
        processBox: processBox
      )
    }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
      processBox.terminate()
    }
  }

  private static func runSynchronously(
    cwd: URL,
    script: String,
    options: RunOptions,
    processBox: ProcessBox
  ) throws -> ShellOutput {
    let process = Process()
    if let shellOverride = options.shellOverride {
      process.executableURL = shellOverride
      process.arguments = []
    } else {
      let invocation = ShellClient.loginShellInvocation(userShell: defaultShellURL())
      process.executableURL = invocation.shell
      process.arguments = [
        "-l", "-c", invocation.command, "--",
        "/bin/sh", "-c", script,
      ]
    }
    process.currentDirectoryURL = cwd
    process.standardInput = FileHandle.nullDevice
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    processBox.install(process)
    try process.run()
    let descriptors = [
      output.fileHandleForReading.fileDescriptor,
      errors.fileHandleForReading.fileDescriptor,
    ]
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(options.timeout * 1_000_000_000)
    var stdout = Data()
    var stderr = Data()
    defer {
      stop(process)
      try? output.fileHandleForReading.close()
      try? errors.fileHandleForReading.close()
    }

    while process.isRunning || hasReadableData(descriptors) {
      if Task.isCancelled { throw CodexShellProbeProcessError.cancelled }
      guard DispatchTime.now().uptimeNanoseconds < deadline else {
        throw CodexShellProbeProcessError.timeout
      }
      var pollDescriptors = descriptors.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
      let status = poll(&pollDescriptors, nfds_t(pollDescriptors.count), 25)
      if status < 0 {
        if errno == EINTR { continue }
        throw CodexShellProbeProcessError.processFailed
      }
      for index in pollDescriptors.indices where pollDescriptors[index].revents & Int16(POLLIN) != 0 {
        var chunk = [UInt8](repeating: 0, count: 4 * 1_024)
        let count = chunk.withUnsafeMutableBytes {
          Darwin.read(descriptors[index], $0.baseAddress, $0.count)
        }
        if count > 0 {
          if index == 0 {
            stdout.append(contentsOf: chunk.prefix(count))
          } else {
            stderr.append(contentsOf: chunk.prefix(count))
          }
          guard stdout.count + stderr.count <= options.maximumOutputBytes else {
            throw CodexShellProbeProcessError.outputTooLarge
          }
        }
      }
    }
    guard process.terminationStatus == 0 else { throw CodexShellProbeProcessError.processFailed }
    guard let stdoutText = String(data: stdout, encoding: .utf8),
      let stderrText = String(data: stderr, encoding: .utf8)
    else { throw CodexShellProbeProcessError.processFailed }
    return ShellOutput(stdout: stdoutText, stderr: stderrText, exitCode: process.terminationStatus)
  }

  private static func hasReadableData(_ descriptors: [Int32]) -> Bool {
    var values = descriptors.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
    return poll(&values, nfds_t(values.count), 0) > 0
  }

  private static func stop(_ process: Process) {
    if process.isRunning { process.terminate() }
    for _ in 0..<100 where process.isRunning { usleep(1_000) }
    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    process.waitUntilExit()
  }

  private static func defaultShellURL() -> URL {
    if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
      return URL(filePath: shell, directoryHint: .notDirectory)
    }
    return URL(filePath: "/bin/zsh", directoryHint: .notDirectory)
  }
}
