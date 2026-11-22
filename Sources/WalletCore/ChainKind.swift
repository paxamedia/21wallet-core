public enum ChainKind: String, Sendable, CaseIterable, Codable, Identifiable, Comparable {
    case bitcoin
    case liquid

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bitcoin: "Bitcoin"
        case .liquid: "Liquid"
        }
    }

    public var nativeTicker: String {
        switch self {
        case .bitcoin: "BTC"
        case .liquid: "L-BTC"
        }
    }

    public var slip44CoinType: UInt32 {
        switch self {
        case .bitcoin: 0
        case .liquid: 1776
        }
    }

    public var isConfidential: Bool {
        switch self {
        case .bitcoin: false
        case .liquid: true
        }
    }

    public var supportsIssuedAssets: Bool {
        switch self {
        case .bitcoin: false
        case .liquid: true
        }
    }

    public var trustNote: String? {
        switch self {
        case .bitcoin:
            nil
        case .liquid:
            "Liquid is a federated sidechain. Your L-BTC is held by a federation of companies, not by the Bitcoin network. Weaker than holding bitcoin yourself, far stronger than an exchange."
        }
    }

    public static func < (lhs: ChainKind, rhs: ChainKind) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .bitcoin: 0
        case .liquid: 1
        }
    }
}
