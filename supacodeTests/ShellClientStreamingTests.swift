import Foundation
import Testing

@testable import supacode

nonisolated final class LoginStreamCallRecorder: @unchecked Sendable {
  struct Snapshot {
    let executableURL: URL?
    let arguments: [String]
    let currentDirectoryURL: URL?
    let log: Bool
  }

  private let lock = NSLock()
  private var executableURLValue: URL?
  private var argumentsValue: [String] = []
  private var currentDirectoryURLValue: URL?
  private var logValue = true

  func record(
    executableURL: URL,
    arguments: [String],
    currentDirectoryURL: URL?,
    log: Bool
  ) {
    lock.lock()
    executableURLValue = executableURL
    argumentsValue = arguments
    currentDirectoryURLValue = currentDirectoryURL
    logValue = log
    lock.unlock()
  }

  func snapshot() -> Snapshot {
    lock.lock()
    let value = Snapshot(
      executableURL: executableURLValue,
      arguments: argumentsValue,
      currentDirectoryURL: currentDirectoryURLValue,
      log: logValue
    )
    lock.unlock()
    return value
  }
}

nonisolated final class TerminationCallRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var countValue = 0

  func record() {
    lock.lock()
    countValue += 1
    lock.unlock()
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return countValue
  }
}

struct ShellClientStreamingTests {

  @Test func cancellationTerminatesOnceBeforeOrAfterProcessRegistration() {
    let beforeRegistration = ProcessCancellation()
    let beforeRecorder = TerminationCallRecorder()
    beforeRegistration.cancel()
    beforeRegistration.installTermination { beforeRecorder.record() }
    beforeRegistration.cancel()
    #expect(beforeRecorder.count == 1)

    let afterRegistration = ProcessCancellation()
    let afterRecorder = TerminationCallRecorder()
    afterRegistration.installTermination { afterRecorder.record() }
    afterRegistration.cancel()
    afterRegistration.cancel()
    #expect(afterRecorder.count == 1)
  }
  @Test func runStreamYieldsStdoutAndStderrLines() async throws {
    let shell = ShellClient.liveValue
    let commandURL = URL(fileURLWithPath: "/bin/sh")
    let stream = shell.runStream(
      commandURL,
      ["-c", "printf 'out-1\\n'; printf 'err-1\\n' 1>&2; printf 'out-2\\n'"],
      nil
    )
    var stdoutLines: [String] = []
    var stderrLines: [String] = []
    var finishedOutput: ShellOutput?
    for try await event in stream {
      switch event {
      case .line(let line):
        switch line.source {
        case .stdout:
          stdoutLines.append(line.text)
        case .stderr:
          stderrLines.append(line.text)
        }
      case .finished(let output):
        finishedOutput = output
      }
    }

    #expect(stdoutLines == ["out-1", "out-2"])
    #expect(stderrLines == ["err-1"])
    #expect(finishedOutput == ShellOutput(stdout: "out-1\nout-2", stderr: "err-1", exitCode: 0))
  }

  @Test func runStreamYieldsLinesBeforeProcessFinishes() async throws {
    let shell = ShellClient.liveValue
    let commandURL = URL(fileURLWithPath: "/bin/sh")
    let stream = shell.runStream(
      commandURL,
      ["-c", "printf 'first\\n'; sleep 0.4; printf 'last\\n'"],
      nil
    )
    var sawFirstLine = false
    var finishedAfterFirstLine = false
    for try await event in stream {
      switch event {
      case .line(let line):
        if line.source == .stdout, line.text == "first" {
          sawFirstLine = true
        }
      case .finished:
        finishedAfterFirstLine = sawFirstLine
      }
    }

    #expect(sawFirstLine)
    #expect(finishedAfterFirstLine)
  }

  @Test func runStreamThrowsShellClientErrorOnNonZeroExit() async throws {
    let shell = ShellClient.liveValue
    let commandURL = URL(fileURLWithPath: "/bin/sh")
    let stream = shell.runStream(
      commandURL,
      ["-c", "printf 'out\\n'; printf 'err\\n' 1>&2; exit 7"],
      nil
    )
    var streamedLines: [ShellStreamLine] = []
    do {
      for try await event in stream {
        if case .line(let line) = event {
          streamedLines.append(line)
        }
      }
      Issue.record("Expected stream to throw for non-zero exit")
    } catch let shellError as ShellClientError {
      #expect(shellError.exitCode == 7)
      #expect(shellError.stdout == "out")
      #expect(shellError.stderr == "err")
      #expect(shellError.command.contains("/bin/sh"))
    }

    #expect(streamedLines.contains(where: { $0.source == .stdout && $0.text == "out" }))
    #expect(streamedLines.contains(where: { $0.source == .stderr && $0.text == "err" }))
  }

