import Testing

@testable import WalletCore

@Suite("AmountFormatter")
struct AmountFormatterTests {
    private let formatter = AmountFormatter(groupingSeparator: " ", decimalSeparator: ".")

    @Test("Satoshi amounts group in threes")
    func formatsSats() {
        #expect(formatter.string(Amount(sats: 1_234_567), unit: .sat) == "1 234 567 sats")
        #expect(formatter.string(Amount(sats: 100), unit: .sat) == "100 sats")
        #expect(formatter.string(Amount.zero, unit: .sat) == "0 sats")
        #expect(formatter.string(Amount(sats: -1_500), unit: .sat) == "-1 500 sats")
    }

    @Test("BTC amounts trim trailing zeros but never lose satoshis")
    func formatsBTC() {
        #expect(formatter.string(Amount(sats: 150_000_000), unit: .btc) == "1.5 BTC")
        #expect(formatter.string(Amount(sats: 100_000_000), unit: .btc) == "1 BTC")
        #expect(formatter.string(Amount(sats: 1), unit: .btc) == "0.00000001 BTC")
        #expect(formatter.string(Amount(sats: 123_456), unit: .btc) == "0.00123456 BTC")
        #expect(formatter.string(Amount.zero, unit: .btc) == "0 BTC")
        #expect(formatter.string(Amount(sats: -50_000_000), unit: .btc) == "-0.5 BTC")
    }

    @Test("Large BTC amounts group the whole part")
    func groupsWholeBTC() {
        #expect(formatter.string(Amount(sats: 2_100_000_000_000_000), unit: .btc) == "21 000 000 BTC")
    }

    @Test("Symbols can be omitted and separators are injectable")
    func respectsConfiguration() {
        #expect(formatter.string(Amount(sats: 1_234), unit: .sat, includeSymbol: false) == "1 234")
        let comma = AmountFormatter(groupingSeparator: ",", decimalSeparator: ".")
        #expect(comma.string(Amount(sats: 1_234_567), unit: .sat) == "1,234,567 sats")
    }
}
