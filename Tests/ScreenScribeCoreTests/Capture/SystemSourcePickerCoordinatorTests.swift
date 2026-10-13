import XCTest

#if canImport(ScreenScribe)
@testable import ScreenScribe

final class SystemSourcePickerCoordinatorTests: XCTestCase {
    func testObserverCallbackCanArriveOffMainQueue() async {
        let coordinator = await MainActor.run {
            SystemSourcePickerCoordinator.shared
        }

        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                coordinator.contentSharingPickerStartDidFailWithError(
                    SourcePickerCallbackTestError.expected
                )
                continuation.resume()
            }
        }

        await Task.yield()
    }
}

private enum SourcePickerCallbackTestError: Error {
    case expected
}
#endif
