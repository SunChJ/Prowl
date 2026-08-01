import ComposableArchitecture
import Testing

@testable import supacode

private struct Counter: Reducer {
  struct State: Equatable {
    var count = 0
    var label = ""
  }

  enum Action: Equatable {
    case increment
    case setLabel(String)
  }

  func reduce(into state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .increment:
      state.count += 1
      return .none
    case .setLabel(let value):
      state.label = value
      return .none
    }
  }
}

@MainActor
struct LogActionsReducerTests {
  /// With action logging off (the default), the wrapper must reduce exactly like
  /// its base — same state mutation, no diverging behavior from the gated path.
  @Test func passesActionsThroughToBaseWhenLoggingDisabled() {
    let reducer = LogActionsReducer(base: Counter())
    var state = Counter.State()

    _ = reducer.reduce(into: &state, action: .increment)
    _ = reducer.reduce(into: &state, action: .setLabel("repo"))

    #expect(state.count == 1)
    #expect(state.label == "repo")
  }

  /// A no-op action leaves state untouched, so the diff branch has nothing to
  /// print; the reducer must still return the base's effect and state.
  @Test func leavesStateUnchangedForActionsThatDoNotMutate() {
    let reducer = LogActionsReducer(base: Counter())
    var state = Counter.State(count: 5, label: "keep")

    _ = reducer.reduce(into: &state, action: .setLabel("keep"))

    #expect(state.count == 5)
    #expect(state.label == "keep")
  }
}
