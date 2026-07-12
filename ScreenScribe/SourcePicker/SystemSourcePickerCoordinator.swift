import Foundation
@preconcurrency import ScreenCaptureKit

enum SourcePickerError: Error, LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "已取消选择捕获来源"
        case let .failed(message):
            "无法选择捕获来源：\(message)"
        }
    }
}

@MainActor
final class SystemSourcePickerCoordinator: NSObject, @preconcurrency SCContentSharingPickerObserver {
    static let shared = SystemSourcePickerCoordinator()

    private var completion: ((Result<SCContentFilter, Error>) -> Void)?
    private var selectedKind: CaptureSourceKind = .display
    private var isObserving = false

    func present(
        kind: CaptureSourceKind,
        completion: @escaping (Result<SCContentFilter, Error>) -> Void
    ) {
        selectedKind = kind
        self.completion = completion

        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = pickerMode(for: kind)
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            configuration.excludedBundleIDs = [bundleIdentifier]
        }
        picker.configuration = configuration

        if !isObserving {
            picker.add(self)
            isObserving = true
        }
        picker.isActive = true
        picker.present()
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        completion?(.success(filter))
        completion = nil
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        completion?(.failure(SourcePickerError.cancelled))
        completion = nil
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        completion?(.failure(SourcePickerError.failed(error.localizedDescription)))
        completion = nil
    }

    private func pickerMode(for kind: CaptureSourceKind) -> SCContentSharingPickerMode {
        switch kind {
        case .display:
            .singleDisplay
        case .window:
            .singleWindow
        case .application:
            .singleApplication
        }
    }
}
