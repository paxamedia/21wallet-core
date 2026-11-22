import Testing

@testable import BitcoinEngine

@Suite("MnemonicNormalizer")
struct MnemonicNormalizerTests {
    private let valid = DerivationVectorTests.testMnemonic

    @Test("Messy but correct input normalises to a valid phrase")
    func normalisesUserInput() {
        let messy = "  Abandon   ABANDON abandon\nabandon abandon abandon abandon "
            + "abandon abandon\tabandon abandon About  "
        #expect(MnemonicNormalizer.normalize(messy) == valid)
        #expect(MnemonicNormalizer.isValid(messy))
    }

    @Test("Checksum and wordlist violations are rejected")
    func rejectsInvalidPhrases() {
        let badChecksum = Array(repeating: "abandon", count: 12).joined(separator: " ")
        #expect(!MnemonicNormalizer.isValid(badChecksum))
        #expect(!MnemonicNormalizer.isValid("wallet256 " + valid.split(separator: " ").dropFirst().joined(separator: " ")))
        #expect(!MnemonicNormalizer.isValid(""))
        #expect(!MnemonicNormalizer.isValid("abandon abandon"))
    }

    @Test("Word count reflects the normalised phrase")
    func countsWords() {
        #expect(MnemonicNormalizer.wordCount(valid) == 12)
        #expect(MnemonicNormalizer.wordCount("   ") == 0)
        #expect(MnemonicNormalizer.wordCount("  one   two  ") == 2)
    }
}
