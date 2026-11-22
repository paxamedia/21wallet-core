import Foundation
import Testing

@testable import WalletCore

@Suite("Stress and fuzz")
struct StressTests {
    private static let hostileURIs: [String] = [
        "",
        " ",
        "\n\t\r",
        "bitcoin:",
        "bitcoin:?",
        "bitcoin:?amount=",
        "bitcoin:?amount=1",
        "liquidnetwork:",
        "bitcoin:" + String(repeating: "a", count: 10_000),
        "bitcoin:addr?" + String(repeating: "k=v&", count: 5_000),
        "bitcoin:addr?amount=" + String(repeating: "9", count: 1_000),
        "bitcoin:addr?amount=-1",
        "bitcoin:addr?amount=NaN",
        "bitcoin:addr?amount=inf",
        "bitcoin:addr?amount=1e10",
        "bitcoin:addr?amount=0x10",
        "bitcoin:addr?amount=1.2.3.4",
        "bitcoin:addr?amount=1,234.5",
        "bitcoin:addr?amount=٣",
        "bitcoin:addr?=novalue",
        "bitcoin:addr?&&&&",
        "bitcoin:addr?amount=1&amount=2",
        "bitcoin:addr?label=%",
        "bitcoin:addr?label=%zz",
        "bitcoin:addr?label=%00%00",
        "BiTcOiN:addr",
        "bitcoin:bitcoin:addr",
        "liquidnetwork:addr?assetid=",
        "liquidnetwork:addr?assetid=" + String(repeating: "f", count: 64),
        "liquidnetwork:addr?assetid=" + String(repeating: "f", count: 63),
        "liquidnetwork:addr?assetid=../../etc/passwd",
        "liquidnetwork:addr?assetid=<script>alert(1)</script>",
        "bitcoin:addr\u{0}?amount=1",
        "bitcoin:addr?amount=1\u{202E}",
        "🙂",
        "bitcoin:🙂",
        "://",
        ":",
        "a:b:c:d",
    ]

    @Test("A hostile payment URI never crashes and never invents an amount")
    func paymentURIsSurviveHostileInput() {
        for raw in Self.hostileURIs {
            guard let uri = PaymentURI(raw) else { continue }

            #expect(!uri.address.isEmpty, "empty address accepted from \(raw.prefix(40))")

            if let amount = uri.amount {
                #expect(amount.sats >= 0, "negative amount from \(raw.prefix(40))")
                #expect(uri.assetID == nil, "asset request produced a satoshi amount")
            }
        }
    }

    @Test("Naming an asset always suppresses the satoshi amount, however malformed")
    func namedAssetsNeverProduceBitcoinAmounts() {
        for assetValue in ["", "nonsense", "../..", String(repeating: "f", count: 63), "%00"] {
            let uri = PaymentURI("liquidnetwork:addr?amount=25.5&assetid=\(assetValue)")
            #expect(uri?.amount == nil, "assetid=\(assetValue) leaked a bitcoin amount")
            #expect(uri?.requestedAmount == "25.5")
        }
    }

    @Test("Schemes the wallet cannot pay are refused, not stripped")
    func refusesForeignSchemes() {
        for raw in ["lightning:lnbc1", "https://x", "mailto:a@b", "javascript:alert(1)", "file:///etc"] {
            #expect(PaymentURI(raw) == nil, "accepted \(raw)")
        }
    }

    @Test("Amount parsing refuses everything that is not a plain non-negative decimal")
    func amountParsingRefusesJunk() {
        let bad = [
            "", " ", "-1", "NaN", "inf", "1e10", "0x10", "1.2.3", "1,2,3", "1.234,5",
            "١٢٣", "1 2", "+1", ".", ",", "..", "1..2", "\u{0}", "1\u{0}",
            String(repeating: "9", count: 400),
            "0." + String(repeating: "0", count: 9),
        ]
        for text in bad {
            #expect(Amount(btcString: text) == nil, "accepted \"\(text)\"")
        }
    }

    @Test("Amount parsing accepts the forms a real keyboard produces")
    func amountParsingAcceptsRealInput() {
        #expect(Amount(btcString: "0")?.sats == 0)
        #expect(Amount(btcString: "1")?.sats == 100_000_000)
        #expect(Amount(btcString: "0,001")?.sats == 100_000)
        #expect(Amount(btcString: "0.00000001")?.sats == 1)
        #expect(Amount(btcString: " 1.5 ")?.sats == 150_000_000)
    }

    @Test("Bitcoin's whole supply is far inside what Amount can hold")
    func supplyFitsComfortably() {
        #expect(Amount.maxSupply.sats == 2_100_000_000_000_000)
        #expect(Amount.maxSupply.sats < Int64.max / 4_000)
    }

    @Test("Amounts outside the money supply are recognised as impossible")
    func implausibleAmountsAreDetected() {
        #expect(Amount(sats: 1).isPlausible)
        #expect(Amount(sats: 0).isPlausible)
        #expect(Amount(sats: -1).isPlausible, "negative deltas are legitimate")
        #expect(Amount.maxSupply.isPlausible)
        #expect(!Amount(sats: Amount.maxSupply.sats + 1).isPlausible)
        #expect(!Amount(sats: Int64.max).isPlausible)
        #expect(!Amount(sats: Int64.min).isPlausible)
    }

