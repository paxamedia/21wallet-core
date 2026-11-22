import Foundation

public struct AssetAmount: Sendable, Hashable, Codable {
    public let asset: AssetID

    public let units: Int64

    public let precision: UInt8

    public static let maxPrecision: UInt8 = 18

    public init(asset: AssetID, units: Int64, precision: UInt8) {
        self.asset = asset
        self.units = units
        self.precision = min(precision, Self.maxPrecision)
    }

    public var isNegative: Bool { units < 0 }

    public var magnitude: AssetAmount {
        AssetAmount(
            asset: asset,
            units: units == Int64.min ? Int64.max : abs(units),
            precision: precision
        )
    }

    public var decimal: Decimal {
        Decimal(units) / pow(Decimal(10), Int(precision))
    }

    public func adding(_ other: AssetAmount) -> AssetAmount? {
        guard other.asset == asset, other.precision == precision else { return nil }
        let (total, overflowed) = units.addingReportingOverflow(other.units)
        guard !overflowed else { return nil }
        return AssetAmount(asset: asset, units: total, precision: precision)
    }

    public init?(asset: AssetID, decimalString: String, precision: UInt8) {
        var trimmed = decimalString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(","), trimmed.contains(".") { return nil }
        trimmed = trimmed.replacingOccurrences(of: ",", with: ".")
        guard trimmed.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        guard trimmed.filter({ $0 == "." }).count <= 1 else { return nil }
        guard trimmed.contains(where: \.isNumber) else { return nil }

        let effectivePrecision = min(precision, Self.maxPrecision)
        if let dot = trimmed.firstIndex(of: ".") {
            let fraction = trimmed[trimmed.index(after: dot)...]
            guard fraction.count <= Int(effectivePrecision) else { return nil }
        }

        guard let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
            !value.isNaN, value >= 0
        else { return nil }

        var scaled = value * pow(Decimal(10), Int(effectivePrecision))
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        guard number.doubleValue.magnitude < Double(Int64.max) else { return nil }
        self.init(
            asset: asset,
            units: number.int64Value,
            precision: effectivePrecision
        )
    }
}
