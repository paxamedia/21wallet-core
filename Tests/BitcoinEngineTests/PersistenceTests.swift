import Foundation
import Testing
import WalletCore

@testable import BitcoinEngine

@Suite("Persistence")
struct PersistenceTests {
    private static var networkTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["NETWORK_TESTS"] == "1"
    }

    private static var broadcastTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["BROADCAST_TESTS"] == "1"
    }

    private static var fundedPhrase: String? {
        ProcessInfo.processInfo.environment["SIGNET_PHRASE"]
    }

    private let signetAddress = "tb1q6rz28mcfaxtmd6v789l9rrlrusdprr9pqcpvkl"

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "kit-persistence-\(UUID().uuidString)")
    }

    private func revokeWriteAccess(toDatabaseOf metadata: WalletMetadata, in directory: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444],
            ofItemAtPath: directory.appending(path: "wallet-\(metadata.id).sqlite")
                .path(percentEncoded: false)
        )
    }

    @Test("A full scan that could not be written is not recorded as done")
    func unwritableDatabaseLeavesFullScanOutstanding() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let engine = WalletEngine(storageDirectory: directory)
        let blueprint = try await engine.createWallet(network: .signet, scriptType: .taproot)
        _ = try await engine.nextReceiveAddress(for: blueprint.metadata)
        try revokeWriteAccess(toDatabaseOf: blueprint.metadata, in: directory)

        let reopened = WalletEngine(storageDirectory: directory)

        _ = try? await reopened.revealNewReceiveAddress(for: blueprint.metadata)

        await #expect(throws: WalletStorageError.self) {
            try await reopened.commit(for: blueprint.metadata, fullScan: true)
        }

        let recorded = await reopened.hasCompletedFullScan(blueprint.metadata)
        #expect(!recorded, "a scan that was not saved must not be on record as complete")
    }

    @Test("A receive address is not handed out when it could not be recorded")
    func unwritableDatabaseWithholdsReceiveAddress() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let engine = WalletEngine(storageDirectory: directory)
        let blueprint = try await engine.createWallet(network: .signet, scriptType: .taproot)
        _ = try await engine.nextReceiveAddress(for: blueprint.metadata)
        try revokeWriteAccess(toDatabaseOf: blueprint.metadata, in: directory)

        let reopened = WalletEngine(storageDirectory: directory)
        await #expect(throws: WalletStorageError.self) {
            try await reopened.revealNewReceiveAddress(for: blueprint.metadata)
        }
    }

    @Test("The signing wallet reveals as far as the watch wallet, not to a constant")
    func signingRevealFollowsDerivationHistory() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let engine = WalletEngine(storageDirectory: directory)
        let blueprint = try await engine.createWallet(network: .signet, scriptType: .nativeSegwit)

        for _ in 1...120 {
            _ = try await engine.revealNewReceiveAddress(for: blueprint.metadata)
        }

        let target = try await engine.signingRevealTarget(for: blueprint.metadata)
        #expect(target.external >= 120, "the reveal must follow the wallet's own derivation")
        #expect(target.change == 100, "an untouched change keychain still gets the floor")
    }

    @Test(
        "A restored wallet survives a restart and the reopened wallet can spend",
        .enabled(
            if: PersistenceTests.broadcastTestsEnabled && PersistenceTests.fundedPhrase != nil
        )
    )
    func chainStateSurvivesRestartAndSpends() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let phrase = try #require(Self.fundedPhrase)
        let source = EsploraChainSource.mempoolSpace(for: .signet)

        let engine = WalletEngine(storageDirectory: directory)
        let blueprint = try await engine.restoreWallet(
            mnemonic: phrase, network: .signet, scriptType: .nativeSegwit
        )
        let scanned = try await engine.sync(blueprint.metadata, using: source)
        try #require(scanned.total.sats > 2_000, "SIGNET_PHRASE names an empty wallet")
        #expect(await engine.hasCompletedFullScan(blueprint.metadata))

        let reopened = WalletEngine(storageDirectory: directory)
        let cached = try await reopened.cachedSnapshot(blueprint.metadata)
        #expect(cached.total == scanned.total, "the balance must reappear without the network")
        #expect(cached.confirmed == scanned.confirmed)
        #expect(
            cached.transactions.map(\.id) == scanned.transactions.map(\.id),
            "history must survive the restart rather than be rediscovered"
        )

        let draft = try await reopened.buildDraft(
            for: blueprint.metadata,
            recipient: signetAddress,
            amount: Amount(sats: 1_000),
            feeRate: 2
        )
        let txid = try await reopened.signAndBroadcast(
            draft: draft.id,
            for: blueprint.metadata,
            secret: .mnemonic(words: phrase, passphrase: nil),
            using: source
        )
        #expect(txid.count == 64)

        let after = try await reopened.sync(blueprint.metadata, using: source)
        #expect(
            after.transactions.contains { $0.id == txid },
            "the wallet must know about its own spend"
        )
        #expect(after.total.sats < scanned.total.sats, "the payment and its fee must have left")

        let again = WalletEngine(storageDirectory: directory)
        let final = try await again.cachedSnapshot(blueprint.metadata)
        #expect(final.total == after.total, "change must come back off disk with everything else")
        #expect(final.transactions.contains { $0.id == txid })
    }
}
