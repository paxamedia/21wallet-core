import BitcoinDevKit
import Foundation
import WalletCore

public enum MnemonicLength: Int, Sendable, CaseIterable, Codable, Identifiable {
    case twelve = 12
    case fifteen = 15
    case eighteen = 18
    case twentyOne = 21
    case twentyFour = 24

    public var id: Int { rawValue }

    public static let offeredAtCreation: [MnemonicLength] = [.twelve, .twentyFour]

    public var entropyBits: Int { rawValue * 11 - rawValue * 11 / 33 }

    var bdkWordCount: WordCount {
        switch self {
        case .twelve: .words12
        case .fifteen: .words15
        case .eighteen: .words18
        case .twentyOne: .words21
        case .twentyFour: .words24
        }
    }
}

public struct WalletStorageError: Error, CustomStringConvertible {
    public let underlying: String

    public init(underlying: String) {
        self.underlying = underlying
    }

    public var description: String {
        "This device could not save the wallet's data. \(underlying)"
    }
}

public struct WalletBlueprint: Sendable {
    public let secret: WalletSecret
    public let metadata: WalletMetadata
}

public struct DerivedAddresses: Sendable, Equatable {
    public let receive: String
    public let change: String
    public let accountPath: String

    public init(receive: String, change: String, accountPath: String) {
        self.receive = receive
        self.change = change
        self.accountPath = accountPath
    }
}

