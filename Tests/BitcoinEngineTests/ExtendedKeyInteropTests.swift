import BitcoinDevKit
import Foundation
import Testing

@testable import BitcoinEngine
@testable import WalletCore

@Suite("Extended key interop")
struct ExtendedKeyInteropTests {
    private let phrase = """
        abandon abandon abandon abandon abandon abandon abandon abandon \
        abandon abandon abandon about
        """

    private func masterKey(_ network: BitcoinNetwork) throws -> DescriptorSecretKey {
        let mnemonic = try Mnemonic.fromString(mnemonic: phrase)
        return DescriptorSecretKey(
            networkKind: network.bdkNetworkKind,
            mnemonic: mnemonic,
            password: nil
        )
    }

    private func serialisation(of key: DescriptorSecretKey) -> String {
        var text = key.description
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            text = String(text[text.index(after: close)...])
        }
        return String(text.split(separator: "/").first ?? "")
    }

    @Test("A master key from BDK parses, and reports depth zero")
    func masterKeyParses() throws {
        let text = serialisation(of: try masterKey(.mainnet))
        let parsed = try ExtendedPrivateKey(text)

        #expect(parsed.isMaster, "BDK's master key did not read as depth 0")
        #expect(parsed.network == .mainnet)
        #expect(parsed.normalized == text, "a plain xprv should normalise to itself")
    }

    @Test("A testnet master key is recognised as testnet")
    func testnetKeyParses() throws {
        let text = serialisation(of: try masterKey(.signet))
        let parsed = try ExtendedPrivateKey(text)

        #expect(parsed.network == .testnet)
        #expect(parsed.isMaster)
    }

    @Test("What the parser normalises to is still a key BDK accepts")
    func normalisedKeyIsStillValid() throws {
        let text = serialisation(of: try masterKey(.mainnet))
        let parsed = try ExtendedPrivateKey(text)

        let rebuilt = try DescriptorSecretKey.fromString(privateKey: parsed.normalized)
        #expect(serialisation(of: rebuilt) == text)
    }

    @Test("An account-level key from BDK reports depth three")
    func accountKeyParses() throws {
        let path = try DerivationPath(path: "m/84h/0h/0h")
        let account = try masterKey(.mainnet).derive(path: path)
        let parsed = try ExtendedPrivateKey(serialisation(of: account))

        #expect(
            parsed.isAccountLevel,
            "a key derived three levels down must read as an account key, or importing it will derive the wrong addresses"
        )
        #expect(!parsed.isMaster)
    }

    @Test("The public half is refused with the reason a user needs")
    func publicKeyIsRefused() throws {
        let publicKey = try masterKey(.mainnet).asPublic()
        let text = String(publicKey.description.split(separator: "/").first ?? "")

        #expect(throws: ExtendedPrivateKey.ParseError.notAPrivateKey) {
            try ExtendedPrivateKey(text)
        }
    }
}
