import Foundation

public enum AccountNetwork: Sendable, Equatable, Hashable, Codable {
    case bitcoin(BitcoinNetwork)
    case liquid(LiquidNetwork)

    public var chain: ChainKind {
        switch self {
        case .bitcoin: .bitcoin
        case .liquid: .liquid
        }
    }

    public var displayName: String {
        switch self {
        case .bitcoin(let network): network.displayName
        case .liquid(let network): network.displayName
        }
    }

    public var isTestNetwork: Bool {
        switch self {
        case .bitcoin(let network): network.isTestNetwork
        case .liquid(let network): network.isTestNetwork
        }
    }

    public var bip44CoinType: UInt32 {
        switch self {
        case .bitcoin(let network): network.bip44CoinType
        case .liquid(let network): network.bip44CoinType
        }
    }

    public var bitcoinNetwork: BitcoinNetwork? {
        guard case .bitcoin(let network) = self else { return nil }
        return network
    }

    public var liquidNetwork: LiquidNetwork? {
        guard case .liquid(let network) = self else { return nil }
        return network
    }

    public func counterpart(on chain: ChainKind) -> AccountNetwork {
        switch chain {
        case .bitcoin: .bitcoin(isTestNetwork ? .signet : .mainnet)
        case .liquid: .liquid(isTestNetwork ? .testnet : .mainnet)
        }
    }
}
