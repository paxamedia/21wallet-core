import Foundation
import Testing

@testable import WalletCore

@Suite("Transaction labels")
struct TransactionLabelsTests {
    private let txid = "d4f2c1a0"

    @Test("A label round-trips")
    func storesAndReads() {
        var labels = TransactionLabels()
        labels[.bitcoin, txid] = "Rent"
        #expect(labels[.bitcoin, txid] == "Rent")
        #expect(labels.count == 1)
    }

    @Test("Blank input clears the label rather than storing emptiness")
    func blankClears() {
        var labels = TransactionLabels()
        labels[.bitcoin, txid] = "Rent"
        labels[.bitcoin, txid] = "   "
        #expect(labels[.bitcoin, txid] == nil)
        #expect(labels.count == 0)

        labels[.bitcoin, txid] = "Rent"
        labels[.bitcoin, txid] = nil
        #expect(labels[.bitcoin, txid] == nil)
    }

    @Test("Surrounding whitespace is trimmed")
    func trims() {
        var labels = TransactionLabels()
        labels[.bitcoin, txid] = "  Coffee  "
        #expect(labels[.bitcoin, txid] == "Coffee")
    }

    @Test("Labels round-trip through storage")
    func codable() throws {
        var labels = TransactionLabels()
        labels[.bitcoin, txid] = "Rent"
        let data = try JSONEncoder().encode(labels)
        #expect(
            try JSONDecoder().decode(TransactionLabels.self, from: data)[.bitcoin, txid] == "Rent"
        )
    }

    @Test("The same transaction id on two chains holds two different notes")
    func keysByChain() {
        var labels = TransactionLabels()
        labels[.bitcoin, txid] = "Rent"
        labels[.liquid, txid] = "Something else entirely"

        #expect(labels[.bitcoin, txid] == "Rent")
        #expect(labels[.liquid, txid] == "Something else entirely")
        #expect(labels.count == 2)
    }
}
