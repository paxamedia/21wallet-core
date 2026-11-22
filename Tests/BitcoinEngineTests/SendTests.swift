import Foundation
import Testing
import WalletCore

@testable import BitcoinEngine

@Suite("Sending")
struct SendTests {
    private static var networkTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["NETWORK_TESTS"] == "1"
    }

    private static var broadcastTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["BROADCAST_TESTS"] == "1"
    }

    private let signetAddress = "tb1q6rz28mcfaxtmd6v789l9rrlrusdprr9pqcpvkl"
    private let mainnetAddress = "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"

    private func temporaryEngine() -> (WalletEngine, URL) {
        let directory = URL.temporaryDirectory.appending(path: "kit-send-\(UUID().uuidString)")
        return (WalletEngine(storageDirectory: directory), directory)
    }

    @Test("A valid address for the wallet's network is accepted")
    func acceptsValidAddress() async {
        let (engine, directory) = temporaryEngine()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = await engine.validateAddress(signetAddress, network: .signet)
        #expect((try? result.get()) == signetAddress)
    }

    @Test("A BIP21 URI is accepted and reduced to its address")
    func acceptsPaymentURI() async {
        let (engine, directory) = temporaryEngine()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = await engine.validateAddress(
            "bitcoin:\(signetAddress)?amount=0.001", network: .signet
        )
        #expect((try? result.get()) == signetAddress)
    }

    @Test("A mainnet address is refused by a signet wallet")
    func rejectsWrongNetwork() async {
        let (engine, directory) = temporaryEngine()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = await engine.validateAddress(mainnetAddress, network: .signet)
        guard case .failure(let error) = result else {
            Issue.record("A mainnet address must not validate on signet")
            return
        }
        #expect(error.description.contains("Bitcoin"))
        #expect(error.description.contains("Signet"))
    }

    @Test("Nonsense and near-miss addresses are refused")
    func rejectsInvalidAddresses() async {
        let (engine, directory) = temporaryEngine()
        defer { try? FileManager.default.removeItem(at: directory) }

        for candidate in ["", "not an address", "tb1qinvalidchecksum", "lightning:lnbc1"] {
            let result = await engine.validateAddress(candidate, network: .signet)
            if case .success = result {
                Issue.record("'\(candidate)' must not validate")
            }
        }
    }

    @Test("Fee estimates map onto the offered priorities")
    func feeOptionMapping() {
        let options = FeeOptions(rates: [.fast: 30, .normal: 12, .slow: 3])
        #expect(options.rate(for: .fast) == 30)
        #expect(options.rate(for: .slow) == 3)
        #expect(FeeOptions(rates: [:]).rate(for: .normal) == 1)
        #expect(FeeOptions.fallback.rate(for: .fast) > FeeOptions.fallback.rate(for: .slow))
    }

    @Test("A draft reports what actually leaves the wallet, excluding change")
    func draftArithmetic() {
        let draft = TransactionDraft(
            recipient: signetAddress,
            amount: Amount(sats: 50_000),
            fee: Amount(sats: 1_200),
            feeRate: 8,
            inputCount: 2,
            outputs: [
                DraftOutput(id: 0, address: signetAddress, amount: Amount(sats: 50_000), isChange: false),
                DraftOutput(id: 1, address: "tb1qchange", amount: Amount(sats: 20_000), isChange: true),
            ],
            network: .signet
        )

        #expect(draft.totalSpent == Amount(sats: 51_200))
        #expect(draft.changeAmount == Amount(sats: 20_000))
        #expect(draft.feeShareOfAmount == Decimal(2.4))
        #expect(!draft.isFeeUnusuallyHigh)
    }

    @Test("A draft that pays out nothing still raises the fee warning")
    func zeroPaymentDoesNotDisarmTheFeeGuard() {
        let draft = TransactionDraft(
            recipient: signetAddress,
            amount: .zero,
            fee: Amount(sats: 4_000),
            feeRate: 300,
            inputCount: 1,
            outputs: [
                DraftOutput(id: 0, address: "tb1qchange", amount: Amount(sats: 96_000), isChange: true)
            ],
            network: .signet
        )

        #expect(draft.feeShareOfAmount == nil, "there is no share to quote against nothing")
        #expect(draft.isFeeUnusuallyHigh, "the fee being the entire cost must warn, not go quiet")
        #expect(draft.totalSpent == Amount(sats: 4_000))
    }

    @Test("A draft with no fee at all raises nothing")
    func zeroFeeIsNotFlagged() {
        let draft = TransactionDraft(
            recipient: signetAddress,
            amount: .zero,
            fee: .zero,
            feeRate: 1,
            inputCount: 1,
            outputs: [],
            network: .signet
        )
        #expect(!draft.isFeeUnusuallyHigh)
    }

    @Test("A fee that dwarfs the payment is flagged")
    func flagsDisproportionateFee() {
        let draft = TransactionDraft(
            recipient: signetAddress,
            amount: Amount(sats: 1_000),
            fee: Amount(sats: 900),
            feeRate: 200,
            inputCount: 1,
            outputs: [
                DraftOutput(id: 0, address: signetAddress, amount: Amount(sats: 1_000), isChange: false)
            ],
            network: .signet
        )
        #expect(draft.isFeeUnusuallyHigh)
        #expect(draft.changeAmount == .zero)
    }

    private static var fundedPhrase: String? {
        ProcessInfo.processInfo.environment["SIGNET_PHRASE"]
    }

    @Test(
        "An empty wallet refuses to build a transaction",
        .enabled(if: SendTests.networkTestsEnabled)
    )
    func refusesToSpendWhatIsNotThere() async throws {
        let (engine, directory) = temporaryEngine()
        defer { try? FileManager.default.removeItem(at: directory) }

        let blueprint = try await engine.createWallet(network: .signet, scriptType: .nativeSegwit)
        _ = try await engine.sync(
            blueprint.metadata, using: EsploraChainSource.mempoolSpace(for: .signet)
        )

        await #expect(throws: SendError.self) {
            try await engine.buildDraft(
                for: blueprint.metadata,
                recipient: self.signetAddress,
                amount: Amount(sats: 10_000),
                feeRate: 2
            )
        }
    }

    @Test(
        "A signet transaction builds and signs against real coins",
        .enabled(if: SendTests.networkTestsEnabled && SendTests.fundedPhrase != nil)
    )
    func buildsAndSignsOnSignet() async throws {
        let (engine, directory) = temporaryEngine()
        defer { try? FileManager.default.removeItem(at: directory) }

        let phrase = try #require(Self.fundedPhrase)
        let blueprint = try await engine.restoreWallet(
            mnemonic: phrase, network: .signet, scriptType: .nativeSegwit
        )
        let source = EsploraChainSource.mempoolSpace(for: .signet)
        let snapshot = try await engine.sync(blueprint.metadata, using: source)
        try #require(snapshot.total.sats > 2_000, "SIGNET_PHRASE names an empty wallet")

        let draft = try await engine.buildDraft(
            for: blueprint.metadata,
            recipient: signetAddress,
            amount: Amount(sats: 1_000),
            feeRate: 2
        )

        #expect(draft.amount == Amount(sats: 1_000))
        #expect(draft.fee.sats > 0)
        #expect(draft.inputCount >= 1)
        #expect(draft.outputs.contains { !$0.isChange && $0.address == signetAddress })
        #expect(draft.totalSpent.sats == draft.amount.sats + draft.fee.sats)

        let txid = try await engine.signDraft(
            draft.id, for: blueprint.metadata, secret: .mnemonic(words: phrase, passphrase: nil)
        )
        #expect(txid.count == 64, "a txid is 32 bytes of hex")

        await engine.discardDraft(draft.id)
    }

    @Test(
        "Paying the wallet's own address reads as a payment, not as change",
        .enabled(if: SendTests.networkTestsEnabled && SendTests.fundedPhrase != nil)
    )
    func selfSendIsNotReportedAsChange() async throws {
        let (engine, directory) = temporaryEngine()
        defer { try? FileManager.default.removeItem(at: directory) }

        let phrase = try #require(Self.fundedPhrase)
        let blueprint = try await engine.restoreWallet(
            mnemonic: phrase, network: .signet, scriptType: .nativeSegwit
        )
        let source = EsploraChainSource.mempoolSpace(for: .signet)
        let snapshot = try await engine.sync(blueprint.metadata, using: source)
        try #require(snapshot.total.sats > 2_000, "SIGNET_PHRASE names an empty wallet")

        let own = try await engine.nextReceiveAddress(for: blueprint.metadata)
        let draft = try await engine.buildDraft(
            for: blueprint.metadata,
            recipient: own,
            amount: Amount(sats: 1_000),
            feeRate: 2
        )

        #expect(draft.amount == Amount(sats: 1_000), "a self-send must not report as zero")
        #expect(draft.recipient == own)
        #expect(
            draft.outputs.contains { $0.address == own && !$0.isChange },
            "the address the user asked to pay is a payment even when the wallet owns it"
        )
        #expect(draft.changeAmount.sats < draft.outputs.reduce(0) { $0 + $1.amount.sats })
        #expect(draft.feeShareOfAmount != nil)

        await engine.discardDraft(draft.id)
    }

    @Test(
        "A signed signet transaction broadcasts",
        .enabled(if: SendTests.broadcastTestsEnabled && SendTests.fundedPhrase != nil)
    )
    func broadcastsOnSignet() async throws {
        let (engine, directory) = temporaryEngine()
        defer { try? FileManager.default.removeItem(at: directory) }

        let phrase = try #require(Self.fundedPhrase)
        let blueprint = try await engine.restoreWallet(
            mnemonic: phrase, network: .signet, scriptType: .nativeSegwit
        )
        let source = EsploraChainSource.mempoolSpace(for: .signet)
        _ = try await engine.sync(blueprint.metadata, using: source)

        let draft = try await engine.buildDraft(
            for: blueprint.metadata,
            recipient: signetAddress,
            amount: Amount(sats: 1_000),
            feeRate: 2
        )
        let txid = try await engine.signAndBroadcast(
            draft: draft.id,
            for: blueprint.metadata,
            secret: .mnemonic(words: phrase, passphrase: nil),
            using: source
        )
        #expect(txid.count == 64)
    }
}
