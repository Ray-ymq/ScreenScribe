import Foundation
import Observation
@preconcurrency import ScreenCaptureKit

private enum AppPipelineError: Error, LocalizedError {
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "无法打开会话存储目录"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var stateMachine = SessionStateMachine()
    var selectedSource: CaptureSourceSelection?
    @ObservationIgnored var selectedContentFilter: SCContentFilter?
    var currentSession: RecordingSession?
    var segments: [TranscriptSegment] = []
    var audioLevel = AudioLevel(rms: 0, peak: 0, isSilent: true)
    var realtimeMode: RealtimeTranscriptionMode = .live
    var realtimeMetrics = RealtimeTranscriptionMetrics()
    var realtimeNotice: String?
    var requiresModelDownload = false
    var finalizationProgress: Double = 0
    var errorMessage: String?
    var defaultModel = ModelDescriptor.small
    var transcriptionLanguage: TranscriptionLanguage {
        didSet {
            guard transcriptionLanguage != oldValue else { return }
            transcriptionLanguage.persist(in: userDefaults)
        }
    }
    var keepOriginalAudio = false
    var terminologyPrompt = ""
    var installedModelIDs: Set<String> = []
    var modelDownloadProgress: [String: Double] = [:]

    @ObservationIgnored private var audioCapture: ScreenCaptureAudioService?
    @ObservationIgnored private var levelTask: Task<Void, Never>?
    @ObservationIgnored private var pcmTask: Task<Void, Never>?
    @ObservationIgnored private var captureFailureTask: Task<Void, Never>?
    @ObservationIgnored private var realtimeEventTask: Task<Void, Never>?
    @ObservationIgnored private var realtimePersistenceTask: Task<Void, Never>?
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let sessionStorage = try? FileSessionStorageService()
    @ObservationIgnored private let modelManager = try? WhisperKitModelManager()
    @ObservationIgnored private var realtimeCoordinator: RealtimeTranscriptionCoordinator?
    private var activeTranscriptionLanguage: TranscriptionLanguage?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        transcriptionLanguage = TranscriptionLanguage.load(from: userDefaults)
        Task { await refreshInstalledModels() }
    }

    var state: AppSessionState { stateMachine.state }
    var paragraphs: [TranscriptParagraph] {
        TranscriptParagraphComposer().compose(segments: segments)
    }
    var isDefaultModelInstalled: Bool { installedModelIDs.contains(defaultModel.id) }
    var isTranscriptionLanguageSelectionDisabled: Bool {
        state.locksTranscriptionLanguageSelection
    }
    var displayedTranscriptionLanguage: String {
        let selection = currentSession?.transcriptionLanguage
            ?? activeTranscriptionLanguage
            ?? transcriptionLanguage
        return selection.sessionDisplayName(
            detectedLanguageCode: currentSession?.detectedLanguageCode
        )
    }

    func transition(to next: AppSessionState) {
        do {
            try stateMachine.transition(to: next)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseSource(kind: CaptureSourceKind) {
        SystemSourcePickerCoordinator.shared.present(kind: kind) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(filter):
                self.selectedContentFilter = filter
                self.selectedSource = CaptureSourceSelection(
                    id: UUID().uuidString,
                    kind: kind,
                    title: self.sourceTitle(kind)
                )
                self.errorMessage = nil
            case let .failure(error as SourcePickerError):
                if case .cancelled = error { return }
                self.errorMessage = error.localizedDescription
            case let .failure(error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func sourceTitle(_ kind: CaptureSourceKind) -> String {
        switch kind {
        case .display: "所选屏幕"
        case .window: "所选窗口"
        case .application: "所选应用"
        }
    }

    func start() {
        guard selectedSource != nil, selectedContentFilter != nil else {
            errorMessage = "请先选择捕获来源"
            return
        }
        guard isDefaultModelInstalled else {
            requiresModelDownload = true
            errorMessage = "尚未安装\(defaultModel.displayName)，请打开设置下载后再开始录制。"
            return
        }
        guard state == .idle || state == .completed || state == .failed else { return }

        if state == .completed || state == .failed {
            transition(to: .idle)
        }
        segments = []
        currentSession = nil
        realtimeNotice = nil
        realtimeMode = .live
        realtimeMetrics = RealtimeTranscriptionMetrics()
        requiresModelDownload = false
        let languageForSession = transcriptionLanguage
        activeTranscriptionLanguage = languageForSession
        transition(to: .preparing)
        Task { await startCapture(transcriptionLanguage: languageForSession) }
    }

    func pause() {
        guard state == .recording else { return }
        Task {
            do {
                try await audioCapture?.pause()
                await realtimeCoordinator?.pause()
                transition(to: .paused)
                try await updatePersistedState()
            } catch {
                await stopPipelineAfterFatalError()
                await fail(error)
            }
        }
    }

    func resume() {
        guard state == .paused else { return }
        Task {
            do {
                await realtimeCoordinator?.resume()
                try await audioCapture?.resume()
                transition(to: .recording)
                try await updatePersistedState()
            } catch {
                await realtimeCoordinator?.pause()
                await stopPipelineAfterFatalError()
                await fail(error)
            }
        }
    }

    func stop() {
        guard state == .recording || state == .paused else { return }
        Task {
            do {
                try await audioCapture?.stop()
                levelTask?.cancel()
                pcmTask?.cancel()
                captureFailureTask?.cancel()
                await realtimeCoordinator?.stop()
                await realtimeEventTask?.value
                await realtimePersistenceTask?.value
                transition(to: .finalizing)
                finalizationProgress = 0
                try await updatePersistedState()
                await finalizeTranscription()
            } catch {
                await stopPipelineAfterFatalError()
                await fail(error)
            }
        }
    }

    private func startCapture(transcriptionLanguage: TranscriptionLanguage) async {
        guard let filter = selectedContentFilter, let source = selectedSource else {
            await fail(SourcePickerError.failed("捕获来源已失效"))
            return
        }

        let transcription: WhisperKitTranscriptionService
        do {
            transcription = try WhisperKitTranscriptionService(
                model: defaultModel,
                transcriptionLanguage: transcriptionLanguage
            )
            try await transcription.prepare()
        } catch {
            await handleModelPreparationFailure(error)
            return
        }

        do {
            guard sessionStorage != nil else { throw AppPipelineError.storageUnavailable }

            let coordinator = RealtimeTranscriptionCoordinator(service: transcription)
            await coordinator.setResultHandler { [weak self] incoming in
                await self?.mergeRealtime(incoming)
            }

            let sessionID = UUID()
            let audioURL = try makeTemporaryAudioURL(sessionID: sessionID)
            currentSession = RecordingSession(
                id: sessionID,
                title: source.title,
                source: source,
                state: .preparing,
                modelID: defaultModel.id,
                transcriptionLanguage: transcriptionLanguage,
                temporaryAudioPath: audioURL.path
            )
            try await persistCurrentSession()

            let capture = ScreenCaptureAudioService(filter: filter)
            realtimeCoordinator = coordinator
            audioCapture = capture
            observe(capture, coordinator: coordinator)

            // Model loading and prewarming have completed before SCStream starts here.
            try await capture.start(outputURL: audioURL)
            transition(to: .recording)
            try await updatePersistedState()
        } catch {
            await stopPipelineAfterFatalError()
            await fail(error)
        }
    }

    private func observe(
        _ service: ScreenCaptureAudioService,
        coordinator: RealtimeTranscriptionCoordinator
    ) {
        levelTask?.cancel()
        levelTask = Task { [weak self] in
            for await level in service.levelUpdates {
                guard !Task.isCancelled else { break }
                self?.audioLevel = level
            }
        }

        pcmTask?.cancel()
        pcmTask = Task {
            for await pcm in service.pcmUpdates {
                guard !Task.isCancelled else { break }
                await coordinator.append(pcm)
            }
        }

        captureFailureTask?.cancel()
        captureFailureTask = Task { [weak self] in
            for await failure in service.failureUpdates {
                guard !Task.isCancelled else { break }
                await self?.handleCaptureFailure(failure)
                break
            }
        }

        realtimeEventTask?.cancel()
        realtimeEventTask = Task { [weak self] in
            for await event in coordinator.events {
                guard !Task.isCancelled else { break }
                self?.applyRealtimeEvent(event)
            }
        }
    }

    func downloadModel(_ model: ModelDescriptor) {
        guard modelDownloadProgress[model.id] == nil, let modelManager else { return }
        modelDownloadProgress[model.id] = 0
        Task {
            do {
                for try await progress in modelManager.download(model) {
                    modelDownloadProgress[model.id] = progress
                }
                modelDownloadProgress[model.id] = nil
                await refreshInstalledModels()
                if model == defaultModel, installedModelIDs.contains(model.id) {
                    requiresModelDownload = false
                    errorMessage = nil
                }
            } catch {
                modelDownloadProgress[model.id] = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteModel(_ model: ModelDescriptor) {
        guard let modelManager else { return }
        Task {
            do {
                try await modelManager.delete(model)
                await refreshInstalledModels()
                if defaultModel == model {
                    requiresModelDownload = true
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshInstalledModels() async {
        guard let modelManager else { return }
        do {
            installedModelIDs = Set(try await modelManager.installedModels().map(\.id))
            if installedModelIDs.contains(defaultModel.id) {
                requiresModelDownload = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mergeRealtime(_ incoming: [TranscriptSegment]) {
        segments = RealtimeTranscriptMerger().merge(existing: segments, incoming: incoming)
        guard var session = currentSession else { return }
        session.segments = segments
        session.updatedAt = Date()
        currentSession = session
        enqueueRealtimePersistence(session)
    }

    private func enqueueRealtimePersistence(_ session: RecordingSession) {
        guard let sessionStorage else {
            Task { await handlePersistenceFailure(AppPipelineError.storageUnavailable) }
            return
        }
        let precedingTask = realtimePersistenceTask
        realtimePersistenceTask = Task { [weak self] in
            await precedingTask?.value
            do {
                try await sessionStorage.save(session)
            } catch {
                await self?.handlePersistenceFailure(error)
            }
        }
    }

    private func applyRealtimeEvent(_ event: RealtimeTranscriptionEvent) {
        switch event {
        case let .modeChanged(mode):
            realtimeMode = mode
            switch mode {
            case .live:
                realtimeNotice = nil
            case .throttled:
                realtimeNotice = "实时转写已降频，完整音频仍在持续保存。"
            case .suspended:
                realtimeNotice = "实时转写已暂停，将按有效音频每 30 秒探测恢复；完整音频仍在保存。"
            }
        case let .metricsUpdated(metrics):
            realtimeMetrics = metrics
        case let .nonfatalFailure(message):
            realtimeNotice = "实时转写暂不可用：\(message)。完整音频仍在保存。"
        case let .languageResolved(languageCode):
            applyResolvedLanguage(languageCode, persistImmediately: true)
        }
    }

    private func finalizeTranscription() async {
        guard
            let realtimeCoordinator,
            let audioPath = currentSession?.temporaryAudioPath
        else {
            await fail(ScreenCaptureAudioError.notRunning)
            return
        }

        do {
            finalizationProgress = 0.1
            let refinedSegments = await realtimeCoordinator.refine(
                audioURL: URL(filePath: audioPath)
            )
            for try await refined in refinedSegments {
                let result = TranscriptReconciler().reconcile(existing: segments, refined: refined)
                segments = result.segments
                if var session = currentSession {
                    session.segments = result.segments
                    session.conflicts = result.conflicts
                    currentSession = session
                }
                finalizationProgress = 0.9
            }
            await updateResolvedLanguageFromCoordinator()
            if var session = currentSession {
                session.state = .completed
                session.updatedAt = Date()
                if !keepOriginalAudio {
                    session.temporaryAudioPath = nil
                }
                currentSession = session
            }
            try await persistCurrentSession()
            transition(to: .completed)
            finalizationProgress = 1
            if !keepOriginalAudio {
                try? FileManager.default.removeItem(atPath: audioPath)
            }
            releaseCompletedPipeline()
        } catch {
            await fail(error)
        }
    }

    private func handleModelPreparationFailure(_ error: Error) async {
        realtimeCoordinator = nil
        if state == .preparing {
            transition(to: .idle)
        }
        activeTranscriptionLanguage = nil
        requiresModelDownload = true
        errorMessage = error.localizedDescription
        await refreshInstalledModels()
    }

    private func handleCaptureFailure(_ failure: AudioCaptureFailure) async {
        guard state == .recording || state == .paused else { return }
        await stopPipelineAfterFatalError()
        await fail(failure)
    }

    private func handlePersistenceFailure(_ error: Error) async {
        guard state == .recording || state == .paused else { return }
        await stopPipelineAfterFatalError()
        await fail(error)
    }

    private func stopPipelineAfterFatalError() async {
        levelTask?.cancel()
        pcmTask?.cancel()
        captureFailureTask?.cancel()
        try? await audioCapture?.stop()
        await realtimeCoordinator?.stop()
    }

    private func releaseCompletedPipeline() {
        levelTask = nil
        pcmTask = nil
        captureFailureTask = nil
        realtimeEventTask = nil
        realtimePersistenceTask = nil
        audioCapture = nil
        realtimeCoordinator = nil
    }

    private func updateResolvedLanguageFromCoordinator() async {
        guard let languageCode = await realtimeCoordinator?.resolvedLanguageCode() else { return }
        applyResolvedLanguage(languageCode, persistImmediately: false)
    }

    private func applyResolvedLanguage(
        _ languageCode: String,
        persistImmediately: Bool
    ) {
        guard
            var session = currentSession,
            session.transcriptionLanguage == .automatic,
            let normalizedCode = TranscriptionLanguage.normalizedLanguageCode(languageCode),
            session.detectedLanguageCode != normalizedCode
        else {
            return
        }
        session.detectedLanguageCode = normalizedCode
        session.updatedAt = Date()
        currentSession = session
        if persistImmediately {
            enqueueRealtimePersistence(session)
        }
    }

    private func makeTemporaryAudioURL(sessionID: UUID) throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "ScreenScribe", directoryHint: .isDirectory)
        let directory = root
            .appending(path: "Sessions", directoryHint: .isDirectory)
            .appending(path: sessionID.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "temporary-audio.caf")
    }

    private func updatePersistedState() async throws {
        guard var session = currentSession else { return }
        session.state = state
        session.updatedAt = Date()
        currentSession = session
        try await persistCurrentSession()
    }

    private func persistCurrentSession() async throws {
        guard let sessionStorage else { throw AppPipelineError.storageUnavailable }
        guard let currentSession else { return }
        try await sessionStorage.save(currentSession)
    }

    private func fail(_ error: Error) async {
        if state.allowsTransition(to: .failed) {
            transition(to: .failed)
        }
        errorMessage = error.localizedDescription
        guard var session = currentSession else { return }
        session.state = .failed
        session.failureMessage = error.localizedDescription
        session.updatedAt = Date()
        currentSession = session
        try? await persistCurrentSession()
    }
}
