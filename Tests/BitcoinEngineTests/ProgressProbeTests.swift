import Foundation
import Testing
import WalletCore

@testable import BitcoinEngine

@Suite("Scan planning")
struct ScanPlanningTests {
    private static var networkTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["NETWORK_TESTS"] == "1"
    }

    @Test(
        "Peeking at an address first must not downgrade the first sync",
        .enabled(if: ScanPlanningTests.networkTestsEnabled)
    )
    func firstSyncIsFullEvenAfterAddressPeek() async throws {
        let directory = URL.temporaryDirectory.appending(path: "kit-plan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = WalletEngine(storageDirectory: directory)
        let blueprint = try await engine.createWallet(network: .signet, scriptType: .taproot)

        _ = try await engine.nextReceiveAddress(for: blueprint.metadata)

        let box = CallbackBox()
        _ = try await engine.sync(
            blueprint.metadata,
            using: EsploraChainSource.mempoolSpace(for: .signet)
        ) { progress in box.record(progress) }

        #expect(box.count >= 40, "first sync ran incrementally: \(box.count) scripts checked")
        #expect(box.sawFullScan, "progress must identify the scan as full")

        let second = CallbackBox()
        _ = try await engine.sync(
            blueprint.metadata,
            using: EsploraChainSource.mempoolSpace(for: .signet)
        ) { progress in second.record(progress) }
        #expect(!second.sawFullScan, "later syncs must be incremental")
    }
}

private final class CallbackBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0
    private(set) var sawFullScan = false
    func record(_ progress: ScanProgress) {
        lock.lock()
        count += 1
        if progress.isFullScan { sawFullScan = true }
        lock.unlock()
    }
}
