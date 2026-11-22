import Foundation
import Testing

@testable import WalletCore

@Suite("Extended private keys")
struct ExtendedPrivateKeyTests {
    private func serialise(version: UInt32, depth: UInt8, keyByte: UInt8 = 0x11) -> String {
        var data = Data()
        data.append(UInt8((version >> 24) & 0xFF))
        data.append(UInt8((version >> 16) & 0xFF))
        data.append(UInt8((version >> 8) & 0xFF))
        data.append(UInt8(version & 0xFF))
        data.append(depth)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // parent fingerprint
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // child number
        data.append(Data(repeating: 0xAB, count: 32))  // chain code
        data.append(0x00)  // private key marker
        data.append(Data(repeating: keyByte, count: 32))
        return Base58.encodeChecked(data)
    }

    private let xprv: UInt32 = 0x0488_ADE4
    private let zprv: UInt32 = 0x04B2_430C
    private let vprv: UInt32 = 0x045F_18BC
    private let tprv: UInt32 = 0x0435_8394
    private let xpub: UInt32 = 0x0488_B21E

    @Test("Base58Check round-trips arbitrary payloads, leading zeros included")
    func base58RoundTrips() throws {
        let payloads: [Data] = [
            Data([0x00]),
            Data([0x00, 0x00, 0x01, 0x02]),
            Data(repeating: 0xFF, count: 78),
            Data((0..<78).map { UInt8($0) }),
        ]
        for payload in payloads {
            let encoded = Base58.encodeChecked(payload)
            #expect(Base58.decodeChecked(encoded) == payload, "round trip failed")
        }
    }

    @Test("A single wrong character fails the checksum rather than decoding to something else")
    func checksumCatchesTypos() throws {
        let key = serialise(version: xprv, depth: 0)
        var typo = Array(key)
        typo[10] = typo[10] == "a" ? "b" : "a"

        #expect(Base58.decodeChecked(String(typo)) == nil)
        #expect(throws: ExtendedPrivateKey.ParseError.badChecksum) {
            try ExtendedPrivateKey(String(typo))
        }
    }

    @Test("Depth decides whether the key is a root or an account")
    func depthIsRead() throws {
        let master = try ExtendedPrivateKey(serialise(version: xprv, depth: 0))
        #expect(master.isMaster)
        #expect(!master.isAccountLevel)

        let account = try ExtendedPrivateKey(serialise(version: xprv, depth: 3))
        #expect(account.isAccountLevel)
        #expect(!account.isMaster)
    }

    @Test("A key at an unexpected depth is refused, not guessed at")
    func refusesAmbiguousDepth() {
        for depth: UInt8 in [1, 2, 4, 5, 255] {
            #expect(throws: ExtendedPrivateKey.ParseError.unsupportedDepth(depth)) {
                try ExtendedPrivateKey(serialise(version: xprv, depth: depth))
            }
        }
    }

    @Test("SLIP-132 prefixes carry their script type and normalise to the plain spelling")
    func slip132IsUnderstood() throws {
        let native = try ExtendedPrivateKey(serialise(version: zprv, depth: 3))
        #expect(native.scriptHint == .nativeSegwit)
        #expect(native.network == .mainnet)
        #expect(native.normalized.hasPrefix("xprv"))

        let testnetNative = try ExtendedPrivateKey(serialise(version: vprv, depth: 3))
        #expect(testnetNative.scriptHint == .nativeSegwit)
        #expect(testnetNative.network == .testnet)
        #expect(testnetNative.normalized.hasPrefix("tprv"))

        let plain = try ExtendedPrivateKey(serialise(version: xprv, depth: 0))
        #expect(plain.scriptHint == .unspecified)
        #expect(plain.normalized.hasPrefix("xprv"))
    }

    @Test("Normalising changes the prefix and nothing else")
    func normalisationPreservesKeyMaterial() throws {
        let zprvKey = serialise(version: zprv, depth: 3)
        let xprvKey = serialise(version: xprv, depth: 3)

        let normalised = try ExtendedPrivateKey(zprvKey).normalized
        #expect(normalised == xprvKey, "normalisation altered more than the version bytes")

        let before = try #require(Base58.decodeChecked(zprvKey))
        let after = try #require(Base58.decodeChecked(normalised))
        #expect(before.dropFirst(4) == after.dropFirst(4))
    }

    @Test("A public key is named as such rather than reported as malformed")
    func publicKeysAreRecognised() {
        #expect(throws: ExtendedPrivateKey.ParseError.notAPrivateKey) {
            try ExtendedPrivateKey(serialise(version: xpub, depth: 0))
        }
    }

    @Test("Testnet keys are recognised as testnet")
    func testnetIsRead() throws {
        let key = try ExtendedPrivateKey(serialise(version: tprv, depth: 0))
        #expect(key.network == .testnet)
        #expect(key.normalized.hasPrefix("tprv"))
    }

    @Test("Hostile and malformed input is refused without crashing")
    func refusesJunk() {
        let junk = [
            "", " ", "\n", "0", "l", "I", "O",
            "xprv", "xprvz",
            String(repeating: "1", count: 200),
            String(repeating: "z", count: 5_000),
            "not base58 at all!!!",
            "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
            "abandon abandon abandon",
            "🙂",
        ]
        for text in junk {
            #expect(throws: (any Error).self) { try ExtendedPrivateKey(text) }
        }
    }

    @Test("Surrounding whitespace is tolerated")
    func trimsWhitespace() throws {
        let key = serialise(version: xprv, depth: 0)
        let padded = try ExtendedPrivateKey("  \n\(key)\t ")
        #expect(padded.normalized == key)
    }

    @Test("A key of the wrong length is refused even when the checksum is valid")
    func refusesWrongLength() {
        let short = Base58.encodeChecked(Data(repeating: 0x01, count: 40))
        #expect(throws: (any Error).self) { try ExtendedPrivateKey(short) }
    }
}
