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
    let hadOpeningFence = text.hasPrefix("```")
    text = droppingOpeningFence(text)
    text = droppingPreamble(text)
    text = droppingClosingFence(text, truncatingTrailer: hadOpeningFence)
    return text
  }

  /// A reply may put chatter *before* the fence that wraps the document ("Sure, here it is:"
  /// then "```markdown"). When a fence line precedes the first heading, everything up to that
  /// fence is preamble and the fence becomes the opening fence.
  private static func droppingPreambleBeforeOpeningFence(_ text: String) -> String {
    guard !text.hasPrefix("```"), !text.hasPrefix("#") else { return text }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard let heading = lines.firstIndex(where: { $0.hasPrefix("# ") || $0.hasPrefix("## ") }),
      let fence = lines.firstIndex(where: { $0.hasPrefix("```") }), fence < heading
    else { return text }
    return lines[fence...].joined(separator: "\n")
  }

  /// Unwraps the opening line of a markdown code fence ("```markdown").
  private static func droppingOpeningFence(_ text: String) -> String {
    guard text.hasPrefix("```") else { return text }
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

  /// Drops a trailing code-fence line left over after preamble removal. When the reply opened
  /// with a fence, the *last* fence line is that wrapper's closer, so any chatter after it is
  /// also discarded — embedded code blocks inside the document close in pairs before it.
  /// Without an opening fence only an exact trailing fence line is removed, so a fence inside
  /// a document body is never a cut point.
  private static func droppingClosingFence(_ text: String, truncatingTrailer: Bool) -> String {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard let lastFence = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "```" })
    else { return text }
    if lastFence == lines.indices.last {
      lines.removeLast()
      return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard truncatingTrailer else { return text }
    return lines[..<lastFence].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
