import XCTest
@preconcurrency import ScreenCaptureKit
#if canImport(ScreenScribeCore)
@testable import ScreenScribeCore
#elseif canImport(ScreenScribe)
@testable import ScreenScribe
#endif

final class InstalledModelIntegrationTests: XCTestCase {
    func testMissingModelFailsWithoutStartingDownload() async throws {
        let directory = temporaryModelsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = try WhisperKitTranscriptionService(
            model: .small,
            modelsDirectory: directory
        )

        do {
            try await service.prepare()
            XCTFail("缺少模型时 prepare 不应成功")
        } catch let error as TranscriptionPreparationError {
            guard case let .modelUnavailable(model) = error else {
                return XCTFail("应返回 modelUnavailable，实际为 \(error)")
            }
            XCTAssertEqual(model, .small)
        }

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    func testDamagedModelFailsWithoutRedownloading() async throws {
        let directory = temporaryModelsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let damagedFolder = directory.appending(path: ModelDescriptor.small.whisperKitVariant)
        try FileManager.default.createDirectory(at: damagedFolder, withIntermediateDirectories: true)
        let service = try WhisperKitTranscriptionService(
            model: .small,
            modelsDirectory: directory
        )

        do {
            try await service.prepare()
            XCTFail("损坏模型时 prepare 不应成功")
        } catch let error as TranscriptionPreparationError {
            guard case let .modelDamaged(model, _) = error else {
                return XCTFail("应返回 modelDamaged，实际为 \(error)")
            }
            XCTAssertEqual(model, .small)
        }

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path),
            [ModelDescriptor.small.whisperKitVariant]
        )
    }

    func testInstalledSmallModelCanLoadAndPrewarm() async throws {
        let manager = try WhisperKitModelManager()
        let installed = try await manager.installedModels()
        guard installed.contains(.small) else {
            throw XCTSkip("本机未安装 small 模型")
        }

        let service = try WhisperKitTranscriptionService(model: .small)
        try await service.prepare()
    }

    func testConfiguredChineseAndEnglishAudioSmoke() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            let chinesePath = environment["SCREENSCRIBE_CHINESE_SMOKE_AUDIO"],
            let englishPath = environment["SCREENSCRIBE_ENGLISH_SMOKE_AUDIO"]
        else {
            throw XCTSkip("未配置中英文冒烟音频路径")
        }

        let manager = try WhisperKitModelManager()
        guard try await manager.installedModels().contains(.small) else {
            throw XCTSkip("本机未安装 small 模型")
        }

        try await assertTranscription(
            audioPath: chinesePath,
            selection: .automatic,
            expectedLanguageCode: "zh"
        )
        try await assertTranscription(
            audioPath: englishPath,
            selection: .automatic,
            expectedLanguageCode: "en"
        )
        try await assertTranscription(
            audioPath: chinesePath,
            selection: .chinese,
            expectedLanguageCode: "zh"
        )
        try await assertTranscription(
            audioPath: englishPath,
            selection: .english,
            expectedLanguageCode: "en"
        )
    }

    func testConfiguredSystemAudioRecordingSmoke() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SCREENSCRIBE_CAPTURE_SMOKE"] == "1" else {
            throw XCTSkip("未启用 ScreenCaptureKit 录制冒烟")
        }
        guard
            let chinesePath = environment["SCREENSCRIBE_CHINESE_SMOKE_AUDIO"],
            let englishPath = environment["SCREENSCRIBE_ENGLISH_SMOKE_AUDIO"]
        else {
            throw XCTSkip("未配置中英文冒烟音频路径")
        }

        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let display = try XCTUnwrap(shareableContent.displays.first)
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )

        try await recordAndAssertTranscription(
            sourceAudioPath: chinesePath,
            filter: filter,
            expectedLanguageCode: "zh"
        )
        try await recordAndAssertTranscription(
            sourceAudioPath: englishPath,
            filter: filter,
            expectedLanguageCode: "en"
        )
    }

    private func recordAndAssertTranscription(
        sourceAudioPath: String,
        filter: SCContentFilter,
        expectedLanguageCode: String
    ) async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ScreenScribeCaptureSmoke-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let capture = ScreenCaptureAudioService(filter: filter)
        try await capture.start(outputURL: outputURL)
        do {
            try await playAudio(at: sourceAudioPath)
            try await Task.sleep(for: .milliseconds(500))
            try await capture.stop()
        } catch {
            try? await capture.stop()
            throw error
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let byteCount = try XCTUnwrap(attributes[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(byteCount, 32_000, "ScreenCaptureKit 未写入有效系统音频")
        try await assertTranscription(
            audioPath: outputURL.path,
            selection: .automatic,
            expectedLanguageCode: expectedLanguageCode
        )
    }

    private func playAudio(at path: String) async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/afplay")
        process.arguments = [path]

        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { completedProcess in
                if completedProcess.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: AudioPlaybackError.failed(completedProcess.terminationStatus)
                    )
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func assertTranscription(
        audioPath: String,
        selection: TranscriptionLanguage,
        expectedLanguageCode: String
    ) async throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioPath))
        let service = try WhisperKitTranscriptionService(
            model: .small,
            transcriptionLanguage: selection
        )
        var segments: [TranscriptSegment] = []
        for try await refined in service.refine(audioURL: URL(filePath: audioPath)) {
            segments.append(contentsOf: refined)
        }

        XCTAssertFalse(segments.isEmpty, "\(selection.rawValue) 模式未生成文稿")
        let resolvedLanguageCode = await service.resolvedLanguageCode()
        XCTAssertEqual(resolvedLanguageCode, expectedLanguageCode)
        XCTAssertFalse(
            segments.contains { $0.text.contains("<|") || $0.text.contains("|>") },
            "\(selection.rawValue) 模式仍输出 Whisper 控制标记"
        )
    }

    private func temporaryModelsDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ScreenScribeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

private enum AudioPlaybackError: Error {
    case failed(Int32)
}
