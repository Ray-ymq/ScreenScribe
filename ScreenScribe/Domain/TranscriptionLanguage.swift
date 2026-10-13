import Foundation

public enum TranscriptionLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case chinese
    case english

    public static let userDefaultsKey = "transcriptionLanguage"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: "自动"
        case .chinese: "中文"
        case .english: "英文"
        }
    }

    public var whisperLanguageCode: String? {
        switch self {
        case .automatic: nil
        case .chinese: "zh"
        case .english: "en"
        }
    }

    public func sessionDisplayName(detectedLanguageCode: String?) -> String {
        switch self {
        case .automatic:
            guard let detectedLanguageCode = Self.normalizedLanguageCode(detectedLanguageCode) else {
                return "自动（检测中）"
            }
            return "自动（\(Self.languageName(for: detectedLanguageCode))）"
        case .chinese, .english:
            return displayName
        }
    }

    public static func load(
        from userDefaults: UserDefaults = .standard,
        key: String = userDefaultsKey
    ) -> TranscriptionLanguage {
        guard
            let rawValue = userDefaults.string(forKey: key),
            let language = TranscriptionLanguage(rawValue: rawValue)
        else {
            return .automatic
        }
        return language
    }

    public func persist(
        in userDefaults: UserDefaults = .standard,
        key: String = userDefaultsKey
    ) {
        userDefaults.set(rawValue, forKey: key)
    }

    static func normalizedLanguageCode(_ languageCode: String?) -> String? {
        guard let languageCode else { return nil }
        let normalized = languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func languageName(for languageCode: String) -> String {
        let baseCode = languageCode
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map(String.init) ?? languageCode
        return switch baseCode {
        case "zh", "chinese": "中文"
        case "en", "english": "英文"
        default: languageCode
        }
    }
}

public struct TranscriptionDecodingPlan: Equatable, Sendable {
    public let languageCode: String?
    public let shouldDetectLanguage: Bool

    public init(languageCode: String?, shouldDetectLanguage: Bool) {
        self.languageCode = languageCode
        self.shouldDetectLanguage = shouldDetectLanguage
    }
}

/// Owns the language decision for one recording. Create a new resolver for every session.
public struct TranscriptionLanguageResolver: Equatable, Sendable {
    public let selection: TranscriptionLanguage
    public private(set) var resolvedLanguageCode: String?

    public init(selection: TranscriptionLanguage) {
        self.selection = selection
        resolvedLanguageCode = selection.whisperLanguageCode
    }

    public var decodingPlan: TranscriptionDecodingPlan {
        if let resolvedLanguageCode {
            return TranscriptionDecodingPlan(
                languageCode: resolvedLanguageCode,
                shouldDetectLanguage: false
            )
        }
        return TranscriptionDecodingPlan(languageCode: nil, shouldDetectLanguage: true)
    }

    public var requiresDetectionBeforeFinalization: Bool {
        selection == .automatic && resolvedLanguageCode == nil
    }

    /// Locks the first usable automatic detection. Fixed-language sessions ignore detections.
    @discardableResult
    public mutating func lockDetectedLanguage(
        _ languageCode: String?,
        hasUsableTranscription: Bool
    ) -> Bool {
        guard
            selection == .automatic,
            resolvedLanguageCode == nil,
            hasUsableTranscription,
            let languageCode = TranscriptionLanguage.normalizedLanguageCode(languageCode)
        else {
            return false
        }
        resolvedLanguageCode = languageCode
        return true
    }
}

public enum TranscriptTextSanitizer {
    public static func sanitized(_ text: String) -> String? {
        let withoutControlTokens = text.replacingOccurrences(
            of: #"<\|[^|]*\|>"#,
            with: "",
            options: .regularExpression
        )
        let cleaned = withoutControlTokens.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
