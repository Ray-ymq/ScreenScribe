import XCTest
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

    private func temporaryModelsDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ScreenScribeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
