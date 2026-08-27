import Foundation

nonisolated public enum ProwlSkillAudience: String, Codable, Equatable, Sendable {
  case user
  case workflow
}

nonisolated public struct BundledSkill: Equatable, Sendable {
  public let id: String
  public let name: String
  public let description: String
  public let audience: ProwlSkillAudience
  public let directoryURL: URL

  public init(
    id: String,
    name: String,
    description: String,
    audience: ProwlSkillAudience,
    directoryURL: URL
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.audience = audience
    self.directoryURL = directoryURL
  }
}

nonisolated public enum ProwlSkillsError: Error, Equatable, Sendable, LocalizedError {
  public enum Code: String, Equatable, Sendable {
    case bundleNotFound = "BUNDLE_NOT_FOUND"
    case invalidFrontmatter = "INVALID_SKILL_FRONTMATTER"
  }

  case bundleNotFound(path: String)
  case invalidFrontmatter(path: String, reason: String)

  public var code: Code {
    switch self {
    case .bundleNotFound:
      .bundleNotFound
    case .invalidFrontmatter:
      .invalidFrontmatter
    }
  }

  public var errorDescription: String? {
    switch self {
    case .bundleNotFound(let path):
      "Bundled skills were not found at \(path)."
    case .invalidFrontmatter(let path, let reason):
      "Invalid skill frontmatter at \(path): \(reason)"
    }
  }
}

