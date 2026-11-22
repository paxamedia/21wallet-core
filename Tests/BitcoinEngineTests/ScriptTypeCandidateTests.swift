import Testing
import WalletCore

@testable import BitcoinEngine

@Suite("Script type detection")
struct ScriptTypeCandidateTests {
    private func candidate(
        _ scriptType: ScriptType, sats: Int64, transactions: Int
    ) -> ScriptTypeCandidate {
        ScriptTypeCandidate(
            scriptType: scriptType, balance: Amount(sats: sats), transactionCount: transactions
        )
    }

    @Test("A funded account beats one with more history")
    func fundsBeatHistory() {
        let drained = candidate(.nativeSegwit, sats: 0, transactions: 3)
        let funded = candidate(.taproot, sats: 250_000, transactions: 1)

        #expect(ScriptTypeCandidate.best(of: [drained, funded]) == .taproot)
        #expect(
            ScriptTypeCandidate.best(of: [funded, drained]) == .taproot,
            "the order the scans happened to finish in must not decide it"
        )
    }

    @Test("Between two accounts that both hold something, the larger balance wins")
    func largerBalanceWins() {
        let small = candidate(.nativeSegwit, sats: 1_000, transactions: 9)
        let large = candidate(.taproot, sats: 900_000, transactions: 1)
        #expect(ScriptTypeCandidate.best(of: [small, large]) == .taproot)
    }

    @Test("Between two empty accounts, the one used more wins")
    func historyDecidesAmongEmptyAccounts() {
        let quiet = candidate(.taproot, sats: 0, transactions: 1)
        let busy = candidate(.nativeSegwit, sats: 0, transactions: 12)
        #expect(ScriptTypeCandidate.best(of: [quiet, busy]) == .nativeSegwit)
    }

    @Test("A phrase with no history anywhere resolves to nothing")
    func noHistoryAnywhere() {
        let untouched = [
            candidate(.nativeSegwit, sats: 0, transactions: 0),
            candidate(.taproot, sats: 0, transactions: 0),
        ]
        #expect(ScriptTypeCandidate.best(of: untouched) == nil)
        #expect(
            ScriptTypeCandidate.best(of: []) == nil,
            "no candidate scanned successfully is not the same as no history"
        )
    }

    @Test("A tie is broken by tieBreak, not by argument order")
    func tieIsExplicit() {
        let taproot = candidate(.taproot, sats: 5_000, transactions: 2)
        let segwit = candidate(.nativeSegwit, sats: 5_000, transactions: 2)
        let stated = ScriptTypeCandidate.tieBreak.first

        #expect(ScriptTypeCandidate.best(of: [taproot, segwit]) == stated)
        #expect(ScriptTypeCandidate.best(of: [segwit, taproot]) == stated)
    }

    @Test("A balance still in the mempool counts as holding money")
    func pendingCountsAsFunded() {
        let arriving = WalletSnapshot(
            total: Amount(sats: 40_000),
            confirmed: .zero,
            transactions: [
                WalletTransaction(
                    id: "pending", netAmount: Amount(sats: 40_000), isConfirmed: false,
                    timestamp: nil
                )
            ]
        )
        let emptied = WalletSnapshot(
            total: .zero,
            confirmed: .zero,
            transactions: [
                WalletTransaction(id: "in", netAmount: Amount(sats: 10), isConfirmed: true, timestamp: nil),
                WalletTransaction(id: "out", netAmount: Amount(sats: -10), isConfirmed: true, timestamp: nil),
            ]
        )

        let best = ScriptTypeCandidate.best(of: [
            ScriptTypeCandidate(scriptType: .nativeSegwit, snapshot: emptied),
            ScriptTypeCandidate(scriptType: .taproot, snapshot: arriving),
        ])
        #expect(best == .taproot)
    }
}
