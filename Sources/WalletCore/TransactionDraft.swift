import Foundation

public struct DraftOutput: Sendable, Equatable, Identifiable {
    public let id: Int
    public let address: String?
    public let amount: Amount
    public let isChange: Bool

    public init(id: Int, address: String?, amount: Amount, isChange: Bool) {
        self.id = id
        self.address = address
        self.amount = amount
        self.isChange = isChange
    }
}

public struct TransactionDraft: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let recipient: String
    public let amount: Amount
    public let fee: Amount
    public let feeRate: UInt64
    public let inputCount: Int
    public let outputs: [DraftOutput]
    public let network: BitcoinNetwork

    public init(
        id: UUID = UUID(),
        recipient: String,
        amount: Amount,
        fee: Amount,
        feeRate: UInt64,
        inputCount: Int,
        outputs: [DraftOutput],
        network: BitcoinNetwork
    ) {
        self.id = id
        self.recipient = recipient
        self.amount = amount
        self.fee = fee
        self.feeRate = feeRate
        self.inputCount = inputCount
        self.outputs = outputs
        self.network = network
    }

    public var totalSpent: Amount { amount + fee }

    public var changeAmount: Amount {
        outputs.filter(\.isChange).reduce(Amount.zero) { $0 + $1.amount }
    }

    public var feeShareOfAmount: Decimal? {
        guard amount.sats > 0 else { return nil }
        return Decimal(fee.sats) / Decimal(amount.sats) * 100
    }

    public var isFeeUnusuallyHigh: Bool {
        guard fee.sats > 0 else { return false }
        guard let share = feeShareOfAmount else { return true }
        return share >= 10
    }
}

public enum FeePriority: String, Sendable, CaseIterable, Identifiable, Codable {
    case fast
    case normal
    case slow
    case custom

    public var id: String { rawValue }

    public static var presets: [FeePriority] { [.fast, .normal, .slow] }

    public var label: String {
        switch self {
        case .fast: "Fast"
        case .normal: "Normal"
        case .slow: "Slow"
        case .custom: "Custom"
        }
    }

    public var expectation: String {
        switch self {
        case .fast: "Next block or two"
        case .normal: "Within an hour"
        case .slow: "Within a day"
        case .custom: "You choose the rate"
        }
    }

    public var blockTarget: UInt16 {
        switch self {
        case .fast: 2
        case .normal: 6
        case .slow, .custom: 144
        }
    }
}

public struct FeeOptions: Sendable, Equatable {
    public let rates: [FeePriority: UInt64]

    public init(rates: [FeePriority: UInt64]) {
        self.rates = rates
    }

    public func rate(for priority: FeePriority) -> UInt64 {
        rates[priority] ?? 1
    }

    public static func sanitise(_ rate: UInt64) -> UInt64 { max(1, rate) }

    public static let fallback = FeeOptions(rates: [.fast: 20, .normal: 8, .slow: 2])
}
