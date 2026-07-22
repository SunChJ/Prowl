import Foundation
import IdentifiedCollections
import Testing

@testable import supacode

@MainActor
struct WorktreeDirectoryIndexTests {
  @Test func resolvesNestedDirectoryToItsEnclosingWorktree() {
    let worktree = makeWorktree(repoRoot: "/tmp/repo", path: "/tmp/repo", branch: "main")
    let index = WorktreeDirectoryIndex(repositories: [makeRepository(id: "/tmp/repo", worktrees: [worktree])])

    #expect(
      index.worktreeID(forWorkingDirectory: URL(fileURLWithPath: "/tmp/repo/src/lib")) == worktree.id
    )
  }

  @Test func prefersTheDeepestContainingWorktree() {
    let mainWorktree = makeWorktree(repoRoot: "/tmp/repo", path: "/tmp/repo", branch: "main")
    let nestedWorktree = makeWorktree(
      repoRoot: "/tmp/repo",
      path: "/tmp/repo/worktrees/feature",
      branch: "feature"
    )
    let index = WorktreeDirectoryIndex(
      repositories: [makeRepository(id: "/tmp/repo", worktrees: [mainWorktree, nestedWorktree])]
    )

    #expect(
      index.worktreeID(forWorkingDirectory: URL(fileURLWithPath: "/tmp/repo/worktrees/feature/lib"))
        == nestedWorktree.id
    )
    #expect(
      index.worktreeID(forWorkingDirectory: URL(fileURLWithPath: "/tmp/repo/src")) == mainWorktree.id
    )
  }

  /// A sibling whose name merely starts with an indexed directory's name must not match. This is why
  /// the index compares whole path components rather than raw string prefixes.
  @Test func doesNotMatchSiblingDirectoryWithSharedNamePrefix() {
    let worktree = makeWorktree(repoRoot: "/tmp/repo", path: "/tmp/repo", branch: "main")
    let index = WorktreeDirectoryIndex(repositories: [makeRepository(id: "/tmp/repo", worktrees: [worktree])])

    #expect(index.worktreeID(forWorkingDirectory: URL(fileURLWithPath: "/tmp/repo2/src")) == nil)
    #expect(index.worktreeID(forWorkingDirectory: URL(fileURLWithPath: "/tmp/repo-backup")) == nil)
  }

  @Test func resolvesPlainFolderRepositoryByItsRootURL() {
    let repository = makeRepository(id: "/tmp/notes", kind: .plain, worktrees: [])
    let index = WorktreeDirectoryIndex(repositories: [repository])

    #expect(
      index.worktreeID(forWorkingDirectory: URL(fileURLWithPath: "/tmp/notes/inbox")) == repository.id
    )
  }

  @Test func returnsNilForDirectoryOutsideEveryRepository() {
    let worktree = makeWorktree(repoRoot: "/tmp/repo", path: "/tmp/repo", branch: "main")
    let index = WorktreeDirectoryIndex(repositories: [makeRepository(id: "/tmp/repo", worktrees: [worktree])])

    #expect(index.worktreeID(forWorkingDirectory: URL(fileURLWithPath: "/tmp/scratch")) == nil)
  }

  @Test func emptyIndexResolvesNothing() {
    let index = WorktreeDirectoryIndex()

    #expect(index.worktreeID(forWorkingDirectory: URL(fileURLWithPath: "/tmp/repo")) == nil)
  }

  /// Trailing slashes and `.` / `..` segments must normalize to the same lookup.
  @Test func normalizesRelativeSegmentsBeforeMatching() {
    let worktree = makeWorktree(repoRoot: "/tmp/repo", path: "/tmp/repo", branch: "main")
    let index = WorktreeDirectoryIndex(repositories: [makeRepository(id: "/tmp/repo", worktrees: [worktree])])

    #expect(
      index.worktreeID(forWorkingDirectory: URL(fileURLWithPath: "/tmp/repo/src/../lib")) == worktree.id
    )
  }

  // MARK: - Cache

  @Test func cacheRebuildsWhenAWorktreeIsAdded() {
    WorktreeDirectoryIndexCache.reset()
    let mainWorktree = makeWorktree(repoRoot: "/tmp/repo", path: "/tmp/repo", branch: "main")
    let before: IdentifiedArrayOf<Repository> = [makeRepository(id: "/tmp/repo", worktrees: [mainWorktree])]
    #expect(
      WorktreeDirectoryIndexCache.index(for: before)
        .worktreeID(forWorkingDirectory: URL(fileURLWithPath: "/tmp/repo/worktrees/feature/lib"))
        == mainWorktree.id
    )

    let nestedWorktree = makeWorktree(
      repoRoot: "/tmp/repo",
      path: "/tmp/repo/worktrees/feature",
      branch: "feature"
    )
    let after: IdentifiedArrayOf<Repository> = [
      makeRepository(id: "/tmp/repo", worktrees: [mainWorktree, nestedWorktree])
    ]

    #expect(
      WorktreeDirectoryIndexCache.index(for: after)
        .worktreeID(forWorkingDirectory: URL(fileURLWithPath: "/tmp/repo/worktrees/feature/lib"))
        == nestedWorktree.id
    )
  }

  /// A branch rename changes the worktree's name but not its directory, so the memo stays valid.
  @Test func cacheReturnsAnEquivalentIndexWhenOnlyBranchNamesChange() {
    WorktreeDirectoryIndexCache.reset()
    let original = makeWorktree(repoRoot: "/tmp/repo", path: "/tmp/repo", branch: "main")
    let renamed = makeWorktree(repoRoot: "/tmp/repo", path: "/tmp/repo", branch: "trunk")
    let first = WorktreeDirectoryIndexCache.index(for: [makeRepository(id: "/tmp/repo", worktrees: [original])])
    let second = WorktreeDirectoryIndexCache.index(for: [makeRepository(id: "/tmp/repo", worktrees: [renamed])])

    #expect(first == second)
  }

  // MARK: - Helpers

  private func makeWorktree(repoRoot: String, path: String, branch: String) -> Worktree {
    Worktree(
      id: path,
      name: branch,
      detail: branch,
      workingDirectory: URL(fileURLWithPath: path),
      repositoryRootURL: URL(fileURLWithPath: repoRoot)
    )
  }

  private func makeRepository(
    id: String,
    kind: Repository.Kind = .git,
    worktrees: IdentifiedArrayOf<Worktree>
  ) -> Repository {
    Repository(
      id: id,
      rootURL: URL(fileURLWithPath: id),
      name: URL(fileURLWithPath: id).lastPathComponent,
      kind: kind,
      worktrees: worktrees
    )
  }
}
