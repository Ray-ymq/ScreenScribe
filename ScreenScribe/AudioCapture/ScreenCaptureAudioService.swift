import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

public enum ScreenCaptureAudioError: Error, LocalizedError {
    case alreadyRunning
    case notRunning
    case invalidAudioFormat
    case audioConversionFailed

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: "系统音频捕获已经在运行"
        case .notRunning: "系统音频捕获尚未启动"
        case .invalidAudioFormat: "系统返回了无法处理的音频格式"
        case .audioConversionFailed: "无法将系统音频转换为 16 kHz 单声道 PCM"
        }
    }
}

public final class ScreenCaptureAudioService: NSObject, @unchecked Sendable, AudioCaptureService {
    public let levelUpdates: AsyncStream<AudioLevel>
    public let pcmUpdates: AsyncStream<[Int16]>
    public let failureUpdates: AsyncStream<AudioCaptureFailure>

    private let filter: SCContentFilter
    private let sampleQueue = DispatchQueue(label: "com.ray.ScreenScribe.audio-samples", qos: .userInitiated)
    private let lock = NSLock()
    private let levelContinuation: AsyncStream<AudioLevel>.Continuation
    private let pcmContinuation: AsyncStream<[Int16]>.Continuation
    private let failureContinuation: AsyncStream<AudioCaptureFailure>.Continuation

    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var isPaused = false

    public init(filter: SCContentFilter) {
        self.filter = filter
        (levelUpdates, levelContinuation) = AsyncStream.makeStream(of: AudioLevel.self)
        (pcmUpdates, pcmContinuation) = AsyncStream.makeStream(of: [Int16].self)
        (failureUpdates, failureContinuation) = AsyncStream.makeStream(
            of: AudioCaptureFailure.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        super.init()
    }

    deinit {
        levelContinuation.finish()
        pcmContinuation.finish()
        failureContinuation.finish()
    }

    public func start(outputURL: URL) async throws {
        let running = lock.withLock { stream != nil }
        guard !running else { throw ScreenCaptureAudioError.alreadyRunning }

        let file = try Self.makeAudioFile(at: outputURL)
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = false
        configuration.sampleRate = 16_000
        configuration.channelCount = 1
        configuration.width = 2
        configuration.height = 2
        configuration.queueDepth = 3
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        configuration.streamName = "幕语系统音频"

        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)

        lock.withLock {
            audioFile = file
            stream = newStream
            isPaused = false
        }

        do {
            try await newStream.startCapture()
        } catch {
            lock.withLock {
                audioFile = nil
                stream = nil
            }
            throw error
        }
    }

    public func pause() async throws {
        let activeStream = try currentStream()
        try await activeStream.stopCapture()
        lock.withLock { isPaused = true }
    }

    public func resume() async throws {
        let activeStream = try currentStream()
        let paused = lock.withLock { isPaused }
        guard paused else { return }
        try await activeStream.startCapture()
        lock.withLock { isPaused = false }
    }

    public func stop() async throws {
        let (activeStream, paused) = try lock.withLock { () throws -> (SCStream, Bool) in
            guard let stream else { throw ScreenCaptureAudioError.notRunning }
            return (stream, isPaused)
        }

        if !paused {
            try await activeStream.stopCapture()
        }

        await withCheckedContinuation { continuation in
            sampleQueue.async { continuation.resume() }
        }
        lock.withLock {
            stream = nil
            audioFile = nil
            isPaused = false
        }
    }

    private func currentStream() throws -> SCStream {
        try lock.withLock {
            guard let stream else { throw ScreenCaptureAudioError.notRunning }
            return stream
        }
    }

    private static func makeAudioFile(at url: URL) throws -> AVAudioFile {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw ScreenCaptureAudioError.invalidAudioFormat
        }
        return try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
    }

    private func handleAudio(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }

        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, _ in
                guard
                    let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                    let inputFormat = AVAudioFormat(
                        standardFormatWithSampleRate: description.mSampleRate,
                        channels: description.mChannelsPerFrame
                    ),
                    let inputBuffer = AVAudioPCMBuffer(
                        pcmFormat: inputFormat,
                        bufferListNoCopy: audioBufferList.unsafePointer
                    ),
                    let channelData = inputBuffer.floatChannelData
                else {
                    throw ScreenCaptureAudioError.invalidAudioFormat
                }

                let channels = Int(inputBuffer.format.channelCount)
                let frameCount = Int(inputBuffer.frameLength)
                var interleaved = [Float]()
                interleaved.reserveCapacity(frameCount * channels)
                for frame in 0..<frameCount {
                    for channel in 0..<channels {
                        interleaved.append(channelData[channel][frame])
                    }
                }

                let pcm = try PCMProcessor.downmixAndResample(
                    interleaved: interleaved,
                    channels: channels,
                    inputSampleRate: Int(inputBuffer.format.sampleRate),
                    outputSampleRate: 16_000
                )
                try write(pcm)
                levelContinuation.yield(PCMProcessor.level(samples: pcm))
                pcmContinuation.yield(pcm)
            }
        } catch {
            failureContinuation.yield(
                AudioCaptureFailure(message: "系统音频写入失败：\(error.localizedDescription)")
            )
        }
    }

    private func write(_ pcm: [Int16]) throws {
        guard !pcm.isEmpty else { return }
        guard let file = audioFile else { throw ScreenCaptureAudioError.notRunning }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(pcm.count)
        ), let destination = buffer.int16ChannelData?[0] else {
            throw ScreenCaptureAudioError.audioConversionFailed
        }

        destination.update(from: pcm, count: pcm.count)
        buffer.frameLength = AVAudioFrameCount(pcm.count)
        try file.write(from: buffer)
    }
}

extension ScreenCaptureAudioService: SCStreamOutput {
    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }
        handleAudio(sampleBuffer)
    }
}

extension ScreenCaptureAudioService: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock {
            self.stream = nil
            audioFile = nil
            isPaused = false
        }
        failureContinuation.yield(
            AudioCaptureFailure(message: "系统音频捕获已中断：\(error.localizedDescription)")
        )
    }
}
