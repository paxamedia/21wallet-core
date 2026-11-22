import Testing

@testable import WalletCore

@Suite("BIP39 wordlist")
struct BIP39WordlistTests {
    @Test("The list is the full BIP39 English wordlist")
    func completeness() {
        #expect(BIP39Wordlist.words.count == 2048)
        #expect(Set(BIP39Wordlist.words).count == 2048, "the wordlist must not repeat")
        #expect(BIP39Wordlist.words.first == "abandon")
        #expect(BIP39Wordlist.words.last == "zoo")
        #expect(BIP39Wordlist.words == BIP39Wordlist.words.sorted())
    }

    @Test("Membership is case-insensitive and rejects non-words")
    func membership() {
        #expect(BIP39Wordlist.contains("abandon"))
        #expect(BIP39Wordlist.contains("ZEBRA"))
        #expect(!BIP39Wordlist.contains("wallet256"))
        #expect(!BIP39Wordlist.contains(""))
        #expect(!BIP39Wordlist.contains("aban"))
    }

    @Test("Suggestions complete a prefix")
    func suggestions() {
        let suggestions = BIP39Wordlist.suggestions(for: "aban")
        #expect(suggestions.contains("abandon"))
        #expect(suggestions.allSatisfy { $0.hasPrefix("aban") })
        #expect(BIP39Wordlist.suggestions(for: "zoo") == ["zoo"])
        #expect(BIP39Wordlist.suggestions(for: "").isEmpty)
        #expect(BIP39Wordlist.suggestions(for: "qqqq").isEmpty)
        #expect(BIP39Wordlist.suggestions(for: "a", limit: 3).count == 3)
    }
}
