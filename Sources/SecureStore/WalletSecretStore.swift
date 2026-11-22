import Foundation
import WalletCore

public struct WalletSecretStore: Sendable {
    private let store: any SecretStore

    public init(store: any SecretStore) {
        self.store = store
    }

    public func save(_ secret: WalletSecret, walletID: String) async throws {
        let encoded = try JSONEncoder().encode(secret)
        try await store.save(encoded, id: Self.key(for: walletID))
    }

    public func load(walletID: String, prompt: String) async throws -> WalletSecret {
        let data = try await store.load(id: Self.key(for: walletID), prompt: prompt)
        do {
            return try JSONDecoder().decode(WalletSecret.self, from: data)
        } catch {
            throw SecretStoreError.cryptography("stored secret could not be decoded")
        }
    }

    public func delete(walletID: String) async throws {
        try await store.delete(id: Self.key(for: walletID))
    }

    public func contains(walletID: String) async -> Bool {
        await store.contains(id: Self.key(for: walletID))
    }

    public func destroyKeyMaterial() async throws {
        try await store.destroyKeyMaterial()
    }

    private static func key(for walletID: String) -> String {
        "wallet.\(walletID).secret"
    }
}
