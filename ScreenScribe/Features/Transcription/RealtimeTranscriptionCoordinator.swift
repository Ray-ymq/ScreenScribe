import Foundation

public enum RealtimeTranscriptionMode: String, Codable, CaseIterable, Sendable {
    case live
    case throttled
    case suspended
}

public struct RealtimeTranscriptionPolicy: Equatable, Sendable {
    public let liveLatencyLimit: TimeInterval
    public let suspendedLatencyLimit: TimeInterval
    public let throttledSubmissionInterval: TimeInterval
    public let probeAudioInterval: TimeInterval
    public let probeRecoveryLatencyLimit: TimeInterval
    public let failureLimit: Int
    public let slowInferenceLimit: Int
    public let liveRecoverySuccessCount: Int

    public init(
        liveLatencyLimit: TimeInterval = 5,
        suspendedLatencyLimit: TimeInterval = 15,
        throttledSubmissionInterval: TimeInterval = 17,
        probeAudioInterval: TimeInterval = 30,
        probeRecoveryLatencyLimit: TimeInterval = 10,
        failureLimit: Int = 3,
        slowInferenceLimit: Int = 2,
        liveRecoverySuccessCount: Int = 2
    ) {
        precondition(liveLatencyLimit > 0)
        precondition(suspendedLatencyLimit > liveLatencyLimit)
        precondition(throttledSubmissionInterval > 0)
        precondition(probeAudioInterval > 0)
        precondition(probeRecoveryLatencyLimit > 0)
        precondition(failureLimit > 0)
        precondition(slowInferenceLimit > 0)
        precondition(liveRecoverySuccessCount > 0)
        self.liveLatencyLimit = liveLatencyLimit
        self.suspendedLatencyLimit = suspendedLatencyLimit
        self.throttledSubmissionInterval = throttledSubmissionInterval
        self.probeAudioInterval = probeAudioInterval
        self.probeRecoveryLatencyLimit = probeRecoveryLatencyLimit
        self.failureLimit = failureLimit
        self.slowInferenceLimit = slowInferenceLimit
        self.liveRecoverySuccessCount = liveRecoverySuccessCount
    }

    public static let `default` = RealtimeTranscriptionPolicy()
}

public struct RealtimeTranscriptionMetrics: Equatable, Sendable {
    public var queueDuration: TimeInterval
    public var inferenceDuration: TimeInterval
    public var submissionToDisplayDuration: TimeInterval
    public var skippedWindowCount: Int
    public var consecutiveFailureCount: Int

    public init(
        queueDuration: TimeInterval = 0,
        inferenceDuration: TimeInterval = 0,
        submissionToDisplayDuration: TimeInterval = 0,
        skippedWindowCount: Int = 0,
        consecutiveFailureCount: Int = 0
    ) {
        self.queueDuration = queueDuration
        self.inferenceDuration = inferenceDuration
        self.submissionToDisplayDuration = submissionToDisplayDuration
        self.skippedWindowCount = skippedWindowCount
        self.consecutiveFailureCount = consecutiveFailureCount
    }
}

public enum RealtimeTranscriptionEvent: Equatable, Sendable {
    case modeChanged(RealtimeTranscriptionMode)
    case metricsUpdated(RealtimeTranscriptionMetrics)
    case nonfatalFailure(String)
    case languageResolved(String)
}

