import Foundation

public struct AudioLevel: Equatable, Sendable {
    public let rms: Float
    public let peak: Float
    public let isSilent: Bool

    public init(rms: Float, peak: Float, isSilent: Bool) {
        self.rms = rms
        self.peak = peak
        self.isSilent = isSilent
    }
}

public struct AudioCaptureFailure: Error, LocalizedError, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public protocol AudioCaptureService: Sendable {
    var levelUpdates: AsyncStream<AudioLevel> { get }
    var pcmUpdates: AsyncStream<[Int16]> { get }
    var failureUpdates: AsyncStream<AudioCaptureFailure> { get }
    func start(outputURL: URL) async throws
    func pause() async throws
    func resume() async throws
    func stop() async throws
}
