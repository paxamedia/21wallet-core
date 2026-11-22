public enum BitcoinNetwork: String, Sendable, CaseIterable, Codable {
    case mainnet
    case testnet
    case testnet4
    case signet
    case regtest

    public var displayName: String {
        switch self {
        case .mainnet: "Bitcoin"
        case .testnet: "Testnet"
        case .testnet4: "Testnet4"
        case .signet: "Signet"
        case .regtest: "Regtest"
        }
    }

    public var bech32HRP: String {
        switch self {
        case .mainnet: "bc"
        case .testnet, .testnet4, .signet: "tb"
        case .regtest: "bcrt"
        }
    }

    public var bip44CoinType: UInt32 {
        self == .mainnet ? 0 : 1
    }

    public var isTestNetwork: Bool { self != .mainnet }
}
