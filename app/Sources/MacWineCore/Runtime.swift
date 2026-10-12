import Foundation

public struct RuntimeStatus: Decodable {
    public let installed: String?
    public let required: String?
    public let upToDate: Bool
    public let path: String?
    public var isReady: Bool { upToDate && installed?.isEmpty == false && path?.isEmpty == false }
}

// Ignore ordinary diagnostics, partial tokens, and out-of-range values.
public enum RuntimeProgress {
    public static func percent(from line: String) -> Double? {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, parts[0] == "progress", let value = Double(parts[1]),
              value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }
}
