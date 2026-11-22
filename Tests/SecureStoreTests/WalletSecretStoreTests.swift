import Foundation
import Testing

import WalletCore

@testable import SecureStore

@Suite("WalletSecretStore")
struct WalletSecretStoreTests {
    private let phrase = """
        abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about
        """

    @Test("A stored secret round-trips unchanged")
    func roundTrip() async throws {
        let store = WalletSecretStore(store: InMemorySecretStore())
        let secret = WalletSecret.mnemonic(words: phrase, passphrase: "wallet256")

        try await store.save(secret, walletID: "primary")
        let loaded = try await store.load(walletID: "primary", prompt: "Unlock")

        #expect(loaded == secret)
        #expect(loaded.passphrase == "wallet256")
    }

    @Test("A secret without a passphrase stays without one")
    func roundTripWithoutPassphrase() async throws {
        let store = WalletSecretStore(store: InMemorySecretStore())
        try await store.save(WalletSecret.mnemonic(words: phrase, passphrase: nil), walletID: "primary")

        let loaded = try await store.load(walletID: "primary", prompt: "Unlock")
        #expect(loaded.passphrase == nil)
    }

    @Test("Wallets are isolated from each other")
    func walletsAreIsolated() async throws {
        let store = WalletSecretStore(store: InMemorySecretStore())
        try await store.save(WalletSecret.mnemonic(words: phrase, passphrase: "a"), walletID: "one")
        try await store.save(WalletSecret.mnemonic(words: phrase, passphrase: "b"), walletID: "two")

        #expect(try await store.load(walletID: "one", prompt: "").passphrase == "a")
        #expect(try await store.load(walletID: "two", prompt: "").passphrase == "b")
    }

    @Test("Loading an unknown wallet reports not found, not an empty secret")
    func missingWallet() async throws {
        let store = WalletSecretStore(store: InMemorySecretStore())
        #expect(await store.contains(walletID: "ghost") == false)

        await #expect(throws: SecretStoreError.notFound) {
            try await store.load(walletID: "ghost", prompt: "Unlock")
        }
    }

    @Test("Deleting removes the secret")
    func deletion() async throws {
        let store = WalletSecretStore(store: InMemorySecretStore())
        try await store.save(WalletSecret.mnemonic(words: phrase, passphrase: nil), walletID: "primary")
        #expect(await store.contains(walletID: "primary"))

        try await store.delete(walletID: "primary")

        #expect(await store.contains(walletID: "primary") == false)
        await #expect(throws: SecretStoreError.notFound) {
            try await store.load(walletID: "primary", prompt: "Unlock")
        }
    }

    @Test("Saving twice replaces rather than duplicates")
    func overwrite() async throws {
        let store = WalletSecretStore(store: InMemorySecretStore())
        try await store.save(WalletSecret.mnemonic(words: phrase, passphrase: "old"), walletID: "primary")
        try await store.save(WalletSecret.mnemonic(words: phrase, passphrase: "new"), walletID: "primary")

        #expect(try await store.load(walletID: "primary", prompt: "").passphrase == "new")
    }

    @Test("Authentication failures propagate instead of being swallowed")
    func authenticationFailurePropagates() async throws {
        let backing = InMemorySecretStore()
        let store = WalletSecretStore(store: backing)
        try await store.save(WalletSecret.mnemonic(words: phrase, passphrase: nil), walletID: "primary")

        await backing.failNextLoad(with: .authenticationCancelled)

        await #expect(throws: SecretStoreError.authenticationCancelled) {
            try await store.load(walletID: "primary", prompt: "Unlock")
        }
    }

    @Test("Destroying the key material leaves nothing loadable, for any wallet")
    func destroyingKeyMaterial() async throws {
        let store = WalletSecretStore(store: InMemorySecretStore())
        try await store.save(WalletSecret.mnemonic(words: phrase, passphrase: nil), walletID: "primary")
        try await store.save(WalletSecret.mnemonic(words: phrase, passphrase: nil), walletID: "second")
        #expect(await store.contains(walletID: "primary"))

        try await store.destroyKeyMaterial()

        #expect(!(await store.contains(walletID: "primary")))
        #expect(!(await store.contains(walletID: "second")))
        await #expect(throws: SecretStoreError.self) {
            try await store.load(walletID: "primary", prompt: "Unlock")
        }
    }

    @Test("Corrupted stored data is reported, never silently treated as empty")
    func corruptedData() async throws {
        let backing = InMemorySecretStore()
        await backing.save(Data("not json".utf8), id: "wallet.primary.secret")
        let store = WalletSecretStore(store: backing)

        await #expect(throws: SecretStoreError.self) {
            try await store.load(walletID: "primary", prompt: "Unlock")
        }
    }
}
