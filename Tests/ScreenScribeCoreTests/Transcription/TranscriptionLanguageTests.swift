import Foundation
import XCTest
#if canImport(ScreenScribeCore)
@testable import ScreenScribeCore
#elseif canImport(ScreenScribe)
@testable import ScreenScribe
#endif

private actor LanguageReportingTranscriptionService: TranscriptionService {
    func prepare() async throws {}

    func transcribeWindow(
        samples: [Int16],
        sampleRate: Int,
        offset: TimeInterval
    ) async throws -> [TranscriptSegment] {
        [
            TranscriptSegment(
                startTime: offset,
                endTime: offset + 1,
                text: "有效文稿",
                status: .provisional
            )
        ]
    }

    nonisolated func refine(
        audioURL: URL
    ) -> AsyncThrowingStream<[TranscriptSegment], Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func resolvedLanguageCode() async -> String? { "zh" }
}

final class TranscriptionLanguageTests: XCTestCase {
    func testLanguageModesMapToWhisperDecodingPlans() {
        let automatic = TranscriptionLanguageResolver(selection: .automatic)
        XCTAssertEqual(
            automatic.decodingPlan,
            TranscriptionDecodingPlan(languageCode: nil, shouldDetectLanguage: true)
        )

        let chinese = TranscriptionLanguageResolver(selection: .chinese)
        XCTAssertEqual(
            chinese.decodingPlan,
            TranscriptionDecodingPlan(languageCode: "zh", shouldDetectLanguage: false)
        )

        let english = TranscriptionLanguageResolver(selection: .english)
        XCTAssertEqual(
            english.decodingPlan,
            TranscriptionDecodingPlan(languageCode: "en", shouldDetectLanguage: false)
        )
    }

    func testAutomaticLanguageLocksOnlyAfterFirstUsableTranscription() {
        var resolver = TranscriptionLanguageResolver(selection: .automatic)

        XCTAssertFalse(resolver.lockDetectedLanguage("en", hasUsableTranscription: false))
        XCTAssertTrue(resolver.decodingPlan.shouldDetectLanguage)
        XCTAssertTrue(resolver.requiresDetectionBeforeFinalization)

        XCTAssertTrue(resolver.lockDetectedLanguage(" ZH ", hasUsableTranscription: true))
        XCTAssertEqual(resolver.resolvedLanguageCode, "zh")
        XCTAssertEqual(
            resolver.decodingPlan,
            TranscriptionDecodingPlan(languageCode: "zh", shouldDetectLanguage: false)
        )
        XCTAssertFalse(resolver.requiresDetectionBeforeFinalization)

        XCTAssertFalse(resolver.lockDetectedLanguage("en", hasUsableTranscription: true))
        XCTAssertEqual(resolver.resolvedLanguageCode, "zh")
    }

    func testFixedLanguagesNeverEnterDetection() {
        for language in [TranscriptionLanguage.chinese, .english] {
            var resolver = TranscriptionLanguageResolver(selection: language)
            XCTAssertFalse(resolver.decodingPlan.shouldDetectLanguage)
            XCTAssertFalse(resolver.requiresDetectionBeforeFinalization)
            XCTAssertFalse(resolver.lockDetectedLanguage("ja", hasUsableTranscription: true))
            XCTAssertEqual(resolver.resolvedLanguageCode, language.whisperLanguageCode)
        }
    }

    func testCoordinatorPublishesResolvedLanguageOnlyOnce() async {
        let coordinator = RealtimeTranscriptionCoordinator(
            service: LanguageReportingTranscriptionService()
        )
        let eventTask = Task { () -> [String] in
            var languages: [String] = []
            for await event in coordinator.events {
                if case let .languageResolved(languageCode) = event {
                    languages.append(languageCode)
                }
            }
            return languages
        }

        await coordinator.submit(window(start: 0))
        await coordinator.waitUntilIdle()
        await coordinator.submit(window(start: 20))
        await coordinator.waitUntilIdle()
        await coordinator.stop()

        let languages = await eventTask.value
        XCTAssertEqual(languages, ["zh"])
    }

    func testControlTokensAreRemovedAndEmptySegmentsAreDropped() throws {
        XCTAssertEqual(
            TranscriptTextSanitizer.sanitized("  <|en|>Hello<|0.84|>  "),
            "Hello"
        )
        XCTAssertNil(TranscriptTextSanitizer.sanitized("<|zh|> <|0.00|>"))
        XCTAssertEqual(TranscriptTextSanitizer.sanitized("(laughing)"), "(laughing)")

        let cleanedText = try XCTUnwrap(
            TranscriptTextSanitizer.sanitized("<|zh|>测试文稿<|1.20|>")
        )
        let session = makeSession(
            transcriptionLanguage: .automatic,
            detectedLanguageCode: "zh",
            text: cleanedText
        )
        let json = try JSONEncoder().encode(session)
        XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("<|"))

