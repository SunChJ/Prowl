struct AgentScreenSnapshot: Equatable, Sendable {
  let text: String
  let lines: [String]

  nonisolated init(canonicalText: String) {
    self.text = canonicalText
    self.lines = canonicalText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }
}
