import Foundation

public enum TranscriptExportFormat: String, CaseIterable, Sendable {
    case markdown = "md"
    case text = "txt"
    case srt
}

public protocol TranscriptExporter: Sendable {
    func render(session: RecordingSession, format: TranscriptExportFormat) throws -> String
    func export(session: RecordingSession, format: TranscriptExportFormat, to url: URL) throws
}

public struct DefaultTranscriptExporter: TranscriptExporter {
    public init() {}

    public func render(session: RecordingSession, format: TranscriptExportFormat) throws -> String {
        let segments = session.segments.sorted { $0.startTime < $1.startTime }
        switch format {
        case .markdown:
            let paragraphs = TranscriptParagraphComposer().compose(segments: segments)
            return renderMarkdown(session: session, paragraphs: paragraphs)
        case .text:
            let paragraphs = TranscriptParagraphComposer().compose(segments: segments)
            return renderText(paragraphs: paragraphs)
        case .srt:
            return renderSRT(segments: segments)
        }
    }

    public func export(session: RecordingSession, format: TranscriptExportFormat, to url: URL) throws {
        let content = try render(session: session, format: format)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func renderText(paragraphs: [TranscriptParagraph]) -> String {
        let body = paragraphs.map(\.text).joined(separator: "\n\n")
        return body.isEmpty ? "" : body + "\n"
    }

    private func renderMarkdown(
        session: RecordingSession,
        paragraphs: [TranscriptParagraph]
    ) -> String {
        let date = ISO8601DateFormatter().string(from: session.createdAt)
        let header = """
        # \(session.title)

        - 日期：\(date)
        - 来源：\(session.source.title)
        - 模型：\(session.modelID)

        ## 文稿
        """
        let body = paragraphs.map(\.text).joined(separator: "\n\n")
        return body.isEmpty ? header + "\n" : header + "\n\n" + body + "\n"
    }

    private func renderSRT(segments: [TranscriptSegment]) -> String {
        guard !segments.isEmpty else { return "" }
        return segments.enumerated().map { index, segment in
            """
            \(index + 1)
            \(srtTimestamp(segment.startTime)) --> \(srtTimestamp(segment.endTime))
            \(segment.text)
            """
        }.joined(separator: "\n\n") + "\n"
    }

    private func srtTimestamp(_ interval: TimeInterval) -> String {
        let totalMilliseconds = max(0, Int((interval * 1_000).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds / 60_000) % 60
        let seconds = (totalMilliseconds / 1_000) % 60
        let milliseconds = totalMilliseconds % 1_000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}
