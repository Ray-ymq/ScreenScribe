import Foundation

public struct RecordingSession: Codable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var source: CaptureSourceSelection
    public var state: AppSessionState
    public var createdAt: Date
    public var updatedAt: Date
    public var activeDuration: TimeInterval
    public var modelID: String
    public var segments: [TranscriptSegment]
    public var conflicts: [TranscriptConflict]
    public var temporaryAudioPath: String?
    public var failureMessage: String?

    public init(
        id: UUID = UUID(),
        title: String,
        source: CaptureSourceSelection,
        state: AppSessionState = .idle,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        activeDuration: TimeInterval = 0,
        modelID: String = "small",
        segments: [TranscriptSegment] = [],
        conflicts: [TranscriptConflict] = [],
        temporaryAudioPath: String? = nil,
        failureMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activeDuration = activeDuration
        self.modelID = modelID
        self.segments = segments
        self.conflicts = conflicts
        self.temporaryAudioPath = temporaryAudioPath
        self.failureMessage = failureMessage
    }
}

