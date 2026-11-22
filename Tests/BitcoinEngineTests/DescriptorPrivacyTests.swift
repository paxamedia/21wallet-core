import BitcoinDevKit
import Testing
import WalletCore

@testable import BitcoinEngine

@Suite("Descriptor privacy")
struct DescriptorPrivacyTests {
    private static let phrase = DerivationVectorTests.testMnemonic

    private func descriptors(_ scriptType: ScriptType, _ network: BitcoinNetwork) throws
        -> WalletDescriptors
    {
        try DescriptorFactory.descriptors(
            mnemonic: Self.phrase, network: network, scriptType: scriptType
        )
    }

    @Test("The public descriptor contains an xpub and no private key")
    func publicFormIsSafeToPersist() throws {
        for scriptType in ScriptType.allCases {
            let wallet = try descriptors(scriptType, .mainnet)
            for descriptor in [wallet.external, wallet.change] {
                let text = descriptor.description
                #expect(!text.contains("xprv"), "public descriptor leaked an xprv")
                #expect(!text.contains("tprv"), "public descriptor leaked a tprv")
                #expect(text.contains("xpub"), "expected an extended public key")
            }
        }
    }

    @Test("Test networks expose tpub, never tprv")
    func testNetworkPublicForm() throws {
        let wallet = try descriptors(.nativeSegwit, .signet)
        let text = wallet.external.description
        #expect(text.contains("tpub"))
        #expect(!text.contains("tprv"))
    }

    @Test("The secret form is the one that carries the private key")
    func secretFormCarriesThePrivateKey() throws {
        let wallet = try descriptors(.taproot, .mainnet)
        #expect(wallet.external.toStringWithSecret().contains("xprv"))
    }

    @Test("Public and secret descriptors describe the same wallet")
    func formsAgree() throws {
        let wallet = try descriptors(.taproot, .signet)
        let watchOnly = try Descriptor(descriptor: wallet.external.description, networkKind: .test)
        let signing = try Descriptor(
            descriptor: wallet.external.toStringWithSecret(), networkKind: .test
        )
        #expect(watchOnly.description == signing.description)
    }
}
