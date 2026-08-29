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

  func testEmptyInputStaysEmpty() {
    XCTAssertEqual(MarkdownArtifactNormalizer.normalized("   \n  "), "")
  }
}
