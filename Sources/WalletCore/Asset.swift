import Foundation

public struct AssetID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let hex: String

    public init?(hex: String) {
        let normalised = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalised.count == 64,
            normalised.allSatisfy({ $0.isHexDigit && ($0.isNumber || $0.isLowercase) })
        else { return nil }
        self.hex = normalised
    }

    public var truncated: String {
        "\(hex.prefix(8))…\(hex.suffix(8))"
    }

    public var description: String { hex }
}

public struct Asset: Sendable, Hashable, Codable, Identifiable {
    public let id: AssetID
    public let ticker: String
    public let name: String

    public let precision: UInt8

    public let isVerified: Bool

    public init(id: AssetID, ticker: String, name: String, precision: UInt8, isVerified: Bool) {
        self.id = id
        self.ticker = ticker
        self.name = name
        self.precision = precision
        self.isVerified = isVerified
    }

    public var displayTicker: String { isVerified ? ticker : id.truncated }
}

public enum AssetRegistry {
    public static let verified: [Asset] = []

    public static func asset(for id: AssetID) -> Asset? {
        verified.first { $0.id == id }
    }

    public static func displayTicker(for id: AssetID, claiming _: String? = nil) -> String {
        asset(for: id)?.displayTicker ?? id.truncated
    }

    public static func isVerified(_ id: AssetID) -> Bool { asset(for: id) != nil }
}
