import Foundation

public protocol SessionStorageService: Sendable {
    func save(_ session: RecordingSession) async throws
    func load(id: UUID) async throws -> RecordingSession
    func list() async throws -> [RecordingSession]
    func delete(id: UUID) async throws
}

public enum SessionStorageError: Error {
    case sessionNotFound(UUID)
}

public actor FileSessionStorageService: SessionStorageService {
    private let sessionsDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL? = nil) throws {
        let fileManager = FileManager.default
        let root = try baseDirectory ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "ScreenScribe", directoryHint: .isDirectory)

        sessionsDirectory = root.appending(path: "Sessions", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func save(_ session: RecordingSession) async throws {
        let data = try encoder.encode(session)
        try data.write(to: url(for: session.id), options: .atomic)
    }

    public func load(id: UUID) async throws -> RecordingSession {
        let fileURL = url(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SessionStorageError.sessionNotFound(id)
        }
        return try decoder.decode(RecordingSession.self, from: Data(contentsOf: fileURL))
    }

    public func list() async throws -> [RecordingSession] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        return try urls
            .map { try decoder.decode(RecordingSession.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func delete(id: UUID) async throws {
        let fileURL = url(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func url(for id: UUID) -> URL {
        sessionsDirectory.appending(path: id.uuidString).appendingPathExtension("json")
    }
}