    @Test("Adding untrusted amounts reports overflow instead of trapping")
    func checkedAdditionDoesNotTrap() {
        #expect(Amount(sats: 1).adding(Amount(sats: 2))?.sats == 3)
        #expect(Amount(sats: Int64.max).adding(Amount(sats: 1)) == nil)
        #expect(Amount(sats: Int64.min).adding(Amount(sats: -1)) == nil)
        #expect(Amount(sats: Int64.max).subtracting(Amount(sats: -1)) == nil)
        #expect(Amount(sats: 5).subtracting(Amount(sats: 8))?.sats == -3)
    }

    @Test("Asset precision is bounded to avoid Decimal overflow")
    func precisionIsBounded() {
        let asset = AssetID(hex: String(repeating: "a", count: 64))!

        let absurd = AssetAmount(asset: asset, units: 1, precision: 255)
        #expect(absurd.precision <= AssetAmount.maxPrecision)
        #expect(!absurd.decimal.isNaN)

        let sane = AssetAmount(asset: asset, units: 12_345, precision: 2)
        #expect(sane.decimal == Decimal(string: "123.45"))
    }

    @Test("Adding asset amounts reports overflow instead of trapping")
    func assetAdditionDoesNotTrap() {
        let asset = AssetID(hex: String(repeating: "b", count: 64))!
        let big = AssetAmount(asset: asset, units: Int64.max, precision: 2)
        let one = AssetAmount(asset: asset, units: 1, precision: 2)

        #expect(big.adding(one) == nil, "overflow must be reported, not trapped")
        #expect(one.adding(one)?.units == 2)
    }

    @Test("Asset amount parsing refuses junk at every precision")
    func assetParsingRefusesJunk() {
        let asset = AssetID(hex: String(repeating: "c", count: 64))!
        for precision in [UInt8(0), 2, 8, AssetAmount.maxPrecision, 255] {
            for text in ["", "-1", "NaN", "1e5", "1.2.3", "1.234,5", "abc", "\u{0}"] {
                #expect(
                    AssetAmount(asset: asset, decimalString: text, precision: precision) == nil,
                    "accepted \"\(text)\" at precision \(precision)"
                )
            }
        }
    }

    @Test("An asset id is 32 bytes of hex or it is nothing")
    func assetIDsRefuseJunk() {
        let bad = [
            "", " ", String(repeating: "a", count: 63), String(repeating: "a", count: 65),
            String(repeating: "g", count: 64), "0x" + String(repeating: "a", count: 62),
            String(repeating: "a", count: 63) + "\u{0}",
            String(repeating: "a", count: 10_000),
        ]
        for hex in bad {
            #expect(AssetID(hex: hex) == nil, "accepted \(hex.prefix(20))")
        }
    }

    @Test("A corrupted vault decodes to nothing rather than crashing")
    func hostileVaultJSONFailsClosed() {
        let blobs = [
            "", "{}", "null", "[]", "\"\"", "{\"id\":null}",
            "{\"id\":\"x\",\"createdAt\":0,\"isBackupVerified\":true,\"accounts\":null}",
            "{\"id\":\"x\",\"createdAt\":1e400,\"isBackupVerified\":true,\"accounts\":[]}",
            "{\"id\":\"x\",\"createdAt\":0,\"isBackupVerified\":\"yes\",\"accounts\":[]}",
            String(repeating: "[", count: 5_000),
            "{\"accounts\":[" + String(repeating: "{},", count: 1_000) + "{}]}",
        ]
        for blob in blobs {
            let decoded = try? JSONDecoder().decode(Vault.self, from: Data(blob.utf8))
            if let decoded {
                #expect(decoded.accounts.allSatisfy { !$0.id.isEmpty })
            }
        }
    }

    @Test("A corrupted address book decodes to nothing rather than crashing")
    func hostileAddressBookJSONFailsClosed() {
        let blobs = [
            "{}", "null", "{\"recipients\":null}", "{\"recipients\":[{}]}",
            "{\"recipients\":[{\"address\":\"\",\"lastUsed\":0}]}",
            "{\"recipients\":[{\"address\":\"a\",\"chain\":\"dogecoin\",\"lastUsed\":0}]}",
        ]
        for blob in blobs {
            _ = try? JSONDecoder().decode(AddressBook.self, from: Data(blob.utf8))
        }
    }

    @Test("Chain scoping did not weaken poisoning detection within a chain")
    func poisoningStillCaughtAfterChainScoping() {
        var book = AddressBook()
        let known = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
        book.remember(known, chain: .bitcoin)

        let poisoned = "bc1qw5ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZv8f3t4"
        #expect(book.warning(for: poisoned, chain: .bitcoin) != nil)

        var typo = Array(known)
        typo[20] = "z"
        typo[21] = "y"
        #expect(book.warning(for: String(typo), chain: .bitcoin) != nil)

        #expect(book.warning(for: known, chain: .bitcoin) == nil)
    }

    @Test("Similarity checking terminates on pathological input")
    func similarityTerminatesOnLongInput() {
        let a = String(repeating: "a", count: 2_000)
        let b = String(repeating: "b", count: 2_000)
        #expect(AddressSimilarity.isSuspiciouslySimilar(a, b) == false)
        #expect(AddressSimilarity.levenshtein("", "") == 0)
        #expect(AddressSimilarity.levenshtein("a", "") == 1)
    }

    @Test("Label keys cannot be forged across chains by a crafted transaction id")
    func labelKeysCannotCollideAcrossChains() {
        var labels = TransactionLabels()
        labels[.bitcoin, "liquid:abcd"] = "crafted"
        labels[.liquid, "abcd"] = "genuine"

        #expect(labels[.liquid, "abcd"] == "genuine")
        #expect(labels[.bitcoin, "liquid:abcd"] == "crafted")
        #expect(labels.count == 2)
    }
}
