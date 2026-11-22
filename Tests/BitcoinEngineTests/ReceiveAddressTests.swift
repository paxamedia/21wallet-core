import Foundation
import Testing
import WalletCore

@testable import BitcoinEngine

@Suite("Receive addresses")
struct ReceiveAddressTests {
    private func temporaryEngine() -> (WalletEngine, URL) {
        let directory = URL.temporaryDirectory.appending(
            path: "kit-receive-\(UUID().uuidString)"
        )
        return (WalletEngine(storageDirectory: directory), directory)
    }

    @Test("The offered address is stable across repeated looks")
    func doesNotBurnAddressesOnEveryLook() async throws {
        let (engine, directory) = temporaryEngine()
        defer { try? FileManager.default.removeItem(at: directory) }

        let blueprint = try await engine.createWallet(network: .signet, scriptType: .taproot)
        let first = try await engine.nextReceiveAddress(for: blueprint.metadata)
        let second = try await engine.nextReceiveAddress(for: blueprint.metadata)

        #expect(first == second)
        #expect(first.hasPrefix("tb1p"))
    }

    @Test("Asking for a fresh address gives a different one every time")
    func rotationProducesNewAddresses() async throws {
        let (engine, directory) = temporaryEngine()
        defer { try? FileManager.default.removeItem(at: directory) }

        let blueprint = try await engine.createWallet(network: .signet, scriptType: .taproot)
        let initial = try await engine.nextReceiveAddress(for: blueprint.metadata)

        var seen: Set<String> = [initial]
        for _ in 1...4 {
            seen.insert(try await engine.revealNewReceiveAddress(for: blueprint.metadata))
        }
        #expect(seen.count == 5, "each request must yield an unused address")
    }

    @Test("Revealed addresses survive a relaunch")
    func revealedIndexPersists() async throws {
        let directory = URL.temporaryDirectory.appending(
            path: "kit-receive-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let engine = WalletEngine(storageDirectory: directory)
        let blueprint = try await engine.createWallet(network: .signet, scriptType: .taproot)
        let first = try await engine.nextReceiveAddress(for: blueprint.metadata)
        let second = try await engine.revealNewReceiveAddress(for: blueprint.metadata)

        let reopened = WalletEngine(storageDirectory: directory)
        let third = try await reopened.revealNewReceiveAddress(for: blueprint.metadata)
        #expect(third != first)
        #expect(third != second)

        #expect(try await reopened.nextReceiveAddress(for: blueprint.metadata) == first)
    }

    @Test("Addresses come from the external keychain, never the change keychain")
    func usesExternalKeychain() async throws {
        let (engine, directory) = temporaryEngine()
        defer { try? FileManager.default.removeItem(at: directory) }

        let blueprint = try await engine.restoreWallet(
            mnemonic: DerivationVectorTests.testMnemonic,
            network: .mainnet,
            scriptType: .nativeSegwit
        )
        let address = try await engine.nextReceiveAddress(for: blueprint.metadata)
        #expect(address == "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu")
    }
}
