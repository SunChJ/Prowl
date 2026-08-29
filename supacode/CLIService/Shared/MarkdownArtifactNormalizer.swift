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
    let openingFence = fence(opening: text.firstLine)
    text = droppingOpeningFence(text)
    text = droppingPreamble(text)
    text = droppingClosingFence(text, openingFence: openingFence)
    return text
  }

  /// Heading lines (`#…`) outside fenced code blocks, trimmed. A heading quoted inside a
  /// fence is code, not structure, so it never satisfies a required section.
  public static func headings(outsideFences text: String) -> [String] {
    var headings: [String] = []
    var open: Fence?
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if let fence = open {
        if closes(line, fence) { open = nil }
        continue
      }
      if let fence = fence(opening: line) {
        open = fence
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

  /// A fenced-code delimiter: the fence character and the length of its run (CommonMark: at
  /// least three backticks or tildes; the closer uses the same character, at least as long,
  /// and carries nothing but whitespace after the run).
  private struct Fence: Equatable {
    let character: Character
    let length: Int
  }

  private static func fence(opening line: String) -> Fence? {
    guard let first = line.first, first == "`" || first == "~" else { return nil }
    let length = line.prefix { $0 == first }.count
    guard length >= 3 else { return nil }
    return Fence(character: first, length: length)
  }

  private static func closes(_ line: String, _ fence: Fence) -> Bool {
    let run = line.prefix { $0 == fence.character }
    guard run.count >= fence.length else { return false }
    return line.dropFirst(run.count).allSatisfy(\.isWhitespace)
  }

  /// A line that is nothing but a fence run (any length ≥ 3, backticks or tildes).
  private static func isBareFence(_ line: String) -> Bool {
    guard let fence = fence(opening: line) else { return false }
    return closes(line, fence)
  }

  /// A reply may put chatter *before* the fence that wraps the document ("Sure, here it is:"
  /// then "```markdown"). When a fence line precedes the first heading, everything up to that
  /// fence is preamble and the fence becomes the opening fence.
  private static func droppingPreambleBeforeOpeningFence(_ text: String) -> String {
    guard fence(opening: text.firstLine) == nil, !text.hasPrefix("#") else { return text }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard let heading = lines.firstIndex(where: { $0.hasPrefix("# ") || $0.hasPrefix("## ") }),
      let fenceIndex = lines.firstIndex(where: { fence(opening: String($0)) != nil }), fenceIndex < heading
    else { return text }
    return lines[fenceIndex...].joined(separator: "\n")
  }

  /// Unwraps the opening line of a markdown code fence ("```markdown" / "~~~markdown").
  private static func droppingOpeningFence(_ text: String) -> String {
    guard fence(opening: text.firstLine) != nil else { return text }
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
  /// with a fence, the *last* line that closes that fence is the wrapper's closer, so any
  /// chatter after it is also discarded — embedded code blocks inside the document close in
  /// pairs before it. Without an opening fence only an exact trailing bare fence line is
  /// removed, so a fence inside a document body is never a cut point.
  private static func droppingClosingFence(_ text: String, openingFence: Fence?) -> String {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    let isCloser: (Substring) -> Bool = { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if let openingFence { return closes(trimmed, openingFence) }
      return isBareFence(trimmed)
    }
    guard let lastFence = lines.lastIndex(where: isCloser) else { return text }
    if lastFence == lines.indices.last {
      lines.removeLast()
      return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard openingFence != nil else { return text }
    return lines[..<lastFence].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

nonisolated extension String {
  fileprivate var firstLine: String {
    String(prefix { $0 != "\n" })
  }
}
