import XCTest
#if canImport(ScreenScribeCore)
@testable import ScreenScribeCore
#elseif canImport(ScreenScribe)
@testable import ScreenScribe
#endif

final class AudioWindowPlannerTests: XCTestCase {
    private let sampleRate = 100
    private let loud = Int16(4_000)

    func testCutsAtClosestSilenceBeforeTarget() {
        var planner = makePlanner()
        var samples = [Int16](repeating: loud, count: 1_000)
        samples.replaceSubrange(920..<960, with: repeatElement(0, count: 40))

        let windows = planner.append(samples)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].samples.count, 960)
        XCTAssertEqual(windows[0].startTime, 0, accuracy: 0.001)
        XCTAssertEqual(planner.bufferedDuration, 1.9, accuracy: 0.001)
    }

    func testWaitsForFirstSilenceAfterTarget() {
        var planner = makePlanner()

        XCTAssertTrue(planner.append([Int16](repeating: loud, count: 1_000)).isEmpty)
        let windows = planner.append([Int16](repeating: 0, count: 30))

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].samples.count, 1_030)
    }

    func testHardCutsAtTwelveSeconds() {
        var planner = makePlanner()
        let windows = planner.append([Int16](repeating: loud, count: 1_200))

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].samples.count, 1_200)
    }

    func testMaintainsOnePointFiveSecondOverlapAndSampleTimeline() {
        var planner = makePlanner()
        let windows = planner.append([Int16](repeating: loud, count: 2_250))

        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].startTime, 0, accuracy: 0.001)
        XCTAssertEqual(windows[1].startTime, 10.5, accuracy: 0.001)
        XCTAssertEqual(windows[0].samples.suffix(150), windows[1].samples.prefix(150))
    }

    func testDiscardRemainderDoesNotCreateShortRealtimeWindow() {
        var planner = makePlanner()
        XCTAssertTrue(planner.append([Int16](repeating: loud, count: 700)).isEmpty)

        planner.discardRemainder()

        XCTAssertEqual(planner.bufferedDuration, 0)
    }

    private func makePlanner() -> AudioWindowPlanner {
        AudioWindowPlanner(
            sampleRate: sampleRate,
            minimumWindowDuration: 8,
            targetWindowDuration: 10,
            maximumWindowDuration: 12,
            overlapDuration: 1.5,
            silenceThresholdDecibels: -45,
            minimumSilenceDuration: 0.3,
            analysisFrameDuration: 0.01
        )
    }
}
