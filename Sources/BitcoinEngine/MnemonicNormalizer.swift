import BitcoinDevKit
import Foundation

public enum MnemonicNormalizer {
    public static func normalize(_ phrase: String) -> String {
        phrase
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }
            .joined(separator: " ")
    }

    public static func isValid(_ phrase: String) -> Bool {
        (try? Mnemonic.fromString(mnemonic: normalize(phrase))) != nil
    }

    public static func wordCount(_ phrase: String) -> Int {
        normalize(phrase).split(separator: " ").count
    }
}