public actor WalletEngine {
    private var openWallets: [String: Wallet] = [:]
    private var persisters: [String: Persister] = [:]
    private let storageDirectory: URL

    var pendingDrafts: [UUID: Psbt] = [:]

    func wallet(for metadata: WalletMetadata) throws -> (wallet: Wallet, isNew: Bool) {
        try openWallet(for: metadata)
    }

    public init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
    }

    private func openWallet(for metadata: WalletMetadata) throws -> (wallet: Wallet, isNew: Bool) {
        if let existing = openWallets[metadata.id] { return (existing, false) }

        try FileManager.default.createDirectory(
            at: storageDirectory, withIntermediateDirectories: true
        )
        let isNew = !FileManager.default.fileExists(atPath: databasePath(metadata))

        let kind = metadata.network.bdkNetworkKind
        let external = try Descriptor(descriptor: metadata.externalDescriptor, networkKind: kind)
        let change = try Descriptor(descriptor: metadata.internalDescriptor, networkKind: kind)
        let database = try persister(for: metadata)

        let wallet: Wallet
        if isNew {
            wallet = try Wallet(
                descriptor: external,
                changeDescriptor: change,
                network: metadata.network.bdkNetwork,
                persister: database
            )
        } else {
            wallet = try Wallet.load(
                descriptor: external, changeDescriptor: change, persister: database
            )
        }
        openWallets[metadata.id] = wallet
        return (wallet, isNew)
    }

    private func needsFullScan(_ metadata: WalletMetadata) -> Bool {
        !FileManager.default.fileExists(atPath: scannedMarkerPath(metadata))
    }

    private func markFullScanDone(_ metadata: WalletMetadata) {
        FileManager.default.createFile(atPath: scannedMarkerPath(metadata), contents: nil)
    }

    private func scannedMarkerPath(_ metadata: WalletMetadata) -> String {
        storageDirectory.appending(path: "wallet-\(metadata.id).scanned")
            .path(percentEncoded: false)
    }

    private func databasePath(_ metadata: WalletMetadata) -> String {
        storageDirectory.appending(path: "wallet-\(metadata.id).sqlite")
            .path(percentEncoded: false)
    }

    // Persist first, then mark the full scan done. The reverse can leave a wallet that looks empty.
    func commit(_ wallet: Wallet, for metadata: WalletMetadata, fullScan: Bool = false) throws {
        do {
            _ = try wallet.persist(persister: try persister(for: metadata))
        } catch {
            throw WalletStorageError(underlying: String(describing: error))
        }
        if fullScan { markFullScanDone(metadata) }
    }

    func commit(for metadata: WalletMetadata, fullScan: Bool) throws {
        let (wallet, _) = try wallet(for: metadata)
        try commit(wallet, for: metadata, fullScan: fullScan)
    }

    func hasCompletedFullScan(_ metadata: WalletMetadata) -> Bool {
        !needsFullScan(metadata)
    }

    public func sync(
        _ metadata: WalletMetadata,
        using source: any ChainSource,
        forceFullScan: Bool = false,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) throws -> WalletSnapshot {
        let (wallet, _) = try wallet(for: metadata)
        let fullScan = needsFullScan(metadata) || forceFullScan
        let update = try source.scan(wallet, fullScan: fullScan, onProgress: onProgress)
        try wallet.applyUpdate(update: update)

        try commit(wallet, for: metadata, fullScan: fullScan)

        return snapshot(of: wallet)
    }

    public func cachedSnapshot(_ metadata: WalletMetadata) throws -> WalletSnapshot {
        let (wallet, isNew) = try wallet(for: metadata)
        return isNew ? .empty : snapshot(of: wallet)
    }

    private func snapshot(of wallet: Wallet) -> WalletSnapshot {
        let balance = wallet.balance()
        let transactions = wallet.transactions().map { canonical -> WalletTransaction in
            let values = wallet.sentAndReceived(tx: canonical.transaction)
            let net =
                Int64(values.received.toSat()) - Int64(values.sent.toSat())

            var confirmed = false
            var timestamp: Date?
            switch canonical.chainPosition {
            case .confirmed(let blockTime, _):
                confirmed = true
                timestamp = Date(timeIntervalSince1970: TimeInterval(blockTime.confirmationTime))
            case .unconfirmed(let seen):
                timestamp = seen.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            }

            return WalletTransaction(
                id: canonical.transaction.computeTxid().description,
                netAmount: Amount(sats: net),
                isConfirmed: confirmed,
                timestamp: timestamp
            )
        }
        .sorted { ($0.timestamp ?? .distantFuture) > ($1.timestamp ?? .distantFuture) }

        return WalletSnapshot(
            total: Amount(sats: Int64(balance.total.toSat())),
            confirmed: Amount(sats: Int64(balance.confirmed.toSat())),
            transactions: transactions
        )
    }

    public func discardStorage(for metadata: WalletMetadata) {
        openWallets[metadata.id] = nil
        persisters[metadata.id] = nil
        try? FileManager.default.removeItem(atPath: databasePath(metadata))
        try? FileManager.default.removeItem(atPath: scannedMarkerPath(metadata))
    }

    public func generateMnemonic(length: MnemonicLength = .twelve) -> String {
        Mnemonic(wordCount: length.bdkWordCount).description
    }

    public func createWallet(
        network: BitcoinNetwork,
        scriptType: ScriptType,
        length: MnemonicLength = .twelve
    ) throws -> WalletBlueprint {
        try blueprint(
            secret: .mnemonic(words: generateMnemonic(length: length), passphrase: nil),
            network: network,
            scriptType: scriptType
        )
    }

    public func restoreWallet(
        mnemonic: String,
        passphrase: String? = nil,
        network: BitcoinNetwork,
        scriptType: ScriptType
    ) throws -> WalletBlueprint {
        try blueprint(
            secret: .mnemonic(words: mnemonic, passphrase: passphrase),
            network: network,
            scriptType: scriptType
        )
    }

    public func restoreWallet(
        extendedKey: String,
        network: BitcoinNetwork,
        scriptType: ScriptType
    ) throws -> WalletBlueprint {
        let parsed = try ExtendedPrivateKey(extendedKey)
        guard parsed.isSupportedScriptType else { throw WalletImportError.unsupportedScriptType }
        return try blueprint(
            secret: .extendedKey(parsed.normalized),
            network: network,
            scriptType: parsed.resolvedScriptType(defaultingTo: scriptType)
        )
    }

    private func blueprint(
        secret: WalletSecret,
        network: BitcoinNetwork,
        scriptType: ScriptType
    ) throws -> WalletBlueprint {
        let normalized: WalletSecret =
            switch secret {
            case .mnemonic(let words, let passphrase):
                .mnemonic(words: MnemonicNormalizer.normalize(words), passphrase: passphrase)
            case .extendedKey(let key):
                .extendedKey(key)
            }

        let descriptors = try DescriptorFactory.descriptors(
            secret: normalized, network: network, scriptType: scriptType
        )
        return WalletBlueprint(
            secret: normalized,
            metadata: WalletMetadata(
                network: network,
                scriptType: scriptType,
                externalDescriptor: descriptors.external.description,
                internalDescriptor: descriptors.change.description
            )
        )
    }

    public func nextReceiveAddress(for metadata: WalletMetadata) throws -> String {
        let (wallet, _) = try wallet(for: metadata)
        if let unused = wallet.listUnusedAddresses(keychain: .external).first {
            return unused.address.description
        }
        return try revealNewReceiveAddress(for: metadata)
    }

    public func revealNewReceiveAddress(for metadata: WalletMetadata) throws -> String {
        let (wallet, _) = try wallet(for: metadata)
        let revealed = wallet.revealNextAddress(keychain: .external)
        try commit(wallet, for: metadata)
        return revealed.address.description
    }

    private func persister(for metadata: WalletMetadata) throws -> Persister {
        if let existing = persisters[metadata.id] { return existing }
        let opened = try Persister.newSqlite(path: databasePath(metadata))
        persisters[metadata.id] = opened
        return opened
    }

    public func receiveAddress(for metadata: WalletMetadata, index: UInt32 = 0) throws -> String {
        let kind = metadata.network.bdkNetworkKind
        let wallet = try Wallet(
            descriptor: try Descriptor(descriptor: metadata.externalDescriptor, networkKind: kind),
            changeDescriptor: try Descriptor(
                descriptor: metadata.internalDescriptor, networkKind: kind
            ),
            network: metadata.network.bdkNetwork,
            persister: try Persister.newInMemory()
        )
        return wallet.peekAddress(keychain: .external, index: index).address.description
    }

    public func detectScriptType(
        mnemonic: String,
        passphrase: String?,
        network: BitcoinNetwork,
        using source: any ChainSource
    ) throws -> ScriptType {
        var candidates: [ScriptTypeCandidate] = []

        for candidate in ScriptType.allCases {
            let blueprint = try restoreWallet(
                mnemonic: mnemonic,
                passphrase: passphrase,
                network: network,
                scriptType: candidate
            )
            defer { discardStorage(for: blueprint.metadata) }

            guard let snapshot = try? sync(blueprint.metadata, using: source, onProgress: nil)
            else { continue }
            candidates.append(ScriptTypeCandidate(scriptType: candidate, snapshot: snapshot))
        }
        return ScriptTypeCandidate.best(of: candidates) ?? .taproot
    }

    public func decoyWords(excluding used: Set<String>, count: Int) -> [String] {
        var decoys: Set<String> = []
        var attempts = 0
        while decoys.count < count, attempts < 20 {
            attempts += 1
            for word in generateMnemonic(length: .twentyFour).split(separator: " ").map(String.init)
            where !used.contains(word) && decoys.count < count {
                decoys.insert(word)
            }
        }
        return Array(decoys)
    }

    public func previewAddresses(
        mnemonic: String,
        passphrase: String? = nil,
        network: BitcoinNetwork,
        scriptType: ScriptType
    ) throws -> DerivedAddresses {
        let descriptors = try DescriptorFactory.descriptors(
            mnemonic: mnemonic,
            passphrase: passphrase,
            network: network,
            scriptType: scriptType
        )
        let wallet = try Wallet(
            descriptor: descriptors.external,
            changeDescriptor: descriptors.change,
            network: network.bdkNetwork,
            persister: try Persister.newInMemory()
        )
        return DerivedAddresses(
            receive: wallet.revealNextAddress(keychain: .external).address.description,
            change: wallet.revealNextAddress(keychain: .internal).address.description,
            accountPath: "m/\(scriptType.purpose)'/\(network.bip44CoinType)'/0'"
        )
    }
}
