import Foundation

/// Creates a temporary directory containing `entries` (a trailing slash marks
/// a subdirectory, like an `.xcodeproj` bundle) and removes it after `body`
/// runs.
func withTemporaryProjectDirectory(
  entries: [String],
  contents: [String: Data] = [:],
  body: (URL) throws -> Void
) throws {
  let fileManager = FileManager.default
  let directory = fileManager.temporaryDirectory
    .appending(path: "project-fixture-\(UUID().uuidString)")
  try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? fileManager.removeItem(at: directory) }
  for entry in entries {
    if entry.hasSuffix("/") {
      try fileManager.createDirectory(
        at: directory.appending(path: String(entry.dropLast())),
        withIntermediateDirectories: true
      )
    } else {
      try Data().write(to: directory.appending(path: entry))
    }
  }
  for (path, data) in contents {
    let fileURL = directory.appending(path: path)
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: fileURL)
  }
  try body(directory)
}
