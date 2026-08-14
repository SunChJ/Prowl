import Testing

@testable import supacode

struct ClaudeScreenProfileTests {
  @Test func ruleIDsAreUniqueAndRuntimePrefixed() {
    let ruleIDs = ClaudeScreenProfile.RuleID.all

    #expect(Set(ruleIDs).count == ruleIDs.count)
    #expect(ruleIDs.allSatisfy { $0.rawValue.hasPrefix("claude.") })
  }

  @Test func capturedFixturesHaveStableReasonsIncludingViewerFix() throws {
    let expectedReasons: [String: AgentScreenDetectionReason] = [
      "claude/2.1.223/blocked/command-permission.txt": .matched(
        ClaudeScreenProfile.RuleID.blockedPrompt
      ),
      "claude/2.1.223/blocked/workspace-trust.txt": .matched(
        ClaudeScreenProfile.RuleID.blockedPrompt
      ),
      "claude/2.1.223/idle/composer.txt": .matched(ClaudeScreenProfile.RuleID.idleComposer),
      "claude/2.1.223/idle/quoted-permission.txt": .matched(
        ClaudeScreenProfile.RuleID.idleComposer
      ),
      "claude/2.1.223/unknown/676-history-search-viewer.txt": .matched(
        ClaudeScreenProfile.RuleID.viewer
      ),
      "claude/2.1.223/working/backgrounded-subagent.txt": .matched(
        ClaudeScreenProfile.RuleID.spinner
      ),
      "claude/2.1.223/working/foreground-spinner.txt": .matched(
        ClaudeScreenProfile.RuleID.spinner
      ),
      "claude/2.1.223/working/subagent-active.txt": .matched(
        ClaudeScreenProfile.RuleID.spinner
      ),
      "claude/2.1.224/working/676-background-agent-wait.txt": .matched(
        ClaudeScreenProfile.RuleID.backgroundWork
      ),
      "claude/2.1.224/working/676-compound-elapsed-status.txt": .matched(
        ClaudeScreenProfile.RuleID.elapsedStatus
      ),
      "claude/2.1.226/working/676-wrapped-background-agent-wait.txt": .matched(
        ClaudeScreenProfile.RuleID.backgroundWork
      ),
    ]
    let fixtures = try AgentScreenFixtureCorpus.load().filter { $0.agent == .claude }

    #expect(fixtures.count == expectedReasons.count)
    for fixture in fixtures {
      let detection = DetectedAgent.claude.detectScreen(in: fixture.text)
      #expect(detection.state == fixture.expectedState)
      #expect(detection.reason == expectedReasons[fixture.relativePath])
    }
  }

  @Test func elapsedAndBackgroundWorkHaveDistinctReasons() {
    let elapsed = ClaudeScreenProfile.detect(
      in: AgentScreenSnapshot(
        text: """
            ● Forging… (10s · thinking with high effort)
            ─────────
            ❯
            ─────────
          """
      )
    )
    #expect(elapsed.state == .working)
    #expect(elapsed.reason == .matched(ClaudeScreenProfile.RuleID.elapsedStatus))

    let background = ClaudeScreenProfile.detect(
      in: AgentScreenSnapshot(
        text: """
            Task complete.
            ─────────
            ❯
            ─────────
            ◯ scout  Map idle detection  3/5 agents done · 7m 29s
          """
      )
    )
    #expect(background.state == .working)
    #expect(background.reason == .matched(ClaudeScreenProfile.RuleID.backgroundWork))
  }

  @Test func blockerOutranksRetainedSpinner() {
    let detection = ClaudeScreenProfile.detect(
      in: AgentScreenSnapshot(
        text: """
            ✻ Tempering… (12s · esc to interrupt)
            Do you want to proceed?
            ❯ 1. Yes
              2. No
            Esc to cancel · Tab to amend
          """
      )
    )

    #expect(detection.state == .blocked)
    #expect(detection.reason == .matched(ClaudeScreenProfile.RuleID.blockedPrompt))
  }

  @Test func blockerTextPreservesClaudeQuestionChoicesAndKeyboardHints() throws {
    let fixture = try AgentScreenFixtureCorpus.load()
      .first { $0.relativePath == "claude/2.1.223/blocked/command-permission.txt" }
    let text = try #require(fixture).text

    let blocker = ClaudeScreenProfile.blockerText(in: AgentScreenSnapshot(text: text))

    #expect(blocker?.contains("Do you want to proceed?") == true)
    #expect(blocker?.contains("❯ 1. Yes") == true)
    #expect(blocker?.contains("3. No") == true)
    #expect(blocker?.contains("Esc to cancel · Tab to amend · ctrl+e to explain") == true)
  }

  @Test func spinnerAboveLongTodoListStaysWorking() {
    // Regression: the shared recent-line tail is measured from the bottom of the
    // screen, so a long todo list plus the composer and a multi-line status line
    // pushed the live spinner row out of the detector window and a working agent
    // was reported idle (via the idle-composer rule).
    var lines = [
      "✻ Implementing hybridTopK… (5m 5s · ↓ 21.1k tokens)",
      "  ⎿ \u{00A0}✔ Write failing tests for hybridTopK and per-scope pickCandidates",
    ]
    for index in 2...16 {
      lines.append("     ◻ Todo item number \(index) still pending")
    }
    lines.append(
      contentsOf: [
        "──────────────────────────────────────────",
        "❯ ",
        "──────────────────────────────────────────",
        "  [Fable 5 | Enterprise] ██░░░░░░░░ 16% | will git:(master*)",
        "  ███░░░░░░░ 34% (4h 3m / 5h) | ███░░░░░░░ 29% (4d 19h / 7d)",
        "  ✓ Bash ×7 | ✓ Read ×6 | ✓ Edit ×5",
        "  ▸ Implement hybridTopK in similarity.ts (2/16)",
        "  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents",
      ]
    )

    let detection = DetectedAgent.claude.detectScreen(in: lines.joined(separator: "\n"))

    #expect(detection.state == .working)
    #expect(detection.reason == .matched(ClaudeScreenProfile.RuleID.spinner))
  }

  @Test func unstructuredScreenUsesExplicitFallback() {
    let detection = ClaudeScreenProfile.detect(
      in: AgentScreenSnapshot(text: "screen without live Claude chrome")
    )

    #expect(detection.state == .idle)
    #expect(detection.reason == .noRuleMatched)
  }
}
