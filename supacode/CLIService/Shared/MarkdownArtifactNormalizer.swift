// ProwlShared/MarkdownArtifactNormalizer.swift
// Strips the chat wrapping agents put around a markdown document (an opening fence, preamble
// before the first heading, the closing fence and any trailer after it). Shared by the handoff
// briefing validation and the workflow delivery validation so both accept the same replies.

import Foundation

nonisolated public enum MarkdownArtifactNormalizer {
  /// The document without chat wrapping, trimmed; empty when nothing remains. Prowl never
  /// authors prose here: only wrapping is removed, the document body is kept verbatim.
  public static func normalized(_ text: String) -> String {
    var text = droppingPreambleBeforeOpeningFence(text.trimmingCharacters(in: .whitespacesAndNewlines))
    let openingFence = fenceMarker(of: text)
    text = droppingOpeningFence(text)
    text = droppingPreamble(text)
    text = droppingClosingFence(text, openingFence: openingFence)
    return text
  }

  /// Heading lines (`#…`) outside fenced code blocks, trimmed. A heading quoted inside a
  /// fence is code, not structure, so it never satisfies a required section.
  public static func headings(outsideFences text: String) -> [String] {
    var headings: [String] = []
    var open: String?
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if let marker = open {
        if line.hasPrefix(marker) { open = nil }
        continue
      }
      if let marker = fenceMarker(of: line) {
        open = marker
        continue
      }
      if line.hasPrefix("#") {
        headings.append(line)
      }
    }
    return headings
  }

  /// Whether every required section is present as a heading line outside fences; a heading
  /// may carry trailing text after a space (`## Findings (2)`).
  public static func hasSections(_ sections: [String], in text: String) -> Bool {
    let headings = headings(outsideFences: text)
    return sections.allSatisfy { section in
      let wanted = section.trimmingCharacters(in: .whitespaces)
      return headings.contains { $0 == wanted || $0.hasPrefix(wanted + " ") }
    }
  }

  /// The fence marker (` ``` ` or `~~~`) a line opens with, or nil.
  private static func fenceMarker(of text: String) -> String? {
    if text.hasPrefix("```") { return "```" }
    if text.hasPrefix("~~~") { return "~~~" }
    return nil
  }

  /// A reply may put chatter *before* the fence that wraps the document ("Sure, here it is:"
  /// then "```markdown"). When a fence line precedes the first heading, everything up to that
  /// fence is preamble and the fence becomes the opening fence.
  private static func droppingPreambleBeforeOpeningFence(_ text: String) -> String {
    guard fenceMarker(of: text) == nil, !text.hasPrefix("#") else { return text }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard let heading = lines.firstIndex(where: { $0.hasPrefix("# ") || $0.hasPrefix("## ") }),
      let fence = lines.firstIndex(where: { fenceMarker(of: String($0)) != nil }), fence < heading
    else { return text }
    return lines[fence...].joined(separator: "\n")
  }

  /// Unwraps the opening line of a markdown code fence ("```markdown" / "~~~markdown").
  private static func droppingOpeningFence(_ text: String) -> String {
    guard fenceMarker(of: text) != nil else { return text }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Drops chat preamble ahead of the document ("Sure, here's the file: …").
  private static func droppingPreamble(_ text: String) -> String {
    guard !text.hasPrefix("#") else { return text }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard let start = lines.firstIndex(where: { $0.hasPrefix("# ") || $0.hasPrefix("## ") }) else {
      return text
    }
    return lines[start...].joined(separator: "\n")
  }

  /// Drops a trailing fence line left over after preamble removal. When the reply opened
  /// with a fence, the *last* line made of that marker is the wrapper's closer, so any chatter
  /// after it is also discarded — embedded code blocks inside the document close in pairs
  /// before it. Without an opening fence only an exact trailing fence line is removed, so a
  /// fence inside a document body is never a cut point.
  private static func droppingClosingFence(_ text: String, openingFence: String?) -> String {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    let closers = openingFence.map { [$0] } ?? ["```", "~~~"]
    guard let lastFence = lines.lastIndex(where: { closers.contains($0.trimmingCharacters(in: .whitespaces)) })
    else { return text }
    if lastFence == lines.indices.last {
      lines.removeLast()
      return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard openingFence != nil else { return text }
    return lines[..<lastFence].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
