import Foundation
import Testing

@testable import WalletCore

@Suite("Address book and poisoning checks")
struct AddressBookTests {
    private let known = "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"

    private func book() -> AddressBook {
        var book = AddressBook()
        book.remember(known, label: "Exchange")
        return book
    }

    @Test("Paying the same address again is not a warning")
    func exactMatchIsNotSuspicious() {
        #expect(book().warning(for: known) == nil)
        #expect(!AddressSimilarity.isSuspiciouslySimilar(known, known))
    }

    @Test("An address matching head and tail but not the middle is flagged")
    func flagsPoisonedLookalike() {
        let poisoned = "tb1qw5zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzv8f3t4"
        #expect(poisoned.prefix(6) == known.prefix(6))
        #expect(poisoned.suffix(6) == known.suffix(6))

        let warning = book().warning(for: poisoned)
        #expect(warning != nil)
        if case .resemblesKnownAddress(let recipient) = warning {
            #expect(recipient.label == "Exchange")
        } else {
            Issue.record("expected a lookalike warning")
        }
        #expect(warning?.message.contains("Exchange") == true)
    }

    @Test("A few changed characters in the middle are flagged as a likely slip")
    func flagsNearMiss() {
        var characters = Array(known)
        characters[20] = "x"
        characters[21] = "y"
        let typo = String(characters)
        #expect(AddressSimilarity.isSuspiciouslySimilar(typo, known))
    }

    @Test("An unrelated address is not flagged")
    func doesNotFlagUnrelatedAddresses() {
        let unrelated = "tb1q6rz28mcfaxtmd6v789l9rrlrusdprr9pqcpvkl"
        #expect(!AddressSimilarity.isSuspiciouslySimilar(unrelated, known))
        #expect(book().warning(for: unrelated) == nil)
    }

    @Test("An empty book warns about nothing")
    func emptyBookIsQuiet() {
        #expect(AddressBook().warning(for: known) == nil)
    }

    @Test("Remembering is idempotent and keeps the label")
    func remembering() {
        var book = AddressBook()
        book.remember(known, label: "Exchange")
        book.remember(known)

        #expect(book.recipients.count == 1)
        #expect(book.recipient(for: known)?.label == "Exchange")
    }

    @Test("Edit distance is symmetric and counts single changes")
    func levenshteinBasics() {
        #expect(AddressSimilarity.levenshtein("abc", "abc") == 0)
        #expect(AddressSimilarity.levenshtein("abc", "abd") == 1)
        #expect(AddressSimilarity.levenshtein("kitten", "sitting") == 3)
        #expect(
            AddressSimilarity.levenshtein("abc", "") == AddressSimilarity.levenshtein("", "abc")
        )
    }

    @Test("The book round-trips through storage")
    func codableRoundTrip() throws {
        let original = book()
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(AddressBook.self, from: data).recipients.count == 1)
    }

    @Test("A near-miss on another chain is not a warning")
    func lookalikesDoNotCrossChains() {
        var book = AddressBook()
        book.remember("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", chain: .bitcoin)

        #expect(book.warning(for: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5", chain: .liquid) == nil)
        #expect(book.warning(for: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5", chain: .bitcoin) != nil)
    }

    @Test("The same address on two chains is two entries")
    func remembersPerChain() {
        var book = AddressBook()
        book.remember("shared-address-string-long-enough", chain: .bitcoin)
        book.remember("shared-address-string-long-enough", chain: .liquid)

        #expect(book.recipients.count == 2)
        #expect(book.recipient(for: "shared-address-string-long-enough", chain: .liquid)?.chain == .liquid)
    }

    @Test("A book written before chains existed reads back as Bitcoin")
    func decodesLegacyEntries() throws {
        let legacy = """
            {"recipients":[{"address":"bc1qlegacy000000000000","lastUsed":0}]}
            """
        let book = try JSONDecoder().decode(AddressBook.self, from: Data(legacy.utf8))
        #expect(book.recipients.first?.chain == .bitcoin)
    }
}
