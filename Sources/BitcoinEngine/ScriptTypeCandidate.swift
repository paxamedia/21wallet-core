import WalletCore

struct ScriptTypeCandidate: Equatable, Sendable {
    let scriptType: ScriptType
    let balance: Amount
    let transactionCount: Int

    init(scriptType: ScriptType, balance: Amount, transactionCount: Int) {
        self.scriptType = scriptType
        self.balance = balance
        self.transactionCount = transactionCount
    }

    init(scriptType: ScriptType, snapshot: WalletSnapshot) {
        self.init(
            scriptType: scriptType,
            balance: snapshot.total,
            transactionCount: snapshot.transactions.count
        )
    }

    var hasHistory: Bool { transactionCount > 0 || balance.sats > 0 }

    var isFunded: Bool { balance.sats > 0 }
}

extension ScriptTypeCandidate {
    static let tieBreak: [ScriptType] = [.nativeSegwit, .taproot]

    static func best(of candidates: [ScriptTypeCandidate]) -> ScriptType? {
        candidates.filter(\.hasHistory).sorted(by: precedes).first?.scriptType
    }

    private static func precedes(_ a: Self, _ b: Self) -> Bool {
        if a.isFunded != b.isFunded { return a.isFunded }
        if a.balance.sats != b.balance.sats { return a.balance.sats > b.balance.sats }
        if a.transactionCount != b.transactionCount {
            return a.transactionCount > b.transactionCount
        }
        let ranks = (
            tieBreak.firstIndex(of: a.scriptType) ?? tieBreak.count,
            tieBreak.firstIndex(of: b.scriptType) ?? tieBreak.count
        )
        return ranks.0 < ranks.1
    }
}
