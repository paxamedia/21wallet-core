import BitcoinDevKit
import Foundation
import WalletCore

public struct ScanProgress: Sendable, Equatable {
    public let scriptsChecked: UInt64
    public let isFullScan: Bool

    public init(scriptsChecked: UInt64, isFullScan: Bool) {
        self.scriptsChecked = scriptsChecked
        self.isFullScan = isFullScan
    }
}

public protocol ChainSource: Sendable {
    var displayName: String { get }
    var privacyNote: String { get }

    func scan(
        _ wallet: Wallet,
        fullScan: Bool,
        onProgress: (@Sendable (ScanProgress) -> Void)?
    ) throws -> Update
    func broadcast(_ transaction: Transaction) throws
    func feeEstimates() throws -> [UInt16: Double]
}

public struct EsploraChainSource: ChainSource {
    public let url: String
    public let displayName: String

    // Empty for a user's own node: falling back to a public server would leak the wallet to it.
    public let fallbackURLs: [String]

    private let stopGap: UInt64
    private let parallelRequests: UInt64

    public init(
        url: String,
        displayName: String,
        fallbackURLs: [String] = [],
        stopGap: UInt64 = 20,
        parallelRequests: UInt64 = 4
    ) {
        self.url = url
        self.displayName = displayName
        self.fallbackURLs = fallbackURLs
        self.stopGap = stopGap
        self.parallelRequests = parallelRequests
    }

    private var urlsInOrder: [String] { [url] + fallbackURLs }

    private func withFailover<T>(_ operation: (String) throws -> T) throws -> T {
        var lastError: Error?
        for endpoint in urlsInOrder {
            do {
                return try operation(endpoint)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? PriceUnavailable()
    }

    private struct PriceUnavailable: Error {}

    public static func mempoolSpace(
        for network: BitcoinNetwork,
        stopGap: UInt64 = ChainSourcePreference.defaultGapLimit
    ) -> EsploraChainSource {
        let path =
            switch network {
            case .mainnet: ""
            case .testnet: "/testnet"
            case .testnet4: "/testnet4"
            case .signet: "/signet"
            case .regtest: "/signet"
            }
        let blockstreamPath =
            switch network {
            case .mainnet: ""
            case .testnet: "/testnet"
            case .testnet4, .signet, .regtest: nil as String?
            }
        return EsploraChainSource(
            url: "https://mempool.space\(path)/api",
            displayName: "mempool.space",
            fallbackURLs: blockstreamPath.map { ["https://blockstream.info\($0)/api"] } ?? [],
            stopGap: stopGap
        )
    }

    public var privacyNote: String {
        "\(displayName) can see every address in this wallet and the device's IP address."
    }

    public func scan(
        _ wallet: Wallet,
        fullScan: Bool,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) throws -> Update {
        try withFailover { endpoint in
            try scanOnce(wallet, fullScan: fullScan, endpoint: endpoint, onProgress: onProgress)
        }
    }

    private func scanOnce(
        _ wallet: Wallet,
        fullScan: Bool,
        endpoint: String,
        onProgress: (@Sendable (ScanProgress) -> Void)?
    ) throws -> Update {
        let client = EsploraClient(url: endpoint)
        if fullScan {
            var builder = wallet.startFullScan()
            if let onProgress {
                builder = try builder.inspectSpksForAllKeychains(
                    inspector: ScanCounter(isFullScan: true, report: onProgress)
                )
            }
            return try client.fullScan(
                request: try builder.build(),
                stopGap: stopGap,
                parallelRequests: parallelRequests
            )
        }

        var builder = wallet.startSyncWithRevealedSpks()
        if let onProgress {
            builder = try builder.inspectSpks(
                inspector: ScanCounter(isFullScan: false, report: onProgress)
            )
        }
        return try client.sync(
            request: try builder.build(),
            parallelRequests: parallelRequests
        )
    }

    public func broadcast(_ transaction: Transaction) throws {
        try withFailover { endpoint in
            // Rebroadcasting a signed transaction is a no-op, so failover cannot double-spend.
            try EsploraClient(url: endpoint).broadcast(transaction: transaction)
        }
    }

    public func feeEstimates() throws -> [UInt16: Double] {
        try withFailover { endpoint in
            try EsploraClient(url: endpoint).getFeeEstimates()
        }
    }
}

private final class ScanCounter: FullScanScriptInspector, SyncScriptInspector, @unchecked Sendable
{
    private let isFullScan: Bool
    private let report: @Sendable (ScanProgress) -> Void
    private let lock = NSLock()
    private var checked: UInt64 = 0

    init(isFullScan: Bool, report: @escaping @Sendable (ScanProgress) -> Void) {
        self.isFullScan = isFullScan
        self.report = report
    }

    private func advance() {
        lock.lock()
        checked += 1
        let current = checked
        lock.unlock()
        report(ScanProgress(scriptsChecked: current, isFullScan: isFullScan))
    }

    func inspect(keychain: KeychainKind, index: UInt32, script: Script) { advance() }
    func inspect(script: Script, total: UInt64) { advance() }
}
