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
    /// Loads and prewarms the selected model before audio capture begins.
    func prepare() async throws

    func transcribeWindow(
        samples: [Int16],
        sampleRate: Int,
        offset: TimeInterval
    ) async throws -> [TranscriptSegment]

    func refine(audioURL: URL) -> AsyncThrowingStream<[TranscriptSegment], Error>

    /// Returns the fixed or automatically locked language for this recording.
    func resolvedLanguageCode() async -> String?
}

public extension TranscriptionService {
    func resolvedLanguageCode() async -> String? { nil }
}

public enum TranscriptionPreparationError: Error, LocalizedError, Sendable {
    case modelUnavailable(ModelDescriptor)
    case modelDamaged(ModelDescriptor, message: String)

    public var errorDescription: String? {
        switch self {
        case let .modelUnavailable(model):
            "尚未安装\(model.displayName)，请在设置中下载后再开始录制。"
        case let .modelDamaged(model, message):
            "\(model.displayName)无法加载，模型可能已损坏。请在设置中重新下载。\n\(message)"
        }
    }
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
