public enum LiquidNetwork: String, Sendable, CaseIterable, Codable {
    case mainnet
    case testnet

    public var displayName: String {
        switch self {
        case .mainnet: "Liquid"
        case .testnet: "Liquid Testnet"
        }
    }

    public var confidentialHRP: String {
        switch self {
        case .mainnet: "lq"
        case .testnet: "tlq"
        }
    }

    public var unconfidentialHRP: String {
        switch self {
        case .mainnet: "ex"
        case .testnet: "tex"
        }
    }

    public var bip44CoinType: UInt32 {
        self == .mainnet ? ChainKind.liquid.slip44CoinType : 1
    }

    public var isTestNetwork: Bool { self != .mainnet }
}
