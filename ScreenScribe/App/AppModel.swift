import Foundation
import Observation
@preconcurrency import ScreenCaptureKit

@MainActor
@Observable
final class AppModel {
    private(set) var stateMachine = SessionStateMachine()
    var selectedSource: CaptureSourceSelection?
    @ObservationIgnored var selectedContentFilter: SCContentFilter?
    var currentSession: RecordingSession?
    var segments: [TranscriptSegment] = []
    var audioLevel = AudioLevel(rms: 0, peak: 0, isSilent: true)
    var inferenceDelay: TimeInterval = 0
    var finalizationProgress: Double = 0
    var errorMessage: String?
    var defaultModel = ModelDescriptor.small
    var keepOriginalAudio = false
    var terminologyPrompt = ""

    @ObservationIgnored private var audioCapture: ScreenCaptureAudioService?
    @ObservationIgnored private var levelTask: Task<Void, Never>?
    @ObservationIgnored private var pcmTask: Task<Void, Never>?
    @ObservationIgnored private let sessionStorage = try? FileSessionStorageService()
    @ObservationIgnored private var windowPlanner = AudioWindowPlanner()

    var state: AppSessionState { stateMachine.state }

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
        let title: String
        switch kind {
        case .display: title = "所选屏幕"
        case .window: title = "所选窗口"
        case .application: title = "所选应用"
        }
        return title
    }

    func start() {
        guard selectedSource != nil, selectedContentFilter != nil else {
            errorMessage = "请先选择捕获来源"
            return
        }
        transition(to: .preparing)
        Task { await startCapture() }
    }

    func pause() {
        guard state == .recording else { return }
        Task {
            do {
                try await audioCapture?.pause()
                transition(to: .paused)
                await updatePersistedState()
            } catch {
                await fail(error)
            }
        }
    }

    func resume() {
        guard state == .paused else { return }
        Task {
            do {
                try await audioCapture?.resume()
                transition(to: .recording)
                await updatePersistedState()
            } catch {
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
                if let finalWindow = windowPlanner.flush() {
                    // The transcription coordinator will consume this final partial window.
                    _ = finalWindow
                }
                transition(to: .finalizing)
                finalizationProgress = 0
                await updatePersistedState()
            } catch {
                await fail(error)
            }
        }
    }

    private func startCapture() async {
        guard let filter = selectedContentFilter, let source = selectedSource else {
            await fail(SourcePickerError.failed("捕获来源已失效"))
            return
        }

        do {
            let sessionID = UUID()
            let audioURL = try makeTemporaryAudioURL(sessionID: sessionID)
            currentSession = RecordingSession(
                id: sessionID,
                title: source.title,
                source: source,
                state: .preparing,
                modelID: defaultModel.id,
                temporaryAudioPath: audioURL.path
            )
            try await persistCurrentSession()

            let service = ScreenCaptureAudioService(filter: filter)
            audioCapture = service
            observe(service)
            try await service.start(outputURL: audioURL)
            transition(to: .recording)
            await updatePersistedState()
        } catch {
            await fail(error)
        }
    }

    private func observe(_ service: ScreenCaptureAudioService) {
        levelTask?.cancel()
        levelTask = Task { [weak self] in
            for await level in service.levelUpdates {
                guard !Task.isCancelled else { break }
                self?.audioLevel = level
            }
        }

        pcmTask?.cancel()
        pcmTask = Task { [weak self] in
            for await pcm in service.pcmUpdates {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                let windows = windowPlanner.append(pcm)
                // WhisperKit real-time inference is connected in the transcription phase.
                _ = windows
            }
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

    private func updatePersistedState() async {
        guard var session = currentSession else { return }
        session.state = state
        session.updatedAt = Date()
        currentSession = session
        try? await persistCurrentSession()
    }

    private func persistCurrentSession() async throws {
        guard let sessionStorage, let currentSession else { return }
        try await sessionStorage.save(currentSession)
    }

    private func fail(_ error: Error) async {
        errorMessage = error.localizedDescription
        if state.allowsTransition(to: .failed) {
            transition(to: .failed)
        }
        guard var session = currentSession else { return }
        session.state = .failed
        session.failureMessage = error.localizedDescription
        session.updatedAt = Date()
        currentSession = session
        try? await persistCurrentSession()
    }
}
