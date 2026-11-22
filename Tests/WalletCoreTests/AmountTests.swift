import Foundation
import Testing

@testable import WalletCore

@Suite("Amount")
struct AmountTests {
    @Test("Satoshis convert to an exact BTC decimal")
    func satsToBTC() {
        #expect(Amount(sats: 100_000_000).btc == Decimal(1))
        #expect(Amount(sats: 1).btc == Decimal(string: "0.00000001")!)
        #expect(Amount.zero.btc == Decimal(0))
    }

    @Test("BTC decimals round to the nearest satoshi")
    func btcToSats() {
        #expect(Amount(btc: Decimal(string: "0.00000001")!).sats == 1)
        #expect(Amount(btc: Decimal(1)).sats == 100_000_000)
        #expect(Amount(btc: Decimal(string: "1.234567894")!).sats == 123_456_789)
        #expect(Amount(btc: Decimal(string: "1.234567896")!).sats == 123_456_790)
    }

    @Test("Valid BTC strings parse to exact satoshi counts")
    func parsesValidStrings() {
        #expect(Amount(btcString: "1")?.sats == 100_000_000)
        #expect(Amount(btcString: "0.00000001")?.sats == 1)
        #expect(Amount(btcString: "1.23456789")?.sats == 123_456_789)
        #expect(Amount(btcString: "0")?.sats == 0)
        #expect(Amount(btcString: " 0.5 ")?.sats == 50_000_000)
    }

    @Test("The whole supply fits without overflow")
    func handlesFullSupply() {
        #expect(Amount(btcString: "21000000")?.sats == 2_100_000_000_000_000)
    }

    @Test("A comma works as the decimal separator")
    func acceptsCommaSeparator() {
        #expect(Amount(btcString: "0,001")?.sats == 100_000)
        #expect(Amount(btcString: "1,5")?.sats == 150_000_000)
        #expect(Amount(btcString: "1.234,5") == nil)
        #expect(Amount(btcString: "1,2,3") == nil)
    }

    @Test("Malformed, negative, and sub-satoshi input is rejected")
    func rejectsInvalidStrings() {
        #expect(Amount(btcString: "0.000000001") == nil, "9 decimal places is below one satoshi")
        #expect(Amount(btcString: "1.2.3") == nil)
        #expect(Amount(btcString: "-1") == nil)
        #expect(Amount(btcString: "abc") == nil)
        #expect(Amount(btcString: "1e8") == nil)
        #expect(Amount(btcString: "") == nil)
        #expect(Amount(btcString: "   ") == nil)
    }

    @Test("Arithmetic and comparison operate on satoshis")
    func arithmetic() {
        #expect((Amount(sats: 100) + Amount(sats: 50)).sats == 150)
        #expect((Amount(sats: 100) - Amount(sats: 150)).sats == -50)
        #expect(Amount(sats: -50).isNegative)
        #expect(Amount(sats: -50).magnitude == Amount(sats: 50))
        #expect(Amount(sats: 1) < Amount(sats: 2))
    }
}
