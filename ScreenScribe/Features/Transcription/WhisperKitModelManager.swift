import Foundation
import WhisperKit

public actor WhisperKitModelManager: ModelManager {
    private let modelsDirectory: URL

    public init(modelsDirectory: URL? = nil) throws {
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

    public func installedModels() async throws -> [ModelDescriptor] {
        [ModelDescriptor.small, .medium].filter { findModelFolder(for: $0) != nil }
    }

    public nonisolated func download(
        _ model: ModelDescriptor
    ) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let directory = await self.modelDirectory()
                    _ = try await WhisperKit.download(
                        variant: model.whisperKitVariant,
                        downloadBase: directory,
                        useBackgroundSession: true
                    ) { progress in
                        continuation.yield(progress.fractionCompleted)
                    }
                    continuation.yield(1)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func delete(_ model: ModelDescriptor) async throws {
        guard let modelFolder = findModelFolder(for: model) else { return }
        try FileManager.default.removeItem(at: modelFolder)
    }

    public func localModelFolder(for model: ModelDescriptor) -> URL? {
        findModelFolder(for: model)
    }

    private func modelDirectory() -> URL {
        modelsDirectory
    }

    private func findModelFolder(for model: ModelDescriptor) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: modelsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            guard url.lastPathComponent == model.whisperKitVariant else { continue }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                return url
            }
        }
        return nil
    }
}
