import Foundation
import Testing
import WalletCore

@testable import BitcoinEngine

@Suite("Mainnet probe")
struct MainnetProbeTests {
    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["MAINNET_PROBE"] == "1"
    }

    @Test("The public test wallet syncs against mainnet", .enabled(if: MainnetProbeTests.enabled))
    func syncsAgainstMainnet() async throws {
        let directory = URL.temporaryDirectory.appending(path: "kit-mainnet-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = WalletEngine(storageDirectory: directory)

        let blueprint = try await engine.restoreWallet(
            mnemonic: DerivationVectorTests.testMnemonic,
            network: .mainnet,
            scriptType: .nativeSegwit
        )
        let address = try await engine.nextReceiveAddress(for: blueprint.metadata)
        #expect(address.hasPrefix("bc1q"))

        let progressCount = ProgressBox()
        let start = Date()
        let snapshot = try await engine.sync(
            blueprint.metadata,
            using: EsploraChainSource.mempoolSpace(for: .mainnet)
        ) { _ in progressCount.increment() }

        print("[mainnet] \(Int(Date().timeIntervalSince(start)))s, "
            + "balance=\(snapshot.total.sats) sats, txs=\(snapshot.transactions.count), "
            + "progress callbacks=\(progressCount.value)")

        #expect(!snapshot.transactions.isEmpty, "the public test wallet has mainnet history")
        #expect(progressCount.value > 0, "scan progress must be reported")
        #expect(snapshot.confirmed.sats <= snapshot.total.sats)
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
