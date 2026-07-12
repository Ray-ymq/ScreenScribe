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
            return renderMarkdown(session: session, segments: segments)
        case .text:
            return segments.map(\.text).joined(separator: "\n") + "\n"
        case .srt:
            return renderSRT(segments: segments)
        }
    }

    public func export(session: RecordingSession, format: TranscriptExportFormat, to url: URL) throws {
        let content = try render(session: session, format: format)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func renderMarkdown(session: RecordingSession, segments: [TranscriptSegment]) -> String {
        let date = ISO8601DateFormatter().string(from: session.createdAt)
        let lines = segments.map { segment in
            "- [\(shortTimestamp(segment.startTime))] \(segment.text)"
        }.joined(separator: "\n")

        return """
        # \(session.title)

        - 日期：\(date)
        - 来源：\(session.source.title)
        - 模型：\(session.modelID)

        ## 文稿

        \(lines)
        """ + "\n"
    }

    private func renderSRT(segments: [TranscriptSegment]) -> String {
        segments.enumerated().map { index, segment in
            """
            \(index + 1)
            \(srtTimestamp(segment.startTime)) --> \(srtTimestamp(segment.endTime))
            \(segment.text)
            """
        }.joined(separator: "\n\n") + "\n"
    }

    private func shortTimestamp(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", totalSeconds / 3600, (totalSeconds / 60) % 60, totalSeconds % 60)
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

