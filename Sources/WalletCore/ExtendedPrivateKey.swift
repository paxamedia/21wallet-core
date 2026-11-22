import CryptoKit
import Foundation

public struct ExtendedPrivateKey: Sendable, Equatable {
    public enum Network: Sendable, Equatable {
        case mainnet
        case testnet
    }

    public enum ScriptHint: Sendable, Equatable {
        case unspecified
        case nestedSegwit
        case nativeSegwit
    }

    public let normalized: String

    public let network: Network
    public let scriptHint: ScriptHint

    public let depth: UInt8

    public var isMaster: Bool { depth == 0 }

    public var isAccountLevel: Bool { depth == 3 }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case notBase58
        case wrongLength
        case badChecksum
        case unrecognisedPrefix
        case notAPrivateKey
        case unsupportedDepth(UInt8)

        public var description: String {
            switch self {
            case .notBase58:
                "That does not look like a private key. Check for a missing or extra character."
            case .wrongLength:
                "That key is the wrong length. Part of it is missing."
            case .badChecksum:
                "That key failed its checksum, so at least one character is wrong. Copy it again rather than retyping it."
            case .unrecognisedPrefix:
                "That is not an extended private key. It should begin with xprv, yprv, zprv, tprv, uprv or vprv."
            case .notAPrivateKey:
                "That is a public key. It can watch a wallet but never spend from one, so it cannot be used to sign in."
            case .unsupportedDepth(let depth):
                "That key sits \(depth) levels down its tree, and this wallet only accepts a master key or an account key. Export the account key, or the master key, from the wallet that made it."
            }
        }
    }

    private static let privateVersions: [(bytes: UInt32, network: Network, hint: ScriptHint)] = [
        (0x0488_ADE4, .mainnet, .unspecified),  // xprv
        (0x049D_7878, .mainnet, .nestedSegwit),  // yprv
        (0x04B2_430C, .mainnet, .nativeSegwit),  // zprv
        (0x0435_8394, .testnet, .unspecified),  // tprv
        (0x044A_4E28, .testnet, .nestedSegwit),  // uprv
        (0x045F_18BC, .testnet, .nativeSegwit),  // vprv
    ]

    private static let publicVersions: Set<UInt32> = [
        0x0488_B21E, 0x049D_7CB2, 0x04B2_4746,  // xpub, ypub, zpub
        0x0435_87CF, 0x044A_5262, 0x045F_1CF6,  // tpub, upub, vpub
    ]

    public init(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = Base58.decodeChecked(trimmed) else {
            throw Base58.decode(trimmed) == nil ? ParseError.notBase58 : ParseError.badChecksum
        }
        guard decoded.count == 78 else { throw ParseError.wrongLength }

        let version = decoded.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        if Self.publicVersions.contains(version) { throw ParseError.notAPrivateKey }
        guard let match = Self.privateVersions.first(where: { $0.bytes == version }) else {
            throw ParseError.unrecognisedPrefix
        }

        let depth = decoded[4]
        guard depth == 0 || depth == 3 else { throw ParseError.unsupportedDepth(depth) }

        self.depth = depth
        self.network = match.network
        self.scriptHint = match.hint

        let standardVersion: UInt32 = match.network == .mainnet ? 0x0488_ADE4 : 0x0435_8394
        var rewritten = Data(decoded)
        rewritten[0] = UInt8((standardVersion >> 24) & 0xFF)
        rewritten[1] = UInt8((standardVersion >> 16) & 0xFF)
        rewritten[2] = UInt8((standardVersion >> 8) & 0xFF)
        rewritten[3] = UInt8(standardVersion & 0xFF)
        self.normalized = Base58.encodeChecked(rewritten)
    }
}

enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let values: [Character: Int] = {
        var map: [Character: Int] = [:]
        for (index, character) in alphabet.enumerated() { map[character] = index }
        return map
    }()

    static func decode(_ text: String) -> Data? {
        guard !text.isEmpty else { return nil }
        var bytes: [UInt8] = []
        for character in text {
            guard let value = values[character] else { return nil }
            var carry = value
            for index in bytes.indices {
                carry += Int(bytes[index]) * 58
                bytes[index] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }
        for character in text {
            guard character == alphabet[0] else { break }
            bytes.append(0)
        }
        return Data(bytes.reversed())
    }

    static func encode(_ data: Data) -> String {
        var digits: [UInt8] = []
        for byte in data {
            var carry = Int(byte)
            for index in digits.indices {
                carry += Int(digits[index]) << 8
                digits[index] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }
        var text = ""
        for byte in data {
            guard byte == 0 else { break }
            text.append(alphabet[0])
        }
        for digit in digits.reversed() { text.append(alphabet[Int(digit)]) }
        return text
    }

    static func decodeChecked(_ text: String) -> Data? {
        guard let decoded = decode(text), decoded.count > 4 else { return nil }
        let body = decoded.prefix(decoded.count - 4)
        let checksum = decoded.suffix(4)
        guard Data(SHA256.hash(data: Data(SHA256.hash(data: body))).prefix(4)) == Data(checksum)
        else { return nil }
        return Data(body)
    }

    static func encodeChecked(_ data: Data) -> String {
        let checksum = Data(SHA256.hash(data: Data(SHA256.hash(data: data))).prefix(4))
        return encode(data + checksum)
    }
}

extension ExtendedPrivateKey {
    public func resolvedScriptType(defaultingTo fallback: ScriptType) -> ScriptType {
        switch scriptHint {
        case .nativeSegwit: .nativeSegwit
        case .nestedSegwit, .unspecified: fallback
        }
    }

    public var isSupportedScriptType: Bool { scriptHint != .nestedSegwit }
}

public enum WalletImportError: Error, Equatable, CustomStringConvertible {
    case networkMismatch(keyIsTestnet: Bool, walletIsTestnet: Bool)
    case unsupportedScriptType

    public var description: String {
        switch self {
        case .networkMismatch(let keyIsTestnet, _):
            keyIsTestnet
                ? "That is a test-network key. It cannot hold real bitcoin, so it cannot be imported into a mainnet wallet."
                : "That is a mainnet key, and this wallet is on a test network. Importing it here would show real addresses on a network that cannot pay them."
        case .unsupportedScriptType:
            "That key describes a nested SegWit account, which this wallet cannot derive. Import the recovery phrase instead, or export a native SegWit or Taproot key."
        }
    }
}
