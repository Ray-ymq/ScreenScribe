import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var stateMachine = SessionStateMachine()
    var selectedSource: CaptureSourceSelection?
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

    func choosePlaceholderSource(kind: CaptureSourceKind) {
        let title: String
        switch kind {
        case .display: title = "整屏"
        case .window: title = "单窗口"
        case .application: title = "单应用"
        }
        selectedSource = CaptureSourceSelection(id: "placeholder-\(kind.rawValue)", kind: kind, title: title)
    }

    func start() {
        guard selectedSource != nil else {
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

