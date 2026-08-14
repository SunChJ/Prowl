struct AgentScreenSnapshot: Equatable, Sendable {
  let text: String
  let lines: [String]

  /// `text` must be the exact detector input for the agent consuming this
  /// snapshot — produce it with `DetectedAgent.detectionScreenText(from:)` so
  /// state detection and blocker extraction always read the same screen.
  nonisolated init(text: String) {
    self.text = text
    self.lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }
}
