import Foundation

public enum RecoveryAction: String, CaseIterable, Sendable {
    case resumeFinalization
    case openLiveTranscript
    case deleteSession
}

public struct RecoveryCandidate: Identifiable, Sendable {
    public let id: UUID
    public let session: RecordingSession
    public let availableActions: [RecoveryAction]

    public init(session: RecordingSession, availableActions: [RecoveryAction]) {
        id = session.id
        self.session = session
        self.availableActions = availableActions
    }
}

public struct RecoveryPolicy: Sendable {
    public init() {}

    public func candidate(for session: RecordingSession) -> RecoveryCandidate? {
        guard isRecoverable(session.state) else { return nil }

        var actions: [RecoveryAction] = [.openLiveTranscript, .deleteSession]
        if session.temporaryAudioPath != nil {
            actions.insert(.resumeFinalization, at: 0)
        }
        return RecoveryCandidate(session: session, availableActions: actions)
    }

    private func isRecoverable(_ state: AppSessionState) -> Bool {
        switch state {
        case .preparing, .recording, .paused, .finalizing, .failed:
            true
        case .idle, .completed:
            false
        }
    }
}

