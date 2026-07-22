import Foundation

public struct TranscriptParagraph: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceSegmentIDs: [UUID]
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String
    public let status: TranscriptSegmentStatus

    public init(
        id: UUID,
        sourceSegmentIDs: [UUID],
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        status: TranscriptSegmentStatus
    ) {
        self.id = id
        self.sourceSegmentIDs = sourceSegmentIDs
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.status = status
    }
}

public struct TranscriptParagraphComposer: Sendable {
    private static let paragraphGap: TimeInterval = 2
    private static let minimumPunctuatedLength = 40
    private static let maximumLength = 120
    private static let terminalPunctuation: Set<Character> = ["。", "！", "？", ".", "!", "?"]

    public init() {}

    public func compose(segments: [TranscriptSegment]) -> [TranscriptParagraph] {
        let orderedSegments = segments.compactMap(cleanedSegment).sorted(by: segmentOrder)
        var paragraphs: [TranscriptParagraph] = []
        var builder: ParagraphBuilder?

        func paragraph(from segment: TranscriptSegment) -> TranscriptParagraph {
            TranscriptParagraph(
                id: segment.id,
                sourceSegmentIDs: [segment.id],
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text,
                status: segment.status
            )
        }

        for segment in orderedSegments {
            if segment.status == .userEdited {
                if let builder {
                    paragraphs.append(builder.paragraph)
                }
                paragraphs.append(paragraph(from: segment))
                builder = nil
                continue
            }

            guard var current = builder else {
                builder = ParagraphBuilder(segment: segment)
                continue
            }

            if shouldStartNewParagraph(current: current, next: segment) {
                paragraphs.append(current.paragraph)
                builder = ParagraphBuilder(segment: segment)
            } else {
                current.append(segment)
                builder = current
            }
        }

        if let builder {
            paragraphs.append(builder.paragraph)
        }
        return paragraphs
    }

    private func cleanedSegment(_ segment: TranscriptSegment) -> TranscriptSegment? {
        guard let text = TranscriptTextSanitizer.sanitized(segment.text) else { return nil }
        var cleaned = segment
        cleaned.text = text
        return cleaned
    }

    private func segmentOrder(_ lhs: TranscriptSegment, _ rhs: TranscriptSegment) -> Bool {
        if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
        if lhs.endTime != rhs.endTime { return lhs.endTime < rhs.endTime }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func shouldStartNewParagraph(
        current: ParagraphBuilder,
        next: TranscriptSegment
    ) -> Bool {
        if next.startTime - current.endTime >= Self.paragraphGap {
            return true
        }
        if current.visibleCharacterCount >= Self.minimumPunctuatedLength,
           let lastCharacter = current.text.last,
           Self.terminalPunctuation.contains(lastCharacter) {
            return true
        }
        return current.visibleCharacterCount + visibleCharacterCount(in: next.text)
            > Self.maximumLength
    }

    private func visibleCharacterCount(in text: String) -> Int {
        text.reduce(into: 0) { count, character in
            if !character.isWhitespace { count += 1 }
        }
    }

    private struct ParagraphBuilder {
        private static let closingPunctuation: Set<Character> = [
            ".", ",", "!", "?", ";", ":", "%", ")", "]", "}",
            "。", "，", "！", "？", "；", "：", "、", "％", "）", "】", "》", "”", "’"
        ]

        private(set) var sourceSegmentIDs: [UUID]
        private(set) var startTime: TimeInterval
        private(set) var endTime: TimeInterval
        private(set) var text: String
        private(set) var status: TranscriptSegmentStatus

        init(segment: TranscriptSegment) {
            sourceSegmentIDs = [segment.id]
            startTime = segment.startTime
            endTime = segment.endTime
            text = segment.text
            status = segment.status
        }

        var visibleCharacterCount: Int {
            text.reduce(into: 0) { count, character in
                if !character.isWhitespace { count += 1 }
            }
        }

        var paragraph: TranscriptParagraph {
            TranscriptParagraph(
                id: sourceSegmentIDs[0],
                sourceSegmentIDs: sourceSegmentIDs,
                startTime: startTime,
                endTime: endTime,
                text: text,
                status: status
            )
        }

        mutating func append(_ segment: TranscriptSegment) {
            sourceSegmentIDs.append(segment.id)
            startTime = min(startTime, segment.startTime)
            endTime = max(endTime, segment.endTime)
            text = joined(left: text, right: segment.text)
            status = higherPriority(status, segment.status)
        }

        private func joined(left: String, right: String) -> String {
            guard let leftCharacter = left.last, let rightCharacter = right.first else {
                return left + right
            }
            if !Self.closingPunctuation.contains(rightCharacter),
               Self.isASCIICharacter(leftCharacter),
               Self.isASCIICharacter(rightCharacter) {
                return left + " " + right
            }
            return left + right
        }

        private func higherPriority(
            _ lhs: TranscriptSegmentStatus,
            _ rhs: TranscriptSegmentStatus
        ) -> TranscriptSegmentStatus {
            priority(of: lhs) >= priority(of: rhs) ? lhs : rhs
        }

        private func priority(of status: TranscriptSegmentStatus) -> Int {
            switch status {
            case .confirmed: 0
            case .provisional: 1
            case .userEdited: 2
            }
        }

        private static func isASCIICharacter(_ character: Character) -> Bool {
            character.unicodeScalars.allSatisfy(\.isASCII)
        }
    }
}
