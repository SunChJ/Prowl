import Foundation
import Testing

@testable import supacode

@MainActor
struct AgentDispatchCommandHandlerTests {
  @Test func completionRequiresCallerContextAndReturnsImmutableReceipt() async throws {
    let caller = CallerPane(worktreeID: "w1", surfaceID: UUID())
    let target = makeTarget(paneID: caller.surfaceID.uuidString)
    let snapshot = AgentDispatchSnapshot(
      record: .completed(
        id: "d1",
        outcome: .succeeded,
        summary: "Done",
        createdAt: Self.start,
        completedAt: Self.start
      ),
      binding: AgentDispatchBinding(surfaceID: caller.surfaceID, target: target, evidenceEpoch: UUID())
    )
    let handler = AgentDispatchCompleteCommandHandler(
      resolveCaller: { _ in caller },
      complete: { id, outcome, summary, surfaceID in
        #expect(id == "d1")
        #expect(outcome == .succeeded)
        #expect(summary == "Done")
        #expect(surfaceID == caller.surfaceID)
        return .success(AgentDispatchMutationResult(snapshot: snapshot, replayed: false))
      },
      now: { Self.start }
    )

    let missingContext = await handler.handle(
      envelope: envelope(.agentsDispatchComplete(.init(dispatchID: "d1", outcome: .succeeded, summary: "Done")))
    )
    #expect(missingContext.error?.code == CLIErrorCode.dispatchContextRequired)

    let response = await handler.handle(
      envelope: envelope(.agentsDispatchComplete(.init(dispatchID: "d1", outcome: .succeeded, summary: "Done"))),
      context: CLICommandContext(callerProcessID: 123)
    )
    #expect(response.ok)
    let payload = try #require(response.data).decode(as: DispatchCompleteCommandPayload.self)
    #expect(payload.target == target)
    #expect(payload.receipt.id == "d1")
    #expect(!payload.replayed)
  }

  @Test func completionMapsStoreFailuresToStableCodes() async {
    let caller = CallerPane(worktreeID: "w1", surfaceID: UUID())
    for (error, code) in [
      (AgentDispatchStoreError.notFound, CLIErrorCode.dispatchNotFound),
      (.sourceMismatch, CLIErrorCode.dispatchSourceMismatch),
      (.alreadyCompleted, CLIErrorCode.dispatchAlreadyCompleted),
      (.alreadyTerminal, CLIErrorCode.dispatchAlreadyTerminal),
    ] {
      let handler = AgentDispatchCompleteCommandHandler(
        resolveCaller: { _ in caller },
        complete: { _, _, _, _ in .failure(error) }
      )
      let response = await handler.handle(
        envelope: envelope(.agentsDispatchComplete(.init(dispatchID: "d1", outcome: .failed, summary: "No"))),
        context: CLICommandContext(callerProcessID: 123)
      )
      #expect(response.error?.code == code)
    }
  }

  @Test func abandonmentNeedsNoCallerAndIsIdempotent() async throws {
    let target = makeTarget(paneID: UUID().uuidString)
    let snapshot = AgentDispatchSnapshot(
      record: .abandoned(id: "d1", createdAt: Self.start, abandonedAt: Self.start, reason: "Stop"),
      binding: AgentDispatchBinding(surfaceID: UUID(), target: target, evidenceEpoch: UUID())
    )
    let handler = AgentDispatchAbandonCommandHandler(
      abandon: { id, reason in
        #expect(id == "d1")
        #expect(reason == "Stop")
        return .success(AgentDispatchMutationResult(snapshot: snapshot, replayed: true))
      },
      now: { Self.start }
    )
    let response = await handler.handle(
      envelope: envelope(.agentsDispatchAbandon(.init(dispatchID: "d1", reason: "Stop")))
    )
    #expect(response.ok)
    let payload = try #require(response.data).decode(as: DispatchAbandonCommandPayload.self)
    #expect(payload.target == target)
    #expect(payload.replayed)
  }

  private static let start = Date(timeIntervalSince1970: 1_000)

  private func envelope(_ command: Command) -> CommandEnvelope {
    CommandEnvelope(output: .json, command: command)
  }

  private func makeTarget(paneID: String) -> TabTarget {
    TabTarget(
      worktree: .init(id: "w1", name: "App", path: "/App", rootPath: "/App", kind: "worktree"),
      tab: .init(id: "t1", title: "Agent", selected: true),
      pane: .init(id: paneID, title: "Agent", cwd: "/App", focused: true)
    )
  }
}
