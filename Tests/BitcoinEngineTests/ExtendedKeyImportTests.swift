import BitcoinDevKit
import Testing
import WalletCore

@testable import BitcoinEngine

@Suite("Extended key import")
struct ExtendedKeyImportTests {
    private let phrase = DerivationVectorTests.testMnemonic

    private func addresses(_ descriptors: WalletDescriptors, network: BitcoinNetwork) throws
        -> (receive: String, change: String)
    {
        let wallet = try Wallet(
            descriptor: descriptors.external,
            changeDescriptor: descriptors.change,
            network: network.bdkNetwork,
            persister: try Persister.newInMemory()
        )
        return (
            wallet.revealNextAddress(keychain: .external).address.description,
            wallet.revealNextAddress(keychain: .internal).address.description
        )
    }

    private func serialisation(of key: DescriptorSecretKey) -> String {
        var text = key.description
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            text = String(text[text.index(after: close)...])
        }
        return String(text.split(separator: "/").first ?? "")
    }

    private func masterKey(_ network: BitcoinNetwork) throws -> DescriptorSecretKey {
        DescriptorSecretKey(
            networkKind: network.bdkNetworkKind,
            mnemonic: try Mnemonic.fromString(mnemonic: phrase),
            password: nil
        )
    }

    @Test(
        "An account key derives the same addresses as the phrase it came from",
        arguments: [ScriptType.nativeSegwit, .taproot]
    )
    func accountKeyMatchesPhrase(_ scriptType: ScriptType) throws {
        let network = BitcoinNetwork.mainnet
        let purpose = scriptType == .taproot ? 86 : 84

        let account = try masterKey(network).derive(
            path: try DerivationPath(path: "m/\(purpose)h/0h/0h")
        )

        let fromPhrase = try DescriptorFactory.descriptors(
            mnemonic: phrase, network: network, scriptType: scriptType
        )
        let fromKey = try DescriptorFactory.descriptors(
            extendedKey: serialisation(of: account), network: network, scriptType: scriptType
        )

        let expected = try addresses(fromPhrase, network: network)
        let imported = try addresses(fromKey, network: network)

        #expect(
            imported.receive == expected.receive,
            "account key derived a different receive address than the phrase"
        )
        #expect(imported.change == expected.change, "change addresses diverged")
    }

    @Test(
        "A master key derives the same addresses as the phrase it came from",
        arguments: [ScriptType.nativeSegwit, .taproot]
    )
    func masterKeyMatchesPhrase(_ scriptType: ScriptType) throws {
        let network = BitcoinNetwork.mainnet

        let fromPhrase = try DescriptorFactory.descriptors(
            mnemonic: phrase, network: network, scriptType: scriptType
        )
        let fromKey = try DescriptorFactory.descriptors(
            extendedKey: serialisation(of: try masterKey(network)),
            network: network,
            scriptType: scriptType
        )

        #expect(try addresses(fromKey, network: network) == addresses(fromPhrase, network: network))
    }

    @Test("The same holds on a test network")
    func matchesOnSignet() throws {
        let network = BitcoinNetwork.signet
        let account = try masterKey(network).derive(path: try DerivationPath(path: "m/84h/1h/0h"))

        let fromPhrase = try DescriptorFactory.descriptors(
            mnemonic: phrase, network: network, scriptType: .nativeSegwit
        )
        let fromKey = try DescriptorFactory.descriptors(
            extendedKey: serialisation(of: account), network: network, scriptType: .nativeSegwit
        )

        #expect(try addresses(fromKey, network: network) == addresses(fromPhrase, network: network))
    }

    @Test("Treating an account key as a master key would derive different addresses")
    func doubleDerivationIsDetectablyWrong() throws {
        let network = BitcoinNetwork.mainnet
        let account = try masterKey(network).derive(path: try DerivationPath(path: "m/84h/0h/0h"))
        let accountKey = try DescriptorSecretKey.fromString(
            privateKey: try ExtendedPrivateKey(serialisation(of: account)).normalized
        )

        let doubled = WalletDescriptors(
            external: Descriptor.newBip84(
                secretKey: accountKey, keychainKind: .external, networkKind: network.bdkNetworkKind
            ),
            change: Descriptor.newBip84(
                secretKey: accountKey, keychainKind: .internal, networkKind: network.bdkNetworkKind
            )
        )
        let correct = try DescriptorFactory.descriptors(
            mnemonic: phrase, network: network, scriptType: .nativeSegwit
        )

        #expect(
            try addresses(doubled, network: network).receive
                != addresses(correct, network: network).receive,
            "if these matched, depth would not matter and this guard would be pointless"
        )
    }

    @Test("A key for the wrong network is refused rather than silently accepted")
    func refusesNetworkMismatch() throws {
        let testnetKey = serialisation(of: try masterKey(.signet))
        #expect(throws: WalletImportError.self) {
            try DescriptorFactory.descriptors(
                extendedKey: testnetKey, network: .mainnet, scriptType: .nativeSegwit
            )
        }

        let mainnetKey = serialisation(of: try masterKey(.mainnet))
        #expect(throws: WalletImportError.self) {
            try DescriptorFactory.descriptors(
                extendedKey: mainnetKey, network: .signet, scriptType: .nativeSegwit
            )
        }
    }

    @Test("Junk is refused before it reaches the engine")
    func refusesJunk() {
        for text in ["", "xprv", "not a key", String(repeating: "z", count: 200)] {
            #expect(throws: (any Error).self) {
                try DescriptorFactory.descriptors(
                    extendedKey: text, network: .mainnet, scriptType: .nativeSegwit
                )
            }
        }
    }
}
