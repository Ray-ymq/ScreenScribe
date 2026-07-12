import Foundation

public enum TranscriptSegmentStatus: String, Codable, Sendable {
    case provisional
    case confirmed
    case userEdited
}

public struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var text: String
    public var status: TranscriptSegmentStatus
    public var originalText: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        status: TranscriptSegmentStatus,
        originalText: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.status = status
        self.originalText = originalText
        self.updatedAt = updatedAt
    }
}

public struct TranscriptConflict: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let segmentID: UUID
    public let userText: String
    public let refinedText: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        segmentID: UUID,
        userText: String,
        refinedText: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.segmentID = segmentID
        self.userText = userText
        self.refinedText = refinedText
        self.createdAt = createdAt
    }
}

