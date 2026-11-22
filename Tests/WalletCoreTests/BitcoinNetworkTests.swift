import Testing

@testable import WalletCore

@Suite("BitcoinNetwork")
struct BitcoinNetworkTests {
    @Test("Bech32 prefixes match BIP173/BIP350")
    func bech32Prefixes() {
        #expect(BitcoinNetwork.mainnet.bech32HRP == "bc")
        #expect(BitcoinNetwork.testnet.bech32HRP == "tb")
        #expect(BitcoinNetwork.testnet4.bech32HRP == "tb")
        #expect(BitcoinNetwork.signet.bech32HRP == "tb")
        #expect(BitcoinNetwork.regtest.bech32HRP == "bcrt")
    }

    @Test("Only mainnet uses BIP44 coin type 0")
    func coinTypes() {
        #expect(BitcoinNetwork.mainnet.bip44CoinType == 0)
        for network in BitcoinNetwork.allCases where network != .mainnet {
            #expect(network.bip44CoinType == 1)
            #expect(network.isTestNetwork)
        }
    }

    @Test("Raw values are stable across versions")
    func stableRawValues() {
        #expect(BitcoinNetwork(rawValue: "mainnet") == .mainnet)
        #expect(BitcoinNetwork(rawValue: "signet") == .signet)
        #expect(
            BitcoinNetwork.allCases.map(\.rawValue)
                == ["mainnet", "testnet", "testnet4", "signet", "regtest"]
        )
    }
}
