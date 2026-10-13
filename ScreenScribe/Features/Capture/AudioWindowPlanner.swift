import Foundation

public struct AudioWindow: Equatable, Sendable {
    public let samples: [Int16]
    public let startTime: TimeInterval
    public let isFinal: Bool

    public init(samples: [Int16], startTime: TimeInterval, isFinal: Bool) {
        self.samples = samples
        self.startTime = startTime
        self.isFinal = isFinal
    }

    public func duration(sampleRate: Int) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(samples.count) / TimeInterval(sampleRate)
    }

    public func endTime(sampleRate: Int) -> TimeInterval {
        startTime + duration(sampleRate: sampleRate)
    }
}

/// Creates bounded, overlapping realtime windows without using wall-clock time.
///
/// Once ten seconds of active audio is available, the planner first looks for the
/// closest qualifying silence boundary between eight and ten seconds. If none is
/// available, it waits for the first boundary after ten seconds and hard-cuts at
/// twelve seconds. Pauses therefore do not create gaps in the transcript timeline:
/// only samples passed to `append(_:)` advance it.
public struct AudioWindowPlanner: Sendable {
    public let sampleRate: Int
    public let minimumWindowDuration: TimeInterval
    public let targetWindowDuration: TimeInterval
    public let maximumWindowDuration: TimeInterval
    public let overlapDuration: TimeInterval
    public let silenceThresholdDecibels: Float
    public let minimumSilenceDuration: TimeInterval
    public let analysisFrameDuration: TimeInterval

    private var buffer: [Int16] = []
    private var bufferStartSample = 0

    public init(
        sampleRate: Int = 16_000,
        minimumWindowDuration: TimeInterval = 8,
        targetWindowDuration: TimeInterval = 10,
        maximumWindowDuration: TimeInterval = 12,
        overlapDuration: TimeInterval = 1.5,
        silenceThresholdDecibels: Float = -45,
        minimumSilenceDuration: TimeInterval = 0.3,
        analysisFrameDuration: TimeInterval = 0.01
    ) {
        precondition(sampleRate > 0)
        precondition(minimumWindowDuration > 0)
        precondition(minimumWindowDuration <= targetWindowDuration)
        precondition(targetWindowDuration <= maximumWindowDuration)
        precondition(overlapDuration >= 0 && overlapDuration < minimumWindowDuration)
        precondition(minimumSilenceDuration > 0)
        precondition(analysisFrameDuration > 0)
        self.sampleRate = sampleRate
        self.minimumWindowDuration = minimumWindowDuration
        self.targetWindowDuration = targetWindowDuration
        self.maximumWindowDuration = maximumWindowDuration
        self.overlapDuration = overlapDuration
        self.silenceThresholdDecibels = silenceThresholdDecibels
        self.minimumSilenceDuration = minimumSilenceDuration
        self.analysisFrameDuration = analysisFrameDuration
    }

    /// Compatibility initializer for callers that previously configured a fixed window.
    public init(
        sampleRate: Int = 16_000,
        windowDuration: TimeInterval,
        overlapDuration: TimeInterval = 1.5
    ) {
        self.init(
            sampleRate: sampleRate,
            minimumWindowDuration: windowDuration,
            targetWindowDuration: windowDuration,
            maximumWindowDuration: windowDuration,
            overlapDuration: overlapDuration
        )
    }

    public var bufferedDuration: TimeInterval {
        TimeInterval(buffer.count) / TimeInterval(sampleRate)
    }

    public mutating func append(_ samples: [Int16]) -> [AudioWindow] {
        guard !samples.isEmpty else { return [] }
        buffer.append(contentsOf: samples)
        var windows: [AudioWindow] = []

        while let cutSample = nextCutSample() {
            windows.append(
                AudioWindow(
                    samples: Array(buffer.prefix(cutSample)),
                    startTime: TimeInterval(bufferStartSample) / TimeInterval(sampleRate),
                    isFinal: false
                )
            )

            let overlapSamples = sampleCount(overlapDuration)
            let consumedSamples = max(1, cutSample - overlapSamples)
            buffer.removeFirst(consumedSamples)
            bufferStartSample += consumedSamples
        }

        return windows
    }

    /// Returns the remaining short window for non-realtime callers.
    /// Realtime shutdown deliberately uses `discardRemainder()` instead.
    public mutating func flush() -> AudioWindow? {
        guard !buffer.isEmpty else { return nil }
        let samples = buffer
        let startTime = TimeInterval(bufferStartSample) / TimeInterval(sampleRate)
        bufferStartSample += buffer.count
        buffer.removeAll(keepingCapacity: true)
        return AudioWindow(samples: samples, startTime: startTime, isFinal: true)
    }

    public mutating func discardRemainder() {
        bufferStartSample += buffer.count
        buffer.removeAll(keepingCapacity: true)
    }

    private func nextCutSample() -> Int? {
        let minimumSamples = sampleCount(minimumWindowDuration)
        let targetSamples = sampleCount(targetWindowDuration)
        let maximumSamples = sampleCount(maximumWindowDuration)
        guard buffer.count >= targetSamples else { return nil }

        let searchableEnd = min(buffer.count, maximumSamples)
        let boundaries = silenceBoundaries(upTo: searchableEnd)

        if let beforeTarget = boundaries
            .filter({ $0 >= minimumSamples && $0 <= targetSamples })
            .max() {
            return beforeTarget
        }

        if let afterTarget = boundaries.first(where: { $0 > targetSamples && $0 <= maximumSamples }) {
            return afterTarget
        }

        if buffer.count >= maximumSamples {
            return maximumSamples
        }
        return nil
    }

    private func silenceBoundaries(upTo limit: Int) -> [Int] {
        let frameSamples = max(1, sampleCount(analysisFrameDuration))
        let requiredSilentSamples = max(1, sampleCount(minimumSilenceDuration))
        let linearThreshold = pow(10, silenceThresholdDecibels / 20)
        let scale = Float(Int16.max)
        var boundaries: [Int] = []
        var silentRunStart: Int?
        var frameStart = 0

        while frameStart < limit {
            let frameEnd = min(frameStart + frameSamples, limit)
            var sumOfSquares: Double = 0
            for index in frameStart..<frameEnd {
                let normalized = Float(buffer[index]) / scale
                sumOfSquares += Double(normalized * normalized)
            }
            let rms = sqrt(sumOfSquares / Double(frameEnd - frameStart))
            let isSilent = Float(rms) < linearThreshold

            if isSilent {
                if silentRunStart == nil { silentRunStart = frameStart }
                if let silentRunStart, frameEnd - silentRunStart >= requiredSilentSamples {
                    boundaries.append(frameEnd)
                }
            } else {
                silentRunStart = nil
            }
            frameStart = frameEnd
        }

        return boundaries
    }

    private func sampleCount(_ duration: TimeInterval) -> Int {
        Int((duration * TimeInterval(sampleRate)).rounded())
    }
}
