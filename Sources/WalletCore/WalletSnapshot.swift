import Foundation

public struct WalletTransaction: Sendable, Equatable, Identifiable, Codable {
    public let id: String

    public let netAmount: Amount

    public let isConfirmed: Bool
    public let timestamp: Date?

    public init(id: String, netAmount: Amount, isConfirmed: Bool, timestamp: Date?) {
        self.id = id
        self.netAmount = netAmount
        self.isConfirmed = isConfirmed
        self.timestamp = timestamp
    }

    public var isIncoming: Bool { netAmount.sats >= 0 }
}

public struct WalletSnapshot: Sendable, Equatable {
    public let total: Amount
    public let confirmed: Amount
    public let transactions: [WalletTransaction]
    public let syncedAt: Date

    public init(
        total: Amount,
        confirmed: Amount,
        transactions: [WalletTransaction],
        syncedAt: Date = Date()
    ) {
        self.total = total
        self.confirmed = confirmed
        self.transactions = transactions
        self.syncedAt = syncedAt
    }

    public static let empty = WalletSnapshot(
        total: .zero, confirmed: .zero, transactions: [], syncedAt: .distantPast
    )

    public var hasPending: Bool { total != confirmed }
}
