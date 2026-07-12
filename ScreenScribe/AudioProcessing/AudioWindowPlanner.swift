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
}

public struct AudioWindowPlanner: Sendable {
    public let sampleRate: Int
    public let windowDuration: TimeInterval
    public let overlapDuration: TimeInterval

    private var buffer: [Int16] = []
    private var startSample = 0

    public init(
        sampleRate: Int = 16_000,
        windowDuration: TimeInterval = 10,
        overlapDuration: TimeInterval = 1.5
    ) {
        precondition(sampleRate > 0)
        precondition(windowDuration > 0)
        precondition(overlapDuration >= 0 && overlapDuration < windowDuration)
        self.sampleRate = sampleRate
        self.windowDuration = windowDuration
        self.overlapDuration = overlapDuration
    }

    public mutating func append(_ samples: [Int16]) -> [AudioWindow] {
        buffer.append(contentsOf: samples)
        let windowSamples = Int(windowDuration * Double(sampleRate))
        let overlapSamples = Int(overlapDuration * Double(sampleRate))
        let hopSamples = windowSamples - overlapSamples
        var windows: [AudioWindow] = []

        while buffer.count >= windowSamples {
            windows.append(
                AudioWindow(
                    samples: Array(buffer.prefix(windowSamples)),
                    startTime: Double(startSample) / Double(sampleRate),
                    isFinal: false
                )
            )
            buffer.removeFirst(hopSamples)
            startSample += hopSamples
        }

        return windows
    }

    public mutating func flush() -> AudioWindow? {
        guard !buffer.isEmpty else { return nil }
        defer {
            startSample += buffer.count
            buffer.removeAll(keepingCapacity: true)
        }
        return AudioWindow(
            samples: buffer,
            startTime: Double(startSample) / Double(sampleRate),
            isFinal: true
        )
    }
}

