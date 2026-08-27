import Foundation

nonisolated public enum ProwlSkillScope: String, Codable, Equatable, Sendable {
  case user
  case project
}

/// One verified agent skill directory (065 S0). Directories are relative to the scope root:
/// the user's home directory or a project root.
nonisolated public struct SkillInstallTarget: Equatable, Sendable, Identifiable {
  public let id: String
  public let displayName: String
  public let userDirectory: String
  public let projectDirectory: String

  public static let all: [SkillInstallTarget] = [
    SkillInstallTarget(
      id: "claude",
      displayName: "Claude Code",
      userDirectory: ".claude/skills",
      projectDirectory: ".claude/skills"
    ),
    SkillInstallTarget(
      id: "codex",
      displayName: "Codex",
      userDirectory: ".codex/skills",
      projectDirectory: ".codex/skills"
    ),
    SkillInstallTarget(
      id: "agents",
      displayName: "Shared agents directory",
      userDirectory: ".agents/skills",
      projectDirectory: ".agents/skills"
    ),
  ]

  public static func target(id: String) -> SkillInstallTarget? {
    all.first { $0.id == id }
  }

  public func skillsDirectoryURL(scope: ProwlSkillScope, root: URL) -> URL {
    let directory =
      switch scope {
      case .user: userDirectory
      case .project: projectDirectory
      }
    return root.appending(path: directory, directoryHint: .isDirectory)
  }

  /// A target is detected when the parent of its skills directory (for example `~/.codex`)
  /// exists, so a runtime that was never set up is not selected by default.
  public func isDetected(scope: ProwlSkillScope, root: URL) -> Bool {
    let parent = skillsDirectoryURL(scope: scope, root: root).deletingLastPathComponent()
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: parent.path(percentEncoded: false), isDirectory: &isDirectory)
      && isDirectory.boolValue
  }
}

nonisolated public struct SkillTargetStatus: Equatable, Sendable {
  public let target: SkillInstallTarget
  public let detected: Bool
  public let linkPath: String
  public let status: SymlinkInstallStatus

  public init(target: SkillInstallTarget, detected: Bool, linkPath: String, status: SymlinkInstallStatus) {
    self.target = target
    self.detected = detected
    self.linkPath = linkPath
    self.status = status
  }
}

/// Skill × target link operations shared by `prowl skills` and the Settings UI.
nonisolated public enum ProwlSkillInstaller {
  public static func status(
    skill: BundledSkill,
    target: SkillInstallTarget,
    scope: ProwlSkillScope,
    root: URL
  ) -> SkillTargetStatus {
    let linkPath = linkPath(skill: skill, target: target, scope: scope, root: root)
    return SkillTargetStatus(
      target: target,
      detected: target.isDetected(scope: scope, root: root),
      linkPath: linkPath,
      status: SymlinkInstaller.status(linkPath: linkPath, source: sourcePath(skill))
    )
  }

  /// Creates the target directory when missing and links the bundled skill directory.
  public static func install(
    skill: BundledSkill,
    target: SkillInstallTarget,
    scope: ProwlSkillScope,
    root: URL
  ) throws -> SkillTargetStatus {
    try SymlinkInstaller.install(
      source: sourcePath(skill),
      linkPath: linkPath(skill: skill, target: target, scope: scope, root: root)
    )
    return status(skill: skill, target: target, scope: scope, root: root)
  }

  public static func uninstall(
    skill: BundledSkill,
    target: SkillInstallTarget,
    scope: ProwlSkillScope,
    root: URL
  ) throws -> SkillTargetStatus {
    try SymlinkInstaller.uninstall(linkPath: linkPath(skill: skill, target: target, scope: scope, root: root))
    return status(skill: skill, target: target, scope: scope, root: root)
  }

  public static func sourcePath(_ skill: BundledSkill) -> String {
    skill.directoryURL.path(percentEncoded: false).trimmingTrailingPathSeparator()
  }

  private static func linkPath(
    skill: BundledSkill,
    target: SkillInstallTarget,
    scope: ProwlSkillScope,
    root: URL
  ) -> String {
    target.skillsDirectoryURL(scope: scope, root: root)
      .appending(path: skill.id, directoryHint: .notDirectory)
      .path(percentEncoded: false)
      .trimmingTrailingPathSeparator()
  }
}
