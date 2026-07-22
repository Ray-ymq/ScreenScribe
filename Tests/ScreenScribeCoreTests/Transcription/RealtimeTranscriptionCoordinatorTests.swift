import Foundation
import XCTest
#if canImport(ScreenScribeCore)
@testable import ScreenScribeCore
#elseif canImport(ScreenScribe)
@testable import ScreenScribe
#endif

private final class ManualRealtimeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0

    func now() -> TimeInterval {
        lock.withLock { value }
    }

    func advance(by duration: TimeInterval) {
        lock.withLock { value += duration }
    }
}

private enum MockTranscriptionError: Error {
    case failed
}

private actor ScriptedTranscriptionService: TranscriptionService {
    enum Outcome: Sendable {
        case success(delay: TimeInterval)
        case failure(delay: TimeInterval)
    }

    private let clock: ManualRealtimeClock
    private var outcomes: [Outcome]
    private var offsets: [TimeInterval] = []
    private var completionCount = 0
    private let realDelayNanoseconds: UInt64

    init(
        clock: ManualRealtimeClock,
        outcomes: [Outcome],
        realDelayNanoseconds: UInt64 = 0
    ) {
        self.clock = clock
        self.outcomes = outcomes
        self.realDelayNanoseconds = realDelayNanoseconds
    }

    func prepare() async throws {}

    func transcribeWindow(
        samples: [Int16],
        sampleRate: Int,
        offset: TimeInterval
    ) async throws -> [TranscriptSegment] {
        offsets.append(offset)
        if realDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: realDelayNanoseconds)
        }
        let outcome = outcomes.isEmpty ? .success(delay: 0) : outcomes.removeFirst()
        switch outcome {
        case let .success(delay):
            clock.advance(by: delay)
            completionCount += 1
            return [
                TranscriptSegment(
                    startTime: offset,
                    endTime: offset + 1,
                    text: "window-\(offset)",
                    status: .provisional
                )
            ]
        case let .failure(delay):
            clock.advance(by: delay)
            completionCount += 1
            throw MockTranscriptionError.failed
        }
    }

    nonisolated func refine(
        audioURL: URL
    ) -> AsyncThrowingStream<[TranscriptSegment], Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func recordedOffsets() -> [TimeInterval] { offsets }
    func completedInferences() -> Int { completionCount }
}

final class RealtimeTranscriptionCoordinatorTests: XCTestCase {
    func testLiveThrottledSuspendedProbeAndLiveRecovery() async {
        let clock = ManualRealtimeClock()
        let service = ScriptedTranscriptionService(
            clock: clock,
            outcomes: [
                .success(delay: 6),
                .success(delay: 16),
                .success(delay: 4),
                .success(delay: 4)
            ]
        )
        let coordinator = makeCoordinator(service: service, clock: clock)
        await coordinator.setResultHandler { _ in }

        await coordinator.submit(window(start: 0))
        await coordinator.waitUntilIdle()
        var mode = await coordinator.currentMode()
        XCTAssertEqual(mode, .throttled)

        await coordinator.submit(window(start: 20))
        await coordinator.waitUntilIdle()
        mode = await coordinator.currentMode()
        XCTAssertEqual(mode, .suspended)

        await coordinator.submit(window(start: 50))
        await coordinator.waitUntilIdle()
        mode = await coordinator.currentMode()
        XCTAssertEqual(mode, .throttled)

        await coordinator.submit(window(start: 67))
        await coordinator.waitUntilIdle()
        mode = await coordinator.currentMode()
        XCTAssertEqual(mode, .live)
    }

    func testLatestPendingWindowReplacesStaleWindow() async {
        let clock = ManualRealtimeClock()
        let service = ScriptedTranscriptionService(
            clock: clock,
            outcomes: [.success(delay: 6), .success(delay: 6)],
            realDelayNanoseconds: 80_000_000
        )
        let coordinator = makeCoordinator(service: service, clock: clock)

        await coordinator.submit(window(start: 0))
        await Task.yield()
        await coordinator.submit(window(start: 20))
        await coordinator.submit(window(start: 40))
        await coordinator.waitUntilIdle()

        let offsets = await service.recordedOffsets()
        let metrics = await coordinator.currentMetrics()
        let mode = await coordinator.currentMode()
        let queueDepth = await coordinator.queueDepth()
        XCTAssertEqual(offsets, [0, 40])
        XCTAssertEqual(metrics.skippedWindowCount, 1)
        XCTAssertEqual(metrics.queueDuration, 6, accuracy: 0.001)
        XCTAssertEqual(metrics.inferenceDuration, 6, accuracy: 0.001)
        XCTAssertEqual(metrics.submissionToDisplayDuration, 12, accuracy: 0.001)
        XCTAssertEqual(mode, .throttled)
        XCTAssertLessThanOrEqual(queueDepth, 2)
    }

