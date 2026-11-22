import Foundation
import Testing
import WalletCore

@testable import BitcoinEngine

@Suite("Chain sync")
struct ChainSyncTests {
    private static var networkTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["NETWORK_TESTS"] == "1"
    }

    private func temporaryEngine() -> (WalletEngine, URL) {
        let directory = URL.temporaryDirectory.appending(path: "kit-tests-\(UUID().uuidString)")
        return (WalletEngine(storageDirectory: directory), directory)
    }

    @Test("Esplora endpoints match the network")
    func endpointsPerNetwork() {
        #expect(EsploraChainSource.mempoolSpace(for: .mainnet).url == "https://mempool.space/api")
        #expect(
            EsploraChainSource.mempoolSpace(for: .signet).url == "https://mempool.space/signet/api"
        )
        #expect(
            EsploraChainSource.mempoolSpace(for: .testnet).url
                == "https://mempool.space/testnet/api"
        )
    }

    @Test("The privacy note names what the server learns")
    func privacyNoteIsExplicit() {
        let note = EsploraChainSource.mempoolSpace(for: .signet).privacyNote
        #expect(note.contains("every address"))
        #expect(note.contains("IP"))
    }

    @Test("A wallet with no chain data reports an empty snapshot without touching the network")
    func cachedSnapshotOfFreshWallet() async throws {
        let (engine, directory) = temporaryEngine()
        defer { try? FileManager.default.removeItem(at: directory) }

        let blueprint = try await engine.createWallet(network: .signet, scriptType: .taproot)
        let snapshot = try await engine.cachedSnapshot(blueprint.metadata)

        #expect(snapshot.total == .zero)
        #expect(snapshot.transactions.isEmpty)
        #expect(!snapshot.hasPending)
    }

    @Test(
        "A signet wallet syncs against a real Esplora server",
        .enabled(if: ChainSyncTests.networkTestsEnabled)
    )
    func syncsAgainstSignet() async throws {
        let (engine, directory) = temporaryEngine()
        defer { try? FileManager.default.removeItem(at: directory) }

        let blueprint = try await engine.restoreWallet(
            mnemonic: DerivationVectorTests.testMnemonic,
            network: .signet,
            scriptType: .nativeSegwit
        )
        let snapshot = try await engine.sync(
            blueprint.metadata,
            using: EsploraChainSource.mempoolSpace(for: .signet)
        )

        #expect(snapshot.total.sats >= 0)
        #expect(snapshot.confirmed.sats <= snapshot.total.sats)
        for transaction in snapshot.transactions {
            #expect(!transaction.id.isEmpty)
        }

        let again = try await engine.sync(
            blueprint.metadata, using: EsploraChainSource.mempoolSpace(for: .signet)
        )
        #expect(again.total == snapshot.total)
    }
}
