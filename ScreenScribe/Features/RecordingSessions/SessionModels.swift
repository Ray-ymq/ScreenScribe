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
    public var transcriptionLanguage: TranscriptionLanguage
    public var detectedLanguageCode: String?
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
        transcriptionLanguage: TranscriptionLanguage = .automatic,
        detectedLanguageCode: String? = nil,
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
        self.transcriptionLanguage = transcriptionLanguage
        self.detectedLanguageCode = TranscriptionLanguage.normalizedLanguageCode(detectedLanguageCode)
        self.segments = segments
        self.conflicts = conflicts
        self.temporaryAudioPath = temporaryAudioPath
        self.failureMessage = failureMessage
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case source
        case state
        case createdAt
        case updatedAt
        case activeDuration
        case modelID
        case transcriptionLanguage
        case detectedLanguageCode
        case segments
        case conflicts
        case temporaryAudioPath
        case failureMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        source = try container.decode(CaptureSourceSelection.self, forKey: .source)
        state = try container.decode(AppSessionState.self, forKey: .state)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        activeDuration = try container.decode(TimeInterval.self, forKey: .activeDuration)
        modelID = try container.decode(String.self, forKey: .modelID)
        if let rawLanguage = try container.decodeIfPresent(String.self, forKey: .transcriptionLanguage) {
            transcriptionLanguage = TranscriptionLanguage(rawValue: rawLanguage) ?? .automatic
        } else {
            transcriptionLanguage = .automatic
        }
        detectedLanguageCode = TranscriptionLanguage.normalizedLanguageCode(
            try container.decodeIfPresent(String.self, forKey: .detectedLanguageCode)
        )
        segments = try container.decode([TranscriptSegment].self, forKey: .segments)
        conflicts = try container.decode([TranscriptConflict].self, forKey: .conflicts)
        temporaryAudioPath = try container.decodeIfPresent(String.self, forKey: .temporaryAudioPath)
        failureMessage = try container.decodeIfPresent(String.self, forKey: .failureMessage)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(source, forKey: .source)
        try container.encode(state, forKey: .state)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(activeDuration, forKey: .activeDuration)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(transcriptionLanguage.rawValue, forKey: .transcriptionLanguage)
        try container.encodeIfPresent(detectedLanguageCode, forKey: .detectedLanguageCode)
        try container.encode(segments, forKey: .segments)
        try container.encode(conflicts, forKey: .conflicts)
        try container.encodeIfPresent(temporaryAudioPath, forKey: .temporaryAudioPath)
        try container.encodeIfPresent(failureMessage, forKey: .failureMessage)
    }
}
