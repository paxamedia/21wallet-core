public struct AmountFormatter: Sendable {
    public var groupingSeparator: String
    public var decimalSeparator: String

    public init(groupingSeparator: String = " ", decimalSeparator: String = ".") {
        self.groupingSeparator = groupingSeparator
        self.decimalSeparator = decimalSeparator
    }

    public func string(_ amount: Amount, unit: BitcoinUnit, includeSymbol: Bool = true) -> String {
        let sign = amount.sats < 0 ? "-" : ""
        let body: String
        switch unit {
        case .sat:
            body = sign + groupDigits(String(abs(amount.sats)))
        case .btc:
            body = sign + formatBTC(magnitudeSats: abs(amount.sats))
        }
        return includeSymbol ? "\(body) \(unit.symbol)" : body
    }

    private func formatBTC(magnitudeSats: Int64) -> String {
        let whole = magnitudeSats / Amount.satsPerBTC
        let fraction = magnitudeSats % Amount.satsPerBTC
        var fractionDigits = String(format: "%08lld", fraction)
        while fractionDigits.hasSuffix("0") { fractionDigits.removeLast() }
        let wholeGrouped = groupDigits(String(whole))
        return fractionDigits.isEmpty
            ? wholeGrouped
            : wholeGrouped + decimalSeparator + fractionDigits
    }

    private func groupDigits(_ digits: String) -> String {
        let chars = Array(digits)
        guard chars.count > 3 else { return digits }
        var groups: [String] = []
        var end = chars.count
        while end > 3 {
            groups.insert(String(chars[(end - 3)..<end]), at: 0)
            end -= 3
        }
        groups.insert(String(chars[0..<end]), at: 0)
        return groups.joined(separator: groupingSeparator)
    }
}