        let exporter = DefaultTranscriptExporter()
        for format in TranscriptExportFormat.allCases {
            let output = try exporter.render(session: session, format: format)
            XCTAssertFalse(output.contains("<|"), "\(format) 导出仍包含控制标记")
        }
    }

    func testLanguagePreferenceDefaultsPersistsAndRejectsInvalidValues() throws {
        let suiteName = "ScreenScribe.TranscriptionLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(TranscriptionLanguage.load(from: defaults), .automatic)
        defaults.set("invalid", forKey: TranscriptionLanguage.userDefaultsKey)
        XCTAssertEqual(TranscriptionLanguage.load(from: defaults), .automatic)

        TranscriptionLanguage.english.persist(in: defaults)
        let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertEqual(TranscriptionLanguage.load(from: reopenedDefaults), .english)
    }

    #if canImport(ScreenScribe)
    @MainActor
    func testAppModelPersistsSelectionAndDisablesItDuringActiveStates() throws {
        let suiteName = "ScreenScribe.AppModelLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(userDefaults: defaults)
        XCTAssertEqual(model.transcriptionLanguage, .automatic)
        XCTAssertFalse(model.isTranscriptionLanguageSelectionDisabled)

        model.transcriptionLanguage = .chinese
        let restartedModel = AppModel(userDefaults: defaults)
        XCTAssertEqual(restartedModel.transcriptionLanguage, .chinese)

        restartedModel.transition(to: .preparing)
        XCTAssertTrue(restartedModel.isTranscriptionLanguageSelectionDisabled)
        restartedModel.transition(to: .recording)
        XCTAssertTrue(restartedModel.isTranscriptionLanguageSelectionDisabled)
        restartedModel.transition(to: .paused)
        XCTAssertTrue(restartedModel.isTranscriptionLanguageSelectionDisabled)
        restartedModel.transition(to: .recording)
        restartedModel.transition(to: .finalizing)
        XCTAssertTrue(restartedModel.isTranscriptionLanguageSelectionDisabled)
        restartedModel.transition(to: .completed)
        XCTAssertFalse(restartedModel.isTranscriptionLanguageSelectionDisabled)
    }
    #endif

    func testSessionLanguageFieldsRoundTripAndOldJSONDefaultsToAutomatic() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let session = makeSession(
            transcriptionLanguage: .automatic,
            detectedLanguageCode: "ZH",
            text: "测试文稿"
        )

        let encoded = try encoder.encode(session)
        let decoded = try decoder.decode(RecordingSession.self, from: encoded)
        XCTAssertEqual(decoded.transcriptionLanguage, .automatic)
        XCTAssertEqual(decoded.detectedLanguageCode, "zh")

        var oldObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        oldObject.removeValue(forKey: "transcriptionLanguage")
        oldObject.removeValue(forKey: "detectedLanguageCode")
        let oldData = try JSONSerialization.data(withJSONObject: oldObject)
        let oldSession = try decoder.decode(RecordingSession.self, from: oldData)
        XCTAssertEqual(oldSession.transcriptionLanguage, .automatic)
        XCTAssertNil(oldSession.detectedLanguageCode)

        oldObject["transcriptionLanguage"] = "invalid"
        let invalidData = try JSONSerialization.data(withJSONObject: oldObject)
        let invalidSession = try decoder.decode(RecordingSession.self, from: invalidData)
        XCTAssertEqual(invalidSession.transcriptionLanguage, .automatic)
    }

    func testLanguageSelectionLocksOnlyInActiveRecordingStates() {
        for state in [
            AppSessionState.preparing,
            .recording,
            .paused,
            .finalizing
        ] {
            XCTAssertTrue(state.locksTranscriptionLanguageSelection)
        }
        for state in [AppSessionState.idle, .completed, .failed] {
            XCTAssertFalse(state.locksTranscriptionLanguageSelection)
        }
    }

    func testSessionLanguageDisplayNames() {
        XCTAssertEqual(
            TranscriptionLanguage.automatic.sessionDisplayName(detectedLanguageCode: nil),
            "自动（检测中）"
        )
        XCTAssertEqual(
            TranscriptionLanguage.automatic.sessionDisplayName(detectedLanguageCode: "zh"),
            "自动（中文）"
        )
        XCTAssertEqual(
            TranscriptionLanguage.automatic.sessionDisplayName(detectedLanguageCode: "en"),
            "自动（英文）"
        )
        XCTAssertEqual(TranscriptionLanguage.chinese.sessionDisplayName(detectedLanguageCode: nil), "中文")
        XCTAssertEqual(TranscriptionLanguage.english.sessionDisplayName(detectedLanguageCode: nil), "英文")
    }

    private func window(start: TimeInterval) -> AudioWindow {
        AudioWindow(
            samples: [Int16](repeating: 1, count: 160_000),
            startTime: start,
            isFinal: false
        )
    }

    private func makeSession(
        transcriptionLanguage: TranscriptionLanguage,
        detectedLanguageCode: String?,
        text: String
    ) -> RecordingSession {
        RecordingSession(
            title: "语言测试",
            source: CaptureSourceSelection(id: "window-1", kind: .window, title: "测试窗口"),
            state: .completed,
            modelID: "small",
            transcriptionLanguage: transcriptionLanguage,
            detectedLanguageCode: detectedLanguageCode,
            segments: [
                TranscriptSegment(
                    startTime: 0,
                    endTime: 1,
                    text: text,
                    status: .confirmed
                )
            ]
        )
    }
}
