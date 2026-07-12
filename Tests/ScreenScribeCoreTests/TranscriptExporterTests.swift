import Foundation
import XCTest
@testable import ScreenScribeCore

final class TranscriptExporterTests: XCTestCase {
    private let exporter = DefaultTranscriptExporter()

    func testRendersSRTMilliseconds() throws {
        let output = try exporter.render(session: sampleSession, format: .srt)
        XCTAssertTrue(output.contains("00:00:01,235 --> 00:00:04,500"))
        XCTAssertTrue(output.contains("测试中文文稿"))
    }

    func testRendersPlainText() throws {
        let output = try exporter.render(session: sampleSession, format: .text)
        XCTAssertEqual(output, "测试中文文稿\n")
        XCTAssertNotNil(output.data(using: .utf8))
    }

    func testRendersMarkdownMetadata() throws {
        let output = try exporter.render(session: sampleSession, format: .markdown)
        XCTAssertTrue(output.contains("来源：示例窗口"))
        XCTAssertTrue(output.contains("[00:00:01]"))
    }

    private var sampleSession: RecordingSession {
        RecordingSession(
            title: "中文标题",
            source: CaptureSourceSelection(id: "window-1", kind: .window, title: "示例窗口"),
            state: .completed,
            modelID: "small",
            segments: [
                TranscriptSegment(
                    startTime: 1.2346,
                    endTime: 4.5,
                    text: "测试中文文稿",
                    status: .confirmed
                )
            ]
        )
    }
}
