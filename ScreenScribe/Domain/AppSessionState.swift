import Foundation

public enum AppSessionState: String, Codable, CaseIterable, Sendable {
    case idle
    case preparing
    case recording
    case paused
    case finalizing
    case completed
    case failed

    public var locksTranscriptionLanguageSelection: Bool {
        switch self {
        case .preparing, .recording, .paused, .finalizing:
            true
        case .idle, .completed, .failed:
            false
        }
    }

    public func allowsTransition(to next: AppSessionState) -> Bool {
        switch (self, next) {
        case (.idle, .preparing),
             (.preparing, .idle),
             (.preparing, .recording),
             (.preparing, .failed),
             (.recording, .paused),
             (.recording, .finalizing),
             (.recording, .failed),
             (.paused, .recording),
             (.paused, .finalizing),
             (.paused, .failed),
             (.finalizing, .completed),
             (.finalizing, .failed),
             (.completed, .idle),
             (.completed, .failed),
             (.failed, .idle),
             (.failed, .finalizing):
            return true
        default:
            return self == next
        }
    }
}

public enum SessionStateError: Error, Equatable, LocalizedError {
    case invalidTransition(from: AppSessionState, to: AppSessionState)

    public var errorDescription: String? {
        switch self {
        case let .invalidTransition(from, to):
            return "无法从 \(from.rawValue) 切换到 \(to.rawValue)"
        }
    }
}

public struct SessionStateMachine: Sendable {
    public private(set) var state: AppSessionState

    public init(initialState: AppSessionState = .idle) {
        state = initialState
    }

    public mutating func transition(to next: AppSessionState) throws {
        guard state.allowsTransition(to: next) else {
            throw SessionStateError.invalidTransition(from: state, to: next)
        }
        state = next
    }
}
