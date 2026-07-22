import XCTest
#if canImport(ScreenScribeCore)
@testable import ScreenScribeCore
#elseif canImport(ScreenScribe)
@testable import ScreenScribe
#endif

final class SessionStateMachineTests: XCTestCase {
    func testCompleteRecordingFlow() throws {
        var machine = SessionStateMachine()
        try machine.transition(to: .preparing)
        try machine.transition(to: .recording)
        try machine.transition(to: .paused)
        try machine.transition(to: .recording)
        try machine.transition(to: .finalizing)
        try machine.transition(to: .completed)
        XCTAssertEqual(machine.state, .completed)
    }

    func testRejectsInvalidTransition() {
        var machine = SessionStateMachine()
        XCTAssertThrowsError(
            try machine.transition(to: .recording)
        )
    }

    func testFailedSessionCanResumeFinalization() throws {
        var machine = SessionStateMachine(initialState: .failed)
        try machine.transition(to: .finalizing)
        XCTAssertEqual(machine.state, .finalizing)
    }
}
