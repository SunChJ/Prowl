import ProwlCLIShared
import XCTest

final class MarkdownArtifactNormalizerTests: XCTestCase {
  func testStripsOpeningFencePreambleAndTrailerAfterClosingFence() {
    let text = """
      Sure, here's the file:
      ```markdown
      # Handoff
      ## Objective
      Ship.
      ```
      Let me know if you need anything else.
      """
    XCTAssertEqual(MarkdownArtifactNormalizer.normalized(text), "# Handoff\n## Objective\nShip.")
  }

  func testWithoutOpeningFenceOnlyAnExactTrailingFenceIsRemoved() {
    let text = """
      Intro chatter
      # Doc
      ```swift
      let x = 1
      ```
      ## More
      text
      ```
      """
    XCTAssertEqual(MarkdownArtifactNormalizer.normalized(text), "# Doc\n```swift\nlet x = 1\n```\n## More\ntext")
  }

  func testTextStartingWithAHeadingIsOnlyTrimmed() {
    XCTAssertEqual(MarkdownArtifactNormalizer.normalized("\n\n# Doc\nbody\n\n"), "# Doc\nbody")
  }

  func testTextWithoutHeadingsIsKept() {
    XCTAssertEqual(MarkdownArtifactNormalizer.normalized("just prose\nno headings"), "just prose\nno headings")
  }

  func testTildeFencesAreUnwrappedLikeBackticks() {
    let text = "~~~markdown\n## Findings\nx\n## Verdict\ny\n~~~\nchat trailer"
    XCTAssertEqual(MarkdownArtifactNormalizer.normalized(text), "## Findings\nx\n## Verdict\ny")
    let mixed = "Intro\n~~~\n# Doc\n```swift\nlet x = 1\n```\n~~~\nbye"
    XCTAssertEqual(MarkdownArtifactNormalizer.normalized(mixed), "# Doc\n```swift\nlet x = 1\n```")
  }

  func testHeadingsOutsideFencesAndSectionMatching() {
    let text = "# Doc\n```text\n## Hidden\n```\n~~~\n## Also hidden\n~~~\n## Visible (2)\nbody\n"
    XCTAssertEqual(MarkdownArtifactNormalizer.headings(outsideFences: text), ["# Doc", "## Visible (2)"])
    XCTAssertTrue(MarkdownArtifactNormalizer.hasSections(["## Visible"], in: text))
    XCTAssertFalse(MarkdownArtifactNormalizer.hasSections(["## Hidden"], in: text))
    XCTAssertFalse(MarkdownArtifactNormalizer.hasSections(["## Vis"], in: text))
  }

  func testFenceClosersMustBeBareRunsOfAtLeastTheOpeningLength() {
    let fake = "# Handoff\n```text\n```still code\n## Objective\n## Current State\n## Next Steps\n```\n"
    XCTAssertEqual(MarkdownArtifactNormalizer.headings(outsideFences: fake), ["# Handoff"])
    XCTAssertFalse(MarkdownArtifactNormalizer.hasSections(["## Objective"], in: fake))
    let longer = "# Doc\n````\n```\n## Hidden\n```\n````\n## Shown\n"
    XCTAssertEqual(MarkdownArtifactNormalizer.headings(outsideFences: longer), ["# Doc", "## Shown"])
    let wrapped = "````markdown\n# Doc\n```swift\nlet x = 1\n```\n````\ntrailer"
    XCTAssertEqual(MarkdownArtifactNormalizer.normalized(wrapped), "# Doc\n```swift\nlet x = 1\n```")
    let mismatched = "```markdown\n# Doc\n~~~\nbye"
    XCTAssertEqual(MarkdownArtifactNormalizer.normalized(mismatched), "# Doc\n~~~\nbye")
  }

  func testEmptyInputStaysEmpty() {
    XCTAssertEqual(MarkdownArtifactNormalizer.normalized("   \n  "), "")
  }
}
