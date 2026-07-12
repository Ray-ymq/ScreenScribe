import Foundation
import Observation
@preconcurrency import ScreenCaptureKit

@MainActor
@Observable
final class AppModel {
    private(set) var stateMachine = SessionStateMachine()
    var selectedSource: CaptureSourceSelection?
    @ObservationIgnored var selectedContentFilter: SCContentFilter?
    var segments: [TranscriptSegment] = []
    var audioLevel = AudioLevel(rms: 0, peak: 0, isSilent: true)
    var inferenceDelay: TimeInterval = 0
    var finalizationProgress: Double = 0
    var errorMessage: String?
    var defaultModel = ModelDescriptor.small
    var keepOriginalAudio = false
    var terminologyPrompt = ""

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
        transition(to: .recording)
    }

    func pause() { transition(to: .paused) }
    func resume() { transition(to: .recording) }

    func stop() {
        transition(to: .finalizing)
        finalizationProgress = 0
    }
}
