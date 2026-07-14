import Foundation
import WhisperKit

public actor WhisperKitTranscriptionService: TranscriptionService {
    private let model: ModelDescriptor
    private let modelsDirectory: URL
    private var whisperKit: WhisperKit?
    private var languageResolver: TranscriptionLanguageResolver

    public init(
        model: ModelDescriptor,
        modelsDirectory: URL? = nil,
        transcriptionLanguage: TranscriptionLanguage = .automatic
    ) throws {
        self.model = model
        languageResolver = TranscriptionLanguageResolver(selection: transcriptionLanguage)
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
        let decodingPlan = languageResolver.decodingPlan
        let options = DecodingOptions(
            language: decodingPlan.languageCode,
            detectLanguage: decodingPlan.shouldDetectLanguage,
            skipSpecialTokens: true,
            wordTimestamps: true,
            concurrentWorkerCount: 1
        )
        let results = try await whisperKit.transcribe(
            audioArray: floatSamples,
            decodeOptions: options
        )
        let mapped = Self.map(results: results, offset: offset, status: .provisional)
        if decodingPlan.shouldDetectLanguage,
           let resultWithUsableText = results.first(where: Self.hasUsableTranscript)
        {
            languageResolver.lockDetectedLanguage(
                resultWithUsableText.language,
                hasUsableTranscription: true
            )
        }
        return mapped
    }

    public func resolvedLanguageCode() async -> String? {
        languageResolver.resolvedLanguageCode
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

        if languageResolver.requiresDetectionBeforeFinalization {
            let detection = try await whisperKit.detectLanguage(audioPath: audioURL.path)
            guard languageResolver.lockDetectedLanguage(
                detection.language,
                hasUsableTranscription: true
            ) else {
                throw TranscriptionLanguageResolutionError.invalidDetectedLanguage
            }
        }

        guard let languageCode = languageResolver.decodingPlan.languageCode else {
            throw TranscriptionLanguageResolutionError.invalidDetectedLanguage
        }
        let options = DecodingOptions(
            language: languageCode,
            detectLanguage: false,
            skipSpecialTokens: true,
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
            guard let text = TranscriptTextSanitizer.sanitized(segment.text) else { return nil }
            return TranscriptSegment(
                startTime: offset + TimeInterval(segment.start),
                endTime: offset + TimeInterval(segment.end),
                text: text,
                status: status
            )
        }
    }

    private static func hasUsableTranscript(_ result: TranscriptionResult) -> Bool {
        result.segments.contains { TranscriptTextSanitizer.sanitized($0.text) != nil }
    }
}

private enum TranscriptionLanguageResolutionError: Error, LocalizedError {
    case invalidDetectedLanguage

    var errorDescription: String? {
        "无法检测转写语言，请重试或在设置中固定选择中文或英文。"
    }
}
