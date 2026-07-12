import Foundation

public struct TranscriptionProgress: Equatable, Sendable {
    public let fractionCompleted: Double
    public let inferenceDelay: TimeInterval

    public init(fractionCompleted: Double, inferenceDelay: TimeInterval) {
        self.fractionCompleted = fractionCompleted
        self.inferenceDelay = inferenceDelay
    }
}

public protocol TranscriptionService: Sendable {
    func transcribeWindow(
        samples: [Int16],
        sampleRate: Int,
        offset: TimeInterval
    ) async throws -> [TranscriptSegment]

    func refine(audioURL: URL) -> AsyncThrowingStream<[TranscriptSegment], Error>
}

public struct ModelDescriptor: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let approximateBytes: Int64

    public init(id: String, displayName: String, approximateBytes: Int64) {
        self.id = id
        self.displayName = displayName
        self.approximateBytes = approximateBytes
    }

    public static let small = ModelDescriptor(
        id: "small",
        displayName: "多语言 Small",
        approximateBytes: 486_000_000
    )

    public static let medium = ModelDescriptor(
        id: "medium",
        displayName: "多语言 Medium",
        approximateBytes: 1_530_000_000
    )

    public var whisperKitVariant: String {
        switch id {
        case Self.small.id: "openai_whisper-small"
        case Self.medium.id: "openai_whisper-medium"
        default: id
        }
    }
}

public protocol ModelManager: Sendable {
    func installedModels() async throws -> [ModelDescriptor]
    func download(_ model: ModelDescriptor) -> AsyncThrowingStream<Double, Error>
    func delete(_ model: ModelDescriptor) async throws
}
