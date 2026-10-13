import Foundation

public struct RealtimeTranscriptMerger: Sendable {
    public init() {}

    public func merge(
        existing: [TranscriptSegment],
        incoming: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        guard !incoming.isEmpty else { return existing }

        let incomingStart = incoming.map(\.startTime).min() ?? 0
        let incomingEnd = incoming.map(\.endTime).max() ?? incomingStart
        var retained = existing.filter { segment in
            if segment.status == .userEdited { return true }
            return segment.endTime <= incomingStart || segment.startTime >= incomingEnd
        }

        retained = retained.map { segment in
            var updated = segment
            if updated.status == .provisional, updated.endTime <= incomingStart {
                updated.status = .confirmed
            }
            return updated
        }

        let filteredIncoming = incoming.filter { candidate in
            !retained.contains { existingSegment in
                existingSegment.status == .userEdited && overlaps(existingSegment, candidate)
            }
        }

        return (retained + filteredIncoming).sorted {
            if $0.startTime == $1.startTime { return $0.endTime < $1.endTime }
            return $0.startTime < $1.startTime
        }
    }

    private func overlaps(_ lhs: TranscriptSegment, _ rhs: TranscriptSegment) -> Bool {
        lhs.startTime < rhs.endTime && rhs.startTime < lhs.endTime
    }
}

