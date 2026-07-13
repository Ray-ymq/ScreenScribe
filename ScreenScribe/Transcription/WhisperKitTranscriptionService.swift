import Foundation
import WhisperKit

public actor WhisperKitTranscriptionService: TranscriptionService {
    private let model: ModelDescriptor
    private let modelsDirectory: URL
    private var whisperKit: WhisperKit?

    public init(model: ModelDescriptor, modelsDirectory: URL? = nil) throws {
        self.model = model
        if let modelsDirectory {
            self.modelsDirectory = modelsDirectory
        } else {
            self.modelsDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appending(path: "ScreenScribe", directoryHint: .isDirectory)
            .appending(path: "Models", directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(
            at: self.modelsDirectory,
            withIntermediateDirectories: true
        )
    }

    public func prepare() async throws {
        guard whisperKit == nil else { return }

        let modelManager = try WhisperKitModelManager(modelsDirectory: modelsDirectory)
        guard let localFolder = await modelManager.localModelFolder(for: model) else {
            throw TranscriptionPreparationError.modelUnavailable(model)
        }
        let configuration = WhisperKitConfig(
            model: model.whisperKitVariant,
            downloadBase: modelsDirectory,
            modelFolder: localFolder.path,
            tokenizerFolder: localFolder,
            verbose: false,
            prewarm: true,
            load: true,
            download: false,
            useBackgroundDownloadSession: false
        )
        do {
            whisperKit = try await WhisperKit(configuration)
        } catch {
            whisperKit = nil
            throw TranscriptionPreparationError.modelDamaged(
                model,
                message: error.localizedDescription
            )
        }
    }

    public func transcribeWindow(
        samples: [Int16],
        sampleRate: Int,
        offset: TimeInterval
    ) async throws -> [TranscriptSegment] {
        guard sampleRate == 16_000 else {
            throw PCMProcessingError.invalidSampleRate
        }
        try await prepare()
        guard let whisperKit else { return [] }

        let floatSamples = samples.map { Float($0) / Float(Int16.max) }
        let options = DecodingOptions(
            wordTimestamps: true,
            concurrentWorkerCount: 1
        )
        let results = try await whisperKit.transcribe(
            audioArray: floatSamples,
            decodeOptions: options
        )
        return Self.map(results: results, offset: offset, status: .provisional)
    }

    public nonisolated func refine(
        audioURL: URL
    ) -> AsyncThrowingStream<[TranscriptSegment], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let segments = try await self.refineCompleteAudio(at: audioURL)
                    continuation.yield(segments)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func refineCompleteAudio(at audioURL: URL) async throws -> [TranscriptSegment] {
        try await prepare()
        guard let whisperKit else { return [] }
        let options = DecodingOptions(
            wordTimestamps: true,
            concurrentWorkerCount: 4,
            chunkingStrategy: .vad
        )
        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )
        return Self.map(results: results, offset: 0, status: .confirmed)
    }

    private static func map(
        results: [TranscriptionResult],
        offset: TimeInterval,
        status: TranscriptSegmentStatus
    ) -> [TranscriptSegment] {
        results.flatMap(\.segments).compactMap { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(
                startTime: offset + TimeInterval(segment.start),
                endTime: offset + TimeInterval(segment.end),
                text: text,
                status: status
            )
        }
    }
}