    func testThreeConsecutiveFailuresSuspendRealtime() async {
        let clock = ManualRealtimeClock()
        let service = ScriptedTranscriptionService(
            clock: clock,
            outcomes: [
                .failure(delay: 1),
                .failure(delay: 1),
                .failure(delay: 1)
            ]
        )
        let coordinator = makeCoordinator(service: service, clock: clock)

        for start in [0.0, 20, 40] {
            await coordinator.submit(window(start: start))
            await coordinator.waitUntilIdle()
        }

        let mode = await coordinator.currentMode()
        let metrics = await coordinator.currentMetrics()
        XCTAssertEqual(mode, .suspended)
        XCTAssertEqual(metrics.consecutiveFailureCount, 3)
    }

    func testTwoSlowInferencesSuspendRealtime() async {
        let clock = ManualRealtimeClock()
        let service = ScriptedTranscriptionService(
            clock: clock,
            outcomes: [.success(delay: 9), .success(delay: 9)]
        )
        let coordinator = makeCoordinator(service: service, clock: clock)

        await coordinator.submit(window(start: 0))
        await coordinator.waitUntilIdle()
        await coordinator.submit(window(start: 20))
        await coordinator.waitUntilIdle()

        let mode = await coordinator.currentMode()
        XCTAssertEqual(mode, .suspended)
    }

    func testPauseDoesNotAdvanceTimelineAndStopDropsShortWindow() async {
        let clock = ManualRealtimeClock()
        let service = ScriptedTranscriptionService(clock: clock, outcomes: [])
        let coordinator = RealtimeTranscriptionCoordinator(
            service: service,
            planner: AudioWindowPlanner(
                sampleRate: 100,
                minimumWindowDuration: 8,
                targetWindowDuration: 10,
                maximumWindowDuration: 12,
                overlapDuration: 1.5,
                minimumSilenceDuration: 0.3,
                analysisFrameDuration: 0.01
            ),
            now: clock.now
        )

        await coordinator.append([Int16](repeating: 4_000, count: 600))
        await coordinator.pause()
        await coordinator.append([Int16](repeating: 4_000, count: 10_000))
        await coordinator.resume()
        await coordinator.append([Int16](repeating: 4_000, count: 600))
        await coordinator.waitUntilIdle()
        await coordinator.stop()

        let offsets = await service.recordedOffsets()
        let queueDepth = await coordinator.queueDepth()
        XCTAssertEqual(offsets, [0])
        XCTAssertEqual(queueDepth, 0)
    }

    func testStopCancelsPendingAndWaitsForCurrentInference() async {
        let clock = ManualRealtimeClock()
        let service = ScriptedTranscriptionService(
            clock: clock,
            outcomes: [.success(delay: 1)],
            realDelayNanoseconds: 80_000_000
        )
        let coordinator = makeCoordinator(service: service, clock: clock)

        await coordinator.submit(window(start: 0))
        while (await service.recordedOffsets()).isEmpty {
            await Task.yield()
        }
        await coordinator.submit(window(start: 20))
        await coordinator.stop()

        let offsets = await service.recordedOffsets()
        let completed = await service.completedInferences()
        let metrics = await coordinator.currentMetrics()
        XCTAssertEqual(offsets, [0])
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(metrics.skippedWindowCount, 1)
    }

    func testRealtimeMergeProtectsUserEditedSegment() {
        let edited = TranscriptSegment(
            startTime: 2,
            endTime: 4,
            text: "用户编辑",
            status: .userEdited
        )
        let incoming = TranscriptSegment(
            startTime: 2.1,
            endTime: 3.9,
            text: "实时覆盖",
            status: .provisional
        )

        let merged = RealtimeTranscriptMerger().merge(existing: [edited], incoming: [incoming])

        XCTAssertEqual(merged, [edited])
    }

    private func makeCoordinator(
        service: ScriptedTranscriptionService,
        clock: ManualRealtimeClock
    ) -> RealtimeTranscriptionCoordinator {
        RealtimeTranscriptionCoordinator(service: service, now: clock.now)
    }

    private func window(start: TimeInterval) -> AudioWindow {
        AudioWindow(
            samples: [Int16](repeating: 1, count: 160_000),
            startTime: start,
            isFinal: false
        )
    }
}
