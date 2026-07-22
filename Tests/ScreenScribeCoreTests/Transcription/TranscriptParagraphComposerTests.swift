import Foundation
import XCTest
#if canImport(ScreenScribeCore)
@testable import ScreenScribeCore
#elseif canImport(ScreenScribe)
@testable import ScreenScribe
#endif

final class TranscriptParagraphComposerTests: XCTestCase {
    private let composer = TranscriptParagraphComposer()

    func testMergesChineseWithoutSpacesAndEnglishWithWordSpaces() throws {
        let chinese = composer.compose(segments: [
            segment(start: 0, end: 1, text: "你好"),
            segment(start: 1.2, end: 2, text: "世界")
        ])
        XCTAssertEqual(chinese.map(\.text), ["你好世界"])

        let english = composer.compose(segments: [
            segment(start: 0, end: 1, text: "Hello"),
            segment(start: 1.2, end: 2, text: "world"),
            segment(start: 2.1, end: 2.3, text: "."),
            segment(start: 2.4, end: 3, text: "Next")
        ])
        XCTAssertEqual(english.map(\.text), ["Hello world. Next"])
    }

    func testStartsNewParagraphAtTwoSecondGap() {
        let paragraphs = composer.compose(segments: [
            segment(start: 0, end: 1, text: "第一段"),
            segment(start: 3, end: 4, text: "第二段")
        ])

        XCTAssertEqual(paragraphs.map(\.text), ["第一段", "第二段"])
    }

    func testStartsNewParagraphAfterLongPunctuatedText() {
        let punctuatedText = String(repeating: "中", count: 39) + "。"
        let paragraphs = composer.compose(segments: [
            segment(start: 0, end: 1, text: punctuatedText),
            segment(start: 1.1, end: 2, text: "下一句")
        ])

        XCTAssertEqual(paragraphs.map(\.text), [punctuatedText, "下一句"])
    }

    func testAllowsOneHundredTwentyCharactersButSplitsBeforeOverflow() {
        let first = String(repeating: "甲", count: 100)
        let second = String(repeating: "乙", count: 20)
        let paragraphs = composer.compose(segments: [
            segment(start: 0, end: 1, text: first),
            segment(start: 1.1, end: 2, text: second),
            segment(start: 2.1, end: 3, text: "丙")
        ])

        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs[0].text.count, 120)
        XCTAssertEqual(paragraphs[1].text, "丙")
    }

    func testUserEditedSegmentIsAnIndependentProtectedParagraph() {
        let before = segment(start: 0, end: 1, text: "前文")
        let edited = segment(start: 1.1, end: 2, text: "用户修改", status: .userEdited)
        let after = segment(start: 2.1, end: 3, text: "后文", status: .provisional)

        let paragraphs = composer.compose(segments: [before, edited, after])

        XCTAssertEqual(paragraphs.map(\.text), ["前文", "用户修改", "后文"])
        XCTAssertEqual(paragraphs[1].sourceSegmentIDs, [edited.id])
        XCTAssertEqual(paragraphs[1].status, .userEdited)
    }

    func testSortsSegmentsCleansLegacyTokensAndDerivesMetadata() throws {
        let first = segment(start: 0, end: 1, text: "<|zh|>第一句", status: .confirmed)
        let second = segment(start: 1.1, end: 3, text: "第二句", status: .provisional)
        let empty = segment(start: 4, end: 5, text: "<|0.00|>")

        let paragraph = try XCTUnwrap(composer.compose(segments: [empty, second, first]).first)

        XCTAssertEqual(paragraph.id, first.id)
        XCTAssertEqual(paragraph.sourceSegmentIDs, [first.id, second.id])
        XCTAssertEqual(paragraph.startTime, 0)
        XCTAssertEqual(paragraph.endTime, 3)
        XCTAssertEqual(paragraph.text, "第一句第二句")
        XCTAssertEqual(paragraph.status, .provisional)
    }

    func testRealtimeReplacementDoesNotLeaveOldTextInParagraphs() {
        let stable = segment(start: 0, end: 1, text: "已确认前文")
        let old = segment(start: 1, end: 3, text: "旧临时片段", status: .provisional)
        let replacement = segment(start: 2, end: 4, text: "新的识别结果", status: .provisional)

        let merged = RealtimeTranscriptMerger().merge(
            existing: [stable, old],
            incoming: [replacement]
        )
        let paragraphs = composer.compose(segments: merged)

        XCTAssertFalse(paragraphs.contains { $0.text.contains("旧临时片段") })
        XCTAssertTrue(paragraphs.contains { $0.text.contains("新的识别结果") })
    }

    #if canImport(ScreenScribe)
    @MainActor
    func testAppModelRecomposesParagraphsAfterFinalSegmentsReplaceRealtimeSegments() throws {
        let suiteName = "ScreenScribe.ParagraphTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(userDefaults: defaults)

        model.segments = [segment(start: 0, end: 1, text: "实时结果", status: .provisional)]
        XCTAssertEqual(model.paragraphs.map(\.text), ["实时结果"])

        model.segments = [segment(start: 0, end: 1, text: "最终精转结果", status: .confirmed)]
        XCTAssertEqual(model.paragraphs.map(\.text), ["最终精转结果"])
        XCTAssertEqual(model.paragraphs.map(\.status), [.confirmed])
    }
    #endif

    private func segment(
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        status: TranscriptSegmentStatus = .confirmed
    ) -> TranscriptSegment {
        TranscriptSegment(
            startTime: start,
            endTime: end,
            text: text,
            status: status
        )
    }
}
