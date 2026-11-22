import Foundation

public struct FiatFormatter: Sendable {
    public var currencyCode: String
    public var locale: Locale

    public init(currencyCode: String = "USD", locale: Locale = .autoupdatingCurrent) {
        self.currencyCode = currencyCode
        self.locale = locale
    }

    public func value(of amount: Amount, at pricePerBTC: Decimal) -> Decimal {
        amount.btc * pricePerBTC
    }

    public func string(_ amount: Amount, at pricePerBTC: Decimal) -> String {
        string(value: value(of: amount, at: pricePerBTC))
    }

    public func string(value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber)
            ?? "\(currencyCode) \(value)"
    }
}