  @Test func cancellingRunStreamConsumerTerminatesProcessQuickly() async throws {
    let shell = ShellClient.liveValue
    let commandURL = URL(fileURLWithPath: "/bin/sleep")
    let stream = shell.runStream(commandURL, ["30"], nil)

    let consumer = Task {
      var lines: [ShellStreamLine] = []
      do {
        for try await event in stream {
          if case .line(let line) = event {
            lines.append(line)
          }
        }
      } catch {
        // CancellationError or ShellClientError after SIGTERM both indicate
        // the cancellation pathway is connected.
      }
      return lines
    }

    // The coordinator unit test covers cancellation before process registration.
    // Yield once to exercise the usual already-running stream path without a timing sleep.
    await Task.yield()

    let start = ContinuousClock.now
    consumer.cancel()
    _ = await consumer.value
    let elapsed = ContinuousClock.now - start

    // The assertion distinguishes "cancellation worked" from "waited out the
    // process's 30-second natural exit". Loaded CI runners have pushed the
    // full cancel → SIGTERM → pipe-EOF → finish chain past 10s while suite
    // tests run in parallel, so the budget leaves headroom without blurring
    // that distinction.
    #expect(
      elapsed < .seconds(20),
      "consumer cancellation must not wait for the process's 30-second natural exit; took \(elapsed)"
    )
  }

  @Test func runReturnsQuicklyWhenCallingTaskIsCancelled() async {
    let shell = ShellClient.liveValue
    let commandURL = URL(fileURLWithPath: "/bin/sleep")

    let runTask = Task {
      try await shell.run(commandURL, ["30"], nil)
    }

    // Cancellation before process registration is covered deterministically above.
    await Task.yield()

    let start = ContinuousClock.now
    runTask.cancel()
    _ = await runTask.result
    let elapsed = ContinuousClock.now - start

    // Same budget rationale as cancellingRunStreamConsumerTerminatesProcessQuickly.
    #expect(
      elapsed < .seconds(20),
      "run() cancellation must not wait for the process's 30-second natural exit; took \(elapsed)"
    )
  }

  @Test func runStreamSucceedsForShortLivedProcessAfterCancellationFixes() async throws {
    // Regression guard: terminationHandler / isRunning race in waitForExit
    // must not deadlock or double-resume on fast-exiting processes.
    let shell = ShellClient.liveValue
    let commandURL = URL(fileURLWithPath: "/bin/sh")
    let stream = shell.runStream(commandURL, ["-c", "true"], nil)
    var finished: ShellOutput?
    for try await event in stream {
      if case .finished(let output) = event {
        finished = output
      }
    }
    #expect(finished?.exitCode == 0)
  }

  @Test func runLoginStreamForwardsParameters() async throws {
    let recorder = LoginStreamCallRecorder()
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runStream: { _, _, _ in
        AsyncThrowingStream { continuation in
          continuation.yield(.finished(ShellOutput(stdout: "", stderr: "", exitCode: 0)))
          continuation.finish()
        }
      },
      runLoginStreamImpl: { executableURL, arguments, currentDirectoryURL, log in
        recorder.record(
          executableURL: executableURL,
          arguments: arguments,
          currentDirectoryURL: currentDirectoryURL,
          log: log
        )
        return AsyncThrowingStream { continuation in
          continuation.yield(.finished(ShellOutput(stdout: "", stderr: "", exitCode: 0)))
          continuation.finish()
        }
      }
    )
    let executableURL = URL(fileURLWithPath: "/usr/bin/env")
    let currentDirectoryURL = URL(fileURLWithPath: "/tmp")
    let stream = shell.runLoginStream(
      executableURL,
      ["echo", "hello"],
      currentDirectoryURL,
      log: false
    )
    for try await _ in stream {}

    let snapshot = recorder.snapshot()
    #expect(snapshot.executableURL == executableURL)
    #expect(snapshot.arguments == ["echo", "hello"])
    #expect(snapshot.currentDirectoryURL == currentDirectoryURL)
    #expect(snapshot.log == false)
  }
}
