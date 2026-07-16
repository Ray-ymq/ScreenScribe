import Foundation
import XCTest
#if canImport(ScreenScribeCore)
@testable import ScreenScribeCore
#elseif canImport(ScreenScribe)
@testable import ScreenScribe
#endif

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

    func testRendersPlainTextAsNaturalParagraphs() throws {
        let output = try exporter.render(session: paragraphSession, format: .text)
        XCTAssertEqual(output, "第一句继续第一段\n\n第二段\n")
    }

    func testRendersMarkdownMetadata() throws {
        let output = try exporter.render(session: sampleSession, format: .markdown)
        XCTAssertTrue(output.contains("来源：示例窗口"))
        XCTAssertTrue(output.contains("## 文稿\n\n测试中文文稿"))
        XCTAssertFalse(output.contains("[00:00:01]"))
    }

    func testLeavesSRTAtOriginalSegmentGranularity() throws {
        let output = try exporter.render(session: paragraphSession, format: .srt)
        XCTAssertEqual(output.components(separatedBy: "\n\n").count, 3)
        XCTAssertTrue(output.contains("00:00:00,000 --> 00:00:01,000\n第一句"))
        XCTAssertTrue(output.contains("00:00:01,200 --> 00:00:02,000\n继续第一段"))
        XCTAssertTrue(output.contains("00:00:04,000 --> 00:00:05,000\n第二段"))
    }

    func testRendersEmptyTranscriptWithoutMeaninglessWhitespace() throws {
        var session = sampleSession
        session.segments = []

        XCTAssertEqual(try exporter.render(session: session, format: .text), "")
        XCTAssertEqual(try exporter.render(session: session, format: .srt), "")
        let markdown = try exporter.render(session: session, format: .markdown)
        XCTAssertTrue(markdown.hasSuffix("## 文稿\n"))
        XCTAssertFalse(markdown.hasSuffix("## 文稿\n\n"))
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

    private var paragraphSession: RecordingSession {
        RecordingSession(
            title: "段落测试",
            source: CaptureSourceSelection(id: "window-2", kind: .window, title: "示例窗口"),
            state: .completed,
            modelID: "small",
            segments: [
                TranscriptSegment(
                    startTime: 0,
                    endTime: 1,
                    text: "第一句",
                    status: .confirmed
                ),
                TranscriptSegment(
                    startTime: 1.2,
                    endTime: 2,
                    text: "继续第一段",
                    status: .confirmed
                ),
                TranscriptSegment(
                    startTime: 4,
                    endTime: 5,
                    text: "第二段",
                    status: .confirmed
                )
            ]
        )
    }
}