nonisolated public enum ProwlSkills {
  public static func bundled(resourcesURL: URL) throws -> [BundledSkill] {
    try bundled(
      skillsURL: resourcesURL.appending(path: "skills", directoryHint: .isDirectory)
    )
  }

  public static func skill(id: String, resourcesURL: URL) throws -> BundledSkill? {
    try bundled(resourcesURL: resourcesURL).first { $0.id == id }
  }

  public static func bundledForCLI(
    executableURL: URL,
    environment: [String: String]
  ) throws -> [BundledSkill] {
    if let overridePath = environment["PROWL_SKILLS_DIR"] {
      guard !overridePath.isEmpty else {
        throw ProwlSkillsError.bundleNotFound(path: overridePath)
      }
      return try bundled(
        skillsURL: URL(filePath: overridePath, directoryHint: .isDirectory)
      )
    }

    let resolvedExecutableURL = executableURL.standardizedFileURL.resolvingSymlinksInPath()
    let executableDirectory = resolvedExecutableURL.deletingLastPathComponent()
    guard resolvedExecutableURL.lastPathComponent == "prowl",
      executableDirectory.lastPathComponent == "prowl-cli"
    else {
      throw ProwlSkillsError.bundleNotFound(
        path: resolvedExecutableURL.path(percentEncoded: false)
      )
    }
    return try bundled(resourcesURL: executableDirectory.deletingLastPathComponent())
  }

  private static func bundled(skillsURL: URL) throws -> [BundledSkill] {
    let standardizedSkillsURL = skillsURL.standardizedFileURL
    let skillsPath = standardizedSkillsURL.path(percentEncoded: false)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: skillsPath, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw ProwlSkillsError.bundleNotFound(path: skillsPath)
    }

    let contents: [URL]
    do {
      contents = try FileManager.default.contentsOfDirectory(
        at: standardizedSkillsURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    } catch {
      throw ProwlSkillsError.bundleNotFound(path: skillsPath)
    }

    let directories =
      contents
      .filter { url in
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    return try directories.compactMap { directoryURL in
      let skillFileURL = directoryURL.appending(path: "SKILL.md", directoryHint: .notDirectory)
      guard FileManager.default.fileExists(atPath: skillFileURL.path(percentEncoded: false)) else {
        return nil
      }
      return try parseSkill(
        id: directoryURL.lastPathComponent,
        directoryURL: directoryURL.standardizedFileURL,
        skillFileURL: skillFileURL
      )
    }
  }

  private static func parseSkill(
    id: String,
    directoryURL: URL,
    skillFileURL: URL
  ) throws -> BundledSkill {
    let skillPath = skillFileURL.path(percentEncoded: false)
    let data: Data
    do {
      data = try Data(contentsOf: skillFileURL)
    } catch {
      throw ProwlSkillsError.invalidFrontmatter(
        path: skillPath,
        reason: "SKILL.md could not be read"
      )
    }
    guard let source = String(data: data, encoding: .utf8) else {
      throw ProwlSkillsError.invalidFrontmatter(
        path: skillPath,
        reason: "SKILL.md is not valid UTF-8"
      )
    }

    let frontmatter = try parseFrontmatter(source, path: skillPath)
    return BundledSkill(
      id: id,
      name: frontmatter.name,
      description: frontmatter.description,
      audience: frontmatter.audience,
      directoryURL: directoryURL
    )
  }

  private static func parseFrontmatter(_ source: String, path: String) throws -> ParsedFrontmatter {
    let normalizedSource =
      source
      .replacing("\r\n", with: "\n")
      .replacing("\r", with: "\n")
    let lines = normalizedSource.split(separator: "\n", omittingEmptySubsequences: false).map(
      String.init)
    guard lines.first == "---",
      let closingIndex = lines.indices.dropFirst().first(where: { lines[$0] == "---" })
    else {
      throw invalidFrontmatter(path: path, reason: "missing frontmatter delimiters")
    }

    let frontmatterLines = Array(lines[1..<closingIndex])
    var name: String?
    var description: String?
    var audience = ProwlSkillAudience.user
    var audienceWasSet = false
    var index = 0

    while index < frontmatterLines.count {
      let line = frontmatterLines[index]
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        index += 1
        continue
      }
      guard indentation(of: line) == 0,
        let (key, value) = keyValue(in: line),
        !key.isEmpty
      else {
        throw invalidFrontmatter(path: path, reason: "malformed top-level field")
      }

      try validateTopLevelKey(key, path: path)

      switch key {
      case "name":
        guard name == nil, !value.isEmpty else {
          throw invalidFrontmatter(path: path, reason: "name must be a non-empty scalar")
        }
        name = value
        index += 1

      case "description":
        guard description == nil else {
          throw invalidFrontmatter(path: path, reason: "description is duplicated")
        }
        if value == ">-" {
          let result = try foldedDescription(
            lines: frontmatterLines,
            startIndex: index + 1,
            path: path
          )
          description = result.value
          index = result.nextIndex
        } else {
          guard !value.isEmpty else {
            throw invalidFrontmatter(
              path: path, reason: "description must be a non-empty scalar or >- block")
          }
          description = value
          index += 1
        }

      case "metadata":
        guard value.isEmpty else {
          throw invalidFrontmatter(path: path, reason: "metadata must be a map")
        }
        let result = try audienceMetadata(
          lines: frontmatterLines,
          startIndex: index + 1,
          currentAudience: audience,
          audienceWasSet: audienceWasSet,
          path: path
        )
        audience = result.audience
        audienceWasSet = result.wasSet
        index = result.nextIndex

      default:
        index += 1
      }
    }

    guard let name else {
      throw invalidFrontmatter(path: path, reason: "name is missing")
    }
    guard let description else {
      throw invalidFrontmatter(path: path, reason: "description is missing")
    }
    return ParsedFrontmatter(name: name, description: description, audience: audience)
  }

  private static func foldedDescription(
    lines: [String],
    startIndex: Int,
    path: String
  ) throws -> (value: String, nextIndex: Int) {
    var index = startIndex
    var blockLines: [String] = []
    while index < lines.count {
      let line = lines[index]
      if !line.trimmingCharacters(in: .whitespaces).isEmpty, indentation(of: line) == 0 {
        break
      }
      blockLines.append(line)
      index += 1
    }

    let nonEmptyLines = blockLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    guard let blockIndent = nonEmptyLines.compactMap(indentation).min(), blockIndent > 0 else {
      throw invalidFrontmatter(path: path, reason: "folded description is empty or malformed")
    }

    var paragraphs: [String] = []
    var paragraphLines: [String] = []
    for line in blockLines {
      let stripped = String(line.dropFirst(min(blockIndent, line.count)))
        .trimmingCharacters(in: .whitespaces)
      if stripped.isEmpty {
        if !paragraphLines.isEmpty {
          paragraphs.append(paragraphLines.joined(separator: " "))
          paragraphLines.removeAll(keepingCapacity: true)
        }
      } else {
        paragraphLines.append(stripped)
      }
    }
    if !paragraphLines.isEmpty {
      paragraphs.append(paragraphLines.joined(separator: " "))
    }

    let value = paragraphs.joined(separator: "\n")
    guard !value.isEmpty else {
      throw invalidFrontmatter(path: path, reason: "folded description is empty")
    }
    return (value, index)
  }

  private static func audienceMetadata(
    lines: [String],
    startIndex: Int,
    currentAudience: ProwlSkillAudience,
    audienceWasSet: Bool,
    path: String
  ) throws -> ParsedAudienceMetadata {
    var audience = currentAudience
    var wasSet = audienceWasSet
    var directFieldIndent: Int?
    var index = startIndex

    while index < lines.count {
      let line = lines[index]
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        index += 1
        continue
      }
      guard let fieldIndent = indentation(of: line) else {
        throw invalidFrontmatter(path: path, reason: "metadata uses invalid indentation")
      }
      if fieldIndent == 0 {
        break
      }
      if directFieldIndent == nil {
        directFieldIndent = fieldIndent
      }
      guard let directFieldIndent, fieldIndent == directFieldIndent else {
        throw invalidFrontmatter(
          path: path,
          reason: "metadata fields must use consistent direct-child indentation"
        )
      }
      guard let (key, value) = keyValue(in: line), !key.isEmpty else {
        throw invalidFrontmatter(path: path, reason: "metadata contains a malformed field")
      }
      if key == "prowl-install" {
        guard !wasSet, let parsedAudience = ProwlSkillAudience(rawValue: value) else {
          throw invalidFrontmatter(
            path: path, reason: "metadata.prowl-install must be user or workflow")
        }
        audience = parsedAudience
        wasSet = true
      }
      index += 1
    }

    return ParsedAudienceMetadata(audience: audience, wasSet: wasSet, nextIndex: index)
  }

  private static func validateTopLevelKey(_ key: String, path: String) throws {
    guard key != "prowl-install" else {
      throw invalidFrontmatter(
        path: path,
        reason: "prowl-install must be a direct child of metadata"
      )
    }
  }

  private static func keyValue(in line: String) -> (key: String, value: String)? {
    guard let separator = line.firstIndex(of: ":") else {
      return nil
    }
    let key = line[..<separator].trimmingCharacters(in: .whitespaces)
    let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
    return (key, value)
  }

  private static func indentation(of line: String) -> Int? {
    var indentation = 0
    for character in line {
      switch character {
      case " ":
        indentation += 1
      case "\t":
        return nil
      default:
        return indentation
      }
    }
    return indentation
  }

  private static func invalidFrontmatter(path: String, reason: String) -> ProwlSkillsError {
    .invalidFrontmatter(path: path, reason: reason)
  }
}

nonisolated private struct ParsedFrontmatter {
  let name: String
  let description: String
  let audience: ProwlSkillAudience
}

nonisolated private struct ParsedAudienceMetadata {
  let audience: ProwlSkillAudience
  let wasSet: Bool
  let nextIndex: Int
}
