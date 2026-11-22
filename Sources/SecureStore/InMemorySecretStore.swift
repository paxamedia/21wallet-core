import Foundation

// Tests and previews only. Never a fallback when the Secure Enclave is unavailable.
public actor InMemorySecretStore: SecretStore {
    private var secrets: [String: Data] = [:]

    private var nextLoadError: SecretStoreError?

    public init() {}

    public func save(_ secret: Data, id: String) {
        secrets[id] = secret
    }

    public func load(id: String, prompt: String) throws -> Data {
        if let error = nextLoadError {
            nextLoadError = nil
            throw error
        }
        guard let secret = secrets[id] else { throw SecretStoreError.notFound }
        return secret
    }

    public func delete(id: String) {
        secrets.removeValue(forKey: id)
    }

    public func contains(id: String) -> Bool {
        secrets[id] != nil
    }

    public func destroyKeyMaterial() {
        secrets.removeAll()
    }

    public func failNextLoad(with error: SecretStoreError) {
        nextLoadError = error
    }
}
