import Foundation

public enum WalletSecret: Sendable, Equatable {
    case mnemonic(words: String, passphrase: String?)
    case extendedKey(String)

    public var mnemonicWords: String? {
        guard case .mnemonic(let words, _) = self else { return nil }
        return words
    }

    public var passphrase: String? {
        guard case .mnemonic(_, let passphrase) = self else { return nil }
        return passphrase
    }

    public var extendedPrivateKey: String? {
        guard case .extendedKey(let key) = self else { return nil }
        return key
    }

    public var hasRecoveryPhrase: Bool {
        if case .mnemonic = self { return true }
        return false
    }
}

extension WalletSecret: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, mnemonic, passphrase, extendedKey
    }

    private enum Kind: String, Codable {
        case mnemonic, extendedKey
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mnemonic(let words, let passphrase):
            try container.encode(Kind.mnemonic, forKey: .kind)
            try container.encode(words, forKey: .mnemonic)
            try container.encodeIfPresent(passphrase, forKey: .passphrase)
        case .extendedKey(let key):
            try container.encode(Kind.extendedKey, forKey: .kind)
            try container.encode(key, forKey: .extendedKey)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        guard let kind = try container.decodeIfPresent(Kind.self, forKey: .kind) else {
            self = .mnemonic(
                words: try container.decode(String.self, forKey: .mnemonic),
                passphrase: try container.decodeIfPresent(String.self, forKey: .passphrase)
            )
            return
        }

        switch kind {
        case .mnemonic:
            self = .mnemonic(
                words: try container.decode(String.self, forKey: .mnemonic),
                passphrase: try container.decodeIfPresent(String.self, forKey: .passphrase)
            )
        case .extendedKey:
            self = .extendedKey(try container.decode(String.self, forKey: .extendedKey))
        }
    }
}
