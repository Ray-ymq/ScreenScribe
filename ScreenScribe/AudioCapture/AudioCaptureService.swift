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

public protocol AudioCaptureService: Sendable {
    var levelUpdates: AsyncStream<AudioLevel> { get }
    func start(source: CaptureSourceSelection, outputURL: URL) async throws
    func pause() async throws
    func resume() async throws
    func stop() async throws
}

