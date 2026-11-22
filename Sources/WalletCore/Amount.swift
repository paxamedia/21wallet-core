import Foundation

public struct Amount: Sendable, Hashable, Comparable, Codable {
    public static let satsPerBTC: Int64 = 100_000_000

    public static let maxSupply = Amount(sats: 21_000_000 * satsPerBTC)

    public let sats: Int64

    public init(sats: Int64) {
        self.sats = sats
    }

    public static let zero = Amount(sats: 0)

    public var btc: Decimal {
        Decimal(sats) / Decimal(Self.satsPerBTC)
    }

    public var isNegative: Bool { sats < 0 }

    public var isPlausible: Bool {
        sats.magnitude <= UInt64(Self.maxSupply.sats)
    }

    public var magnitude: Amount {
        sats == Int64.min ? Amount(sats: Int64.max) : Amount(sats: abs(sats))
    }

    public static func < (lhs: Amount, rhs: Amount) -> Bool { lhs.sats < rhs.sats }

    public static func + (lhs: Amount, rhs: Amount) -> Amount { Amount(sats: lhs.sats + rhs.sats) }

    public static func - (lhs: Amount, rhs: Amount) -> Amount { Amount(sats: lhs.sats - rhs.sats) }

    public func adding(_ other: Amount) -> Amount? {
        let (value, overflowed) = sats.addingReportingOverflow(other.sats)
        return overflowed ? nil : Amount(sats: value)
    }

    public func subtracting(_ other: Amount) -> Amount? {
        let (value, overflowed) = sats.subtractingReportingOverflow(other.sats)
        return overflowed ? nil : Amount(sats: value)
    }
}

extension Amount {
    public init(btc: Decimal) {
        var scaled = btc * Decimal(Self.satsPerBTC)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        self = Amount(sats: NSDecimalNumber(decimal: rounded).int64Value)
    }

    public init?(btcString: String) {
        var trimmed = btcString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(","), trimmed.contains(".") { return nil }
        trimmed = trimmed.replacingOccurrences(of: ",", with: ".")
        guard trimmed.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        guard trimmed.filter({ $0 == "." }).count <= 1 else { return nil }
        guard trimmed.contains(where: \.isNumber) else { return nil }

        if let dot = trimmed.firstIndex(of: ".") {
            let fraction = trimmed[trimmed.index(after: dot)...]
            guard fraction.count <= 8 else { return nil }
        }

        guard let decimal = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
              !decimal.isNaN, decimal >= 0 else { return nil }

        self = Amount(btc: decimal)
    }
}
