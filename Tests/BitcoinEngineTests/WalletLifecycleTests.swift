import Foundation
import Testing
import WalletCore

@testable import BitcoinEngine

@Suite("Wallet lifecycle")
struct WalletLifecycleTests {
    private let engine = WalletEngine(
        storageDirectory: URL.temporaryDirectory.appending(path: "kit-lifecycle-\(UUID().uuidString)")
    )

    @Test("A created wallet is valid, unverified, and carries no secret in its metadata")
    func createWallet() async throws {
        let blueprint = try await engine.createWallet(network: .signet, scriptType: .taproot)

        let words = try #require(blueprint.secret.mnemonicWords, "a created wallet must have a phrase")
        #expect(MnemonicNormalizer.isValid(words))
        #expect(MnemonicNormalizer.wordCount(words) == 12)
        #expect(blueprint.metadata.externalDescriptor.isEmpty == false)
        #expect(blueprint.metadata.network == .signet)
        #expect(!blueprint.metadata.externalDescriptor.contains("tprv"))
        #expect(!blueprint.metadata.internalDescriptor.contains("tprv"))
    }

    @Test("Every created wallet is different")
    func createdWalletsAreUnique() async throws {
        let first = try await engine.createWallet(network: .signet, scriptType: .taproot)
        let second = try await engine.createWallet(network: .signet, scriptType: .taproot)
        #expect(first.secret.mnemonicWords != second.secret.mnemonicWords)
        #expect(first.metadata.externalDescriptor != second.metadata.externalDescriptor)
        #expect(first.metadata.id != second.metadata.id)
    }

    @Test("Restoring the same phrase reproduces the same wallet")
    func restoreIsDeterministic() async throws {
        let created = try await engine.createWallet(network: .signet, scriptType: .taproot)
        let restored = try await engine.restoreWallet(
            mnemonic: created.secret.mnemonicWords ?? "", network: .signet, scriptType: .taproot
        )

        #expect(restored.metadata.externalDescriptor == created.metadata.externalDescriptor)
        #expect(
            try await engine.receiveAddress(for: restored.metadata)
                == engine.receiveAddress(for: created.metadata)
        )
    }

    @Test("A passphrase restores a different wallet from the same words")
    func passphraseChangesRestore() async throws {
        let created = try await engine.createWallet(network: .signet, scriptType: .taproot)
        let withPassphrase = try await engine.restoreWallet(
            mnemonic: created.secret.mnemonicWords ?? "", passphrase: "wallet256", network: .signet, scriptType: .taproot
        )
        #expect(withPassphrase.metadata.externalDescriptor != created.metadata.externalDescriptor)
    }

    @Test("Receive addresses come from public descriptors and match the derivation vector")
    func receiveAddressFromPublicDescriptorsOnly() async throws {
        let restored = try await engine.restoreWallet(
            mnemonic: DerivationVectorTests.testMnemonic,
            network: .mainnet,
            scriptType: .nativeSegwit
        )
        let address = try await engine.receiveAddress(for: restored.metadata, index: 0)
        #expect(address == "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu")

        let second = try await engine.receiveAddress(for: restored.metadata, index: 1)
        #expect(second == "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g")
    }

    @Test("Decoy words are real BIP39 words that avoid the user's own phrase")
    func decoyWords() async throws {
        let created = try await engine.createWallet(network: .signet, scriptType: .taproot)
        let used = Set((created.secret.mnemonicWords ?? "").split(separator: " ").map(String.init))

        let decoys = await engine.decoyWords(excluding: used, count: 9)

        #expect(decoys.count == 9)
        #expect(Set(decoys).isDisjoint(with: used))
        #expect(Set(decoys).count == 9, "decoys must not repeat")
    }
}

extension WalletLifecycleTests {
    @Test(
        "Every BIP39 length can be created and restores to the same wallet",
        arguments: MnemonicLength.allCases
    )
    func everyLengthRoundTrips(_ length: MnemonicLength) async throws {
        let created = try await engine.createWallet(
            network: .signet, scriptType: .nativeSegwit, length: length
        )
        let words = try #require(created.secret.mnemonicWords)
        #expect(MnemonicNormalizer.wordCount(words) == length.rawValue)
        #expect(MnemonicNormalizer.isValid(words))

        let restored = try await engine.restoreWallet(
            mnemonic: words, network: .signet, scriptType: .nativeSegwit
        )
        #expect(restored.metadata.externalDescriptor == created.metadata.externalDescriptor)
    }

    @Test("Entropy matches what BIP39 says each length carries")
    func entropyBits() {
        #expect(MnemonicLength.twelve.entropyBits == 128)
        #expect(MnemonicLength.fifteen.entropyBits == 160)
        #expect(MnemonicLength.eighteen.entropyBits == 192)
        #expect(MnemonicLength.twentyOne.entropyBits == 224)
        #expect(MnemonicLength.twentyFour.entropyBits == 256)
    }
}
