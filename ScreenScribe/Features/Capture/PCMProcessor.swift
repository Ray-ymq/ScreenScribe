import Foundation

public enum PCMProcessingError: Error, Equatable {
    case invalidChannelCount
    case invalidSampleRate
    case incompleteFrame
}

public enum PCMProcessor {
    public static func downmixAndResample(
        interleaved samples: [Float],
        channels: Int,
        inputSampleRate: Int,
        outputSampleRate: Int = 16_000
    ) throws -> [Int16] {
        guard channels > 0 else { throw PCMProcessingError.invalidChannelCount }
        guard inputSampleRate > 0, outputSampleRate > 0 else {
            throw PCMProcessingError.invalidSampleRate
        }
        guard samples.count.isMultiple(of: channels) else {
            throw PCMProcessingError.incompleteFrame
        }
        guard !samples.isEmpty else { return [] }

        let frameCount = samples.count / channels
        var mono = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            var sum: Float = 0
            let base = frame * channels
            for channel in 0..<channels {
                sum += samples[base + channel]
            }
            mono[frame] = sum / Float(channels)
        }

        let ratio = Double(outputSampleRate) / Double(inputSampleRate)
        let outputCount = max(1, Int((Double(frameCount) * ratio).rounded(.down)))
        var output = [Int16]()
        output.reserveCapacity(outputCount)

        for outputIndex in 0..<outputCount {
            let inputPosition = Double(outputIndex) / ratio
            let lowerIndex = min(Int(inputPosition), frameCount - 1)
            let upperIndex = min(lowerIndex + 1, frameCount - 1)
            let fraction = Float(inputPosition - Double(lowerIndex))
            let interpolated = mono[lowerIndex] + (mono[upperIndex] - mono[lowerIndex]) * fraction
            output.append(int16(from: interpolated))
        }

        return output
    }

    public static func level(
        samples: [Int16],
        silenceThresholdDecibels: Float = -45
    ) -> AudioLevel {
        guard !samples.isEmpty else {
            return AudioLevel(rms: 0, peak: 0, isSilent: true)
        }

        let scale = Float(Int16.max)
        var sumOfSquares: Double = 0
        var peak: Float = 0

        for sample in samples {
            let normalized = abs(Float(sample) / scale)
            peak = max(peak, normalized)
            sumOfSquares += Double(normalized * normalized)
        }

        let rms = Float(sqrt(sumOfSquares / Double(samples.count)))
        let decibels = rms > 0 ? 20 * log10(rms) : -.infinity
        return AudioLevel(rms: rms, peak: peak, isSilent: decibels < silenceThresholdDecibels)
    }

    private static func int16(from sample: Float) -> Int16 {
        let clamped = min(1, max(-1, sample))
        if clamped == -1 { return Int16.min }
        return Int16((clamped * Float(Int16.max)).rounded())
    }
}

