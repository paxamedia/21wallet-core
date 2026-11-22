import Foundation
import Testing

@testable import SecureStore

@Suite("SecureEnclaveSecretStore")
struct SecureEnclaveSecretStoreTests {
    private static var enclaveTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["ENCLAVE_TESTS"] == "1"
    }

    @Test("Report Secure Enclave availability in this environment")
    func reportAvailability() {
        let available = SecureEnclaveSecretStore.isAvailable()
        print("[SecureStore] Secure Enclave available here: \(available)")
    }

    @Test(
        "A secret round-trips through the enclave",
        .enabled(if: SecureEnclaveSecretStoreTests.enclaveTestsEnabled)
    )
    func roundTrip() async throws {
        let store = SecureEnclaveSecretStore(
            service: "kit.tests",
            keyTag: "kit.tests.enclave-key"
        )
        let secret = Data("correct horse battery staple".utf8)

        try await store.save(secret, id: "test-secret")
        defer { Task { try? await store.delete(id: "test-secret") } }

        #expect(await store.contains(id: "test-secret"))
        let loaded = try await store.load(id: "test-secret", prompt: "Unit test")
        #expect(loaded == secret)
    }

    @Test(
        "Deleting is idempotent",
        .enabled(if: SecureEnclaveSecretStoreTests.enclaveTestsEnabled)
    )
    func deleteIsIdempotent() async throws {
        let store = SecureEnclaveSecretStore(
            service: "kit.tests",
            keyTag: "kit.tests.enclave-key"
        )
        try await store.delete(id: "never-existed")
        try await store.delete(id: "never-existed")
    }

    @Test("Reading a secret that was never stored reports not found")
    func missingSecretFailsClosed() async throws {
        let store = SecureEnclaveSecretStore(
            service: "kit.tests.empty",
            keyTag: "kit.tests.enclave-key"
        )
        #expect(await store.contains(id: "absent") == false)

        await #expect(throws: SecretStoreError.self) {
            try await store.load(id: "absent", prompt: "Unit test")
        }
    }
}
