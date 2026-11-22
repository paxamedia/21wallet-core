import BitcoinDevKit
import Testing
import WalletCore

@testable import BitcoinEngine

@Suite("Derivation vectors")
struct DerivationVectorTests {
    static let testMnemonic = """
        abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about
        """

    private func addresses(
        network: BitcoinNetwork,
        scriptType: ScriptType,
        passphrase: String? = nil,
        count: Int = 1
    ) throws -> (receive: [String], change: String) {
        let descriptors = try DescriptorFactory.descriptors(
            mnemonic: Self.testMnemonic,
            passphrase: passphrase,
            network: network,
            scriptType: scriptType
        )
        let wallet = try Wallet(
            descriptor: descriptors.external,
            changeDescriptor: descriptors.change,
            network: network.bdkNetwork,
            persister: try Persister.newInMemory()
        )
        let receive = (0..<count).map { _ in
            wallet.revealNextAddress(keychain: .external).address.description
        }
        let change = wallet.revealNextAddress(keychain: .internal).address.description
        return (receive, change)
    }

    @Test("BIP84 mainnet matches the published vector")
    func bip84Mainnet() throws {
        let derived = try addresses(network: .mainnet, scriptType: .nativeSegwit, count: 2)
        #expect(derived.receive[0] == "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu")
        #expect(derived.receive[1] == "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g")
        #expect(derived.change == "bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el")
    }

    @Test("BIP86 Taproot mainnet matches the published vector")
    func bip86Mainnet() throws {
        let derived = try addresses(network: .mainnet, scriptType: .taproot, count: 2)
        #expect(
            derived.receive[0]
                == "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr"
        )
        #expect(
            derived.receive[1]
                == "bc1p4qhjn9zdvkux4e44uhx8tc55attvtyu358kutcqkudyccelu0was9fqzwh"
        )
        #expect(
            derived.change
                == "bc1p3qkhfews2uk44qtvauqyr2ttdsw7svhkl9nkm9s9c3x4ax5h60wqwruhk7"
        )
    }

    @Test("Test networks derive under coin type 1 with a tb1 prefix")
    func signetUsesTestCoinType() throws {
        let derived = try addresses(network: .signet, scriptType: .nativeSegwit)
        #expect(derived.receive[0] == "tb1q6rz28mcfaxtmd6v789l9rrlrusdprr9pqcpvkl")
        #expect(derived.receive[0].hasPrefix(BitcoinNetwork.signet.bech32HRP))
    }

    @Test("Taproot and native SegWit derive different wallets from the same seed")
    func scriptTypesDiverge() throws {
        let segwit = try addresses(network: .mainnet, scriptType: .nativeSegwit)
        let taproot = try addresses(network: .mainnet, scriptType: .taproot)
        #expect(segwit.receive[0] != taproot.receive[0])
        #expect(segwit.receive[0].hasPrefix("bc1q"))
        #expect(taproot.receive[0].hasPrefix("bc1p"))
    }

    @Test("A BIP39 passphrase produces an entirely different wallet")
    func passphraseChangesWallet() throws {
        let plain = try addresses(network: .mainnet, scriptType: .nativeSegwit)
        let passphrased = try addresses(
            network: .mainnet, scriptType: .nativeSegwit, passphrase: "wallet256"
        )
        #expect(plain.receive[0] != passphrased.receive[0])
    }

    @Test("An empty passphrase is identical to no passphrase")
    func emptyPassphraseIsNoPassphrase() throws {
        let none = try addresses(network: .mainnet, scriptType: .nativeSegwit, passphrase: nil)
        let empty = try addresses(network: .mainnet, scriptType: .nativeSegwit, passphrase: "")
        #expect(none.receive[0] == empty.receive[0])
    }

    @Test("Derivation is deterministic across repeated runs")
    func derivationIsDeterministic() throws {
        let first = try addresses(network: .mainnet, scriptType: .taproot)
        let second = try addresses(network: .mainnet, scriptType: .taproot)
        #expect(first.receive[0] == second.receive[0])
        #expect(first.change == second.change)
    }
}