public actor RealtimeTranscriptionCoordinator {
    public typealias ResultHandler = @Sendable ([TranscriptSegment]) async -> Void
    public typealias TimeProvider = @Sendable () -> TimeInterval

    public nonisolated let events: AsyncStream<RealtimeTranscriptionEvent>

    private struct WorkItem: Sendable {
        let window: AudioWindow
        let submittedAt: TimeInterval
        let isProbe: Bool
    }

    private let service: any TranscriptionService
    private let policy: RealtimeTranscriptionPolicy
    private let now: TimeProvider
    private let eventContinuation: AsyncStream<RealtimeTranscriptionEvent>.Continuation
    private let sampleRate: Int
    private let overlapDuration: TimeInterval

    private var planner: AudioWindowPlanner
    private var resultHandler: ResultHandler = { _ in }
    private var processingTask: Task<Void, Never>?
    private var currentWork: WorkItem?
    private var pendingWork: WorkItem?
    private var mode: RealtimeTranscriptionMode = .live
    private var metrics = RealtimeTranscriptionMetrics()
    private var isPaused = false
    private var isStopping = false
    private var slowInferenceCount = 0
    private var liveRecoverySuccessCount = 0
    private var lastObservedAudioEnd: TimeInterval = 0
    private var lastStartedAudioEnd: TimeInterval?
    private var nextProbeAudioEnd: TimeInterval?
    private var lastPublishedLanguageCode: String?

    public init(
        service: any TranscriptionService,
        planner: AudioWindowPlanner = AudioWindowPlanner(),
        policy: RealtimeTranscriptionPolicy = .default,
        now: @escaping TimeProvider = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.service = service
        self.planner = planner
        self.policy = policy
        self.now = now
        sampleRate = planner.sampleRate
        overlapDuration = planner.overlapDuration
        let stream = AsyncStream.makeStream(
            of: RealtimeTranscriptionEvent.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        events = stream.stream
        eventContinuation = stream.continuation
    }

    deinit {
        eventContinuation.finish()
    }

    public func setResultHandler(_ handler: @escaping ResultHandler) {
        resultHandler = handler
    }

    /// Accepts captured PCM without waiting for inference. Window inference is run by
    /// the coordinator's own processing task and is bounded to one current plus one
    /// latest pending item.
    public func append(_ samples: [Int16]) {
        guard !isPaused, !isStopping else { return }
        for window in planner.append(samples) {
            enqueue(window)
        }
    }

    /// Direct window submission is useful for deterministic policy tests and adapters.
    public func submit(_ window: AudioWindow) {
        guard !isStopping else { return }
        enqueue(window)
    }

    public func pause() {
        isPaused = true
    }

    public func resume() {
        guard !isStopping else { return }
        isPaused = false
    }

    public func currentMode() -> RealtimeTranscriptionMode {
        mode
    }

    public func currentMetrics() -> RealtimeTranscriptionMetrics {
        metrics
    }

    public func queueDepth() -> Int {
        (currentWork == nil ? 0 : 1) + (pendingWork == nil ? 0 : 1)
    }

    /// Runs complete-audio refinement through the same service instance used by the
    /// realtime queue. Call after `stop()` so no realtime inference overlaps it.
    public func refine(
        audioURL: URL
    ) -> AsyncThrowingStream<[TranscriptSegment], Error> {
        service.refine(audioURL: audioURL)
    }

    public func resolvedLanguageCode() async -> String? {
        await service.resolvedLanguageCode()
    }

    public func waitUntilIdle() async {
        while let task = processingTask {
            await task.value
        }
    }

    /// Discards the short rolling remainder and the pending window, then waits for the
    /// already-running inference to finish. The shared transcription service can then
    /// be reused for complete-CAF refinement without loading a second model.
    public func stop() async {
        guard !isStopping else {
            if let processingTask { await processingTask.value }
            return
        }
        isStopping = true
        planner.discardRemainder()
        if pendingWork != nil {
            pendingWork = nil
            recordSkippedWindow()
        }
        if let processingTask {
            await processingTask.value
        }
        eventContinuation.finish()
    }

    private func enqueue(_ window: AudioWindow) {
        let audioEnd = window.endTime(sampleRate: sampleRate)
        lastObservedAudioEnd = max(lastObservedAudioEnd, audioEnd)

        let isProbe: Bool
        switch mode {
        case .suspended:
            let due = nextProbeAudioEnd ?? (lastObservedAudioEnd + policy.probeAudioInterval)
            guard audioEnd >= due else {
                recordSkippedWindow()
                return
            }
            isProbe = true
            nextProbeAudioEnd = audioEnd + policy.probeAudioInterval
        case .throttled:
            if let lastStartedAudioEnd,
               audioEnd - lastStartedAudioEnd < policy.throttledSubmissionInterval {
                recordSkippedWindow()
                return
            }
            isProbe = false
        case .live:
            isProbe = false
        }

        let work = WorkItem(window: window, submittedAt: now(), isProbe: isProbe)
        guard processingTask != nil else {
            startProcessing(with: work)
            return
        }

        if pendingWork != nil {
            pendingWork = work
            recordSkippedWindow()
            if mode == .live {
                changeMode(to: .throttled)
            }
        } else {
            pendingWork = work
        }
    }

    private func startProcessing(with work: WorkItem) {
        processingTask = Task { [weak self] in
            await self?.processLoop(startingWith: work)
        }
    }

    private func processLoop(startingWith firstWork: WorkItem) async {
        var nextWork: WorkItem? = firstWork

        while let work = nextWork {
            if isStopping {
                recordSkippedWindow()
                break
            }

            currentWork = work
            let audioEnd = work.window.endTime(sampleRate: sampleRate)
            lastStartedAudioEnd = audioEnd
            let inferenceStartedAt = now()
            let queueDuration = max(0, inferenceStartedAt - work.submittedAt)

            do {
                let incoming = try await service.transcribeWindow(
                    samples: work.window.samples,
                    sampleRate: sampleRate,
                    offset: work.window.startTime
                )
                let inferenceFinishedAt = now()
                let inferenceDuration = max(0, inferenceFinishedAt - inferenceStartedAt)
                await resultHandler(incoming)
                await publishResolvedLanguageIfNeeded()
                let displayedAt = now()
                handleSuccess(
                    work,
                    queueDuration: queueDuration,
                    inferenceDuration: inferenceDuration,
                    submissionToDisplayDuration: max(0, displayedAt - work.submittedAt)
                )
            } catch {
                let inferenceDuration = max(0, now() - inferenceStartedAt)
                handleFailure(
                    error,
                    work: work,
                    queueDuration: queueDuration,
                    inferenceDuration: inferenceDuration
                )
            }

            currentWork = nil
            if isStopping {
                nextWork = nil
            } else {
                nextWork = takePendingWork()
            }
        }

        currentWork = nil
        processingTask = nil
    }

    private func publishResolvedLanguageIfNeeded() async {
        guard
            let languageCode = await service.resolvedLanguageCode(),
            languageCode != lastPublishedLanguageCode
        else {
            return
        }
        lastPublishedLanguageCode = languageCode
        eventContinuation.yield(.languageResolved(languageCode))
    }

    private func takePendingWork() -> WorkItem? {
        guard let work = pendingWork else { return nil }
        pendingWork = nil

        if mode == .suspended, !work.isProbe {
            recordSkippedWindow()
            return nil
        }
        if mode == .throttled,
           let lastStartedAudioEnd,
           work.window.endTime(sampleRate: sampleRate) - lastStartedAudioEnd
               < policy.throttledSubmissionInterval {
            recordSkippedWindow()
            return nil
        }
        return work
    }

    private func handleSuccess(
        _ work: WorkItem,
        queueDuration: TimeInterval,
        inferenceDuration: TimeInterval,
        submissionToDisplayDuration: TimeInterval
    ) {
        metrics.queueDuration = queueDuration
        metrics.inferenceDuration = inferenceDuration
        metrics.submissionToDisplayDuration = submissionToDisplayDuration
        metrics.consecutiveFailureCount = 0

        let windowStep = max(
            0.001,
            work.window.duration(sampleRate: sampleRate) - overlapDuration
        )
        if inferenceDuration > windowStep {
            slowInferenceCount += 1
        } else {
            slowInferenceCount = 0
        }

        if submissionToDisplayDuration > policy.suspendedLatencyLimit
            || slowInferenceCount >= policy.slowInferenceLimit {
            changeMode(to: .suspended)
            publishMetrics()
            return
        }

        if work.isProbe, mode == .suspended {
            if submissionToDisplayDuration <= policy.probeRecoveryLatencyLimit {
                changeMode(to: .throttled)
                liveRecoverySuccessCount = submissionToDisplayDuration <= policy.liveLatencyLimit ? 1 : 0
            }
            publishMetrics()
            return
        }

        switch mode {
        case .live:
            if submissionToDisplayDuration > policy.liveLatencyLimit {
                liveRecoverySuccessCount = 0
                changeMode(to: .throttled)
            }
        case .throttled:
            if submissionToDisplayDuration <= policy.liveLatencyLimit {
                liveRecoverySuccessCount += 1
                if liveRecoverySuccessCount >= policy.liveRecoverySuccessCount {
                    changeMode(to: .live)
                }
            } else {
                liveRecoverySuccessCount = 0
            }
        case .suspended:
            break
        }
        publishMetrics()
    }

    private func handleFailure(
        _ error: Error,
        work: WorkItem,
        queueDuration: TimeInterval,
        inferenceDuration: TimeInterval
    ) {
        metrics.queueDuration = queueDuration
        metrics.inferenceDuration = inferenceDuration
        metrics.consecutiveFailureCount += 1
        liveRecoverySuccessCount = 0
        eventContinuation.yield(.nonfatalFailure(error.localizedDescription))

        if metrics.consecutiveFailureCount >= policy.failureLimit {
            changeMode(to: .suspended)
        }
        publishMetrics()
    }

    private func recordSkippedWindow() {
        metrics.skippedWindowCount += 1
        publishMetrics()
    }

    private func changeMode(to newMode: RealtimeTranscriptionMode) {
        guard mode != newMode else { return }
        mode = newMode
        switch newMode {
        case .live:
            liveRecoverySuccessCount = 0
            nextProbeAudioEnd = nil
        case .throttled:
            nextProbeAudioEnd = nil
        case .suspended:
            liveRecoverySuccessCount = 0
            slowInferenceCount = 0
            nextProbeAudioEnd = lastObservedAudioEnd + policy.probeAudioInterval
        }
        eventContinuation.yield(.modeChanged(newMode))
    }

    private func publishMetrics() {
        eventContinuation.yield(.metricsUpdated(metrics))
    }
}
