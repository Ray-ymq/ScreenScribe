import Foundation

public struct TranscriptReconciliationResult: Equatable, Sendable {
    public let segments: [TranscriptSegment]
    public let conflicts: [TranscriptConflict]

    public init(segments: [TranscriptSegment], conflicts: [TranscriptConflict]) {
        self.segments = segments
        self.conflicts = conflicts
    }
}

public struct TranscriptReconciler: Sendable {
    public init() {}

    public func reconcile(
        existing: [TranscriptSegment],
        refined: [TranscriptSegment]
    ) -> TranscriptReconciliationResult {
        let edited = existing.filter { $0.status == .userEdited }
        var conflicts: [TranscriptConflict] = []

        let acceptedRefined = refined.filter { refinedSegment in
            let overlappingEdits = edited.filter { overlaps($0, refinedSegment) }
            for edit in overlappingEdits where normalized(edit.text) != normalized(refinedSegment.text) {
                conflicts.append(
                    TranscriptConflict(
                        segmentID: edit.id,
                        userText: edit.text,
                        refinedText: refinedSegment.text
                    )
                )
            }
            return overlappingEdits.isEmpty
        }.map { segment in
            var confirmed = segment
            confirmed.status = .confirmed
            return confirmed
        }

        let segments = (acceptedRefined + edited).sorted {
            if $0.startTime == $1.startTime { return $0.endTime < $1.endTime }
            return $0.startTime < $1.startTime
        }

        return TranscriptReconciliationResult(segments: segments, conflicts: conflicts)
    }

    private func overlaps(_ lhs: TranscriptSegment, _ rhs: TranscriptSegment) -> Bool {
        lhs.startTime < rhs.endTime && rhs.startTime < lhs.endTime
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}

