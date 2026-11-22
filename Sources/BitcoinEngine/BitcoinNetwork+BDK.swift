import BitcoinDevKit
import WalletCore

extension BitcoinNetwork {
    public var bdkNetwork: Network {
        switch self {
        case .mainnet: .bitcoin
        case .testnet: .testnet
        case .testnet4: .testnet4
        case .signet: .signet
        case .regtest: .regtest
        }
    }

    public var bdkNetworkKind: NetworkKind {
        self == .mainnet ? .main : .test
    }
}
