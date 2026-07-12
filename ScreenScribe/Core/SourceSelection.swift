import Foundation

public enum CaptureSourceKind: String, Codable, CaseIterable, Sendable {
    case display
    case window
    case application
}

public struct CaptureSourceSelection: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: CaptureSourceKind
    public let title: String

    public init(id: String, kind: CaptureSourceKind, title: String) {
        self.id = id
        self.kind = kind
        self.title = title
    }
}

