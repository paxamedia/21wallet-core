import Foundation

public struct Account: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let network: AccountNetwork
    public let scriptType: ScriptType
    public let externalDescriptor: String
    public let internalDescriptor: String
    public let createdAt: Date

    public var label: String?

    public var isHidden: Bool

    public var chain: ChainKind { network.chain }

    public var displayName: String { label ?? chain.displayName }

    public init(
        id: String = UUID().uuidString,
        network: AccountNetwork,
        scriptType: ScriptType,
        externalDescriptor: String,
        internalDescriptor: String,
        createdAt: Date = Date(),
        label: String? = nil,
        isHidden: Bool = false
    ) {
        self.id = id
        self.network = network
        self.scriptType = scriptType
        self.externalDescriptor = externalDescriptor
        self.internalDescriptor = internalDescriptor
        self.createdAt = createdAt
        self.label = label
        self.isHidden = isHidden
    }
}

extension Account {
    public var bitcoinMetadata: WalletMetadata? {
        guard let bitcoinNetwork = network.bitcoinNetwork else { return nil }
        return WalletMetadata(
            id: id,
            network: bitcoinNetwork,
            scriptType: scriptType,
            externalDescriptor: externalDescriptor,
            internalDescriptor: internalDescriptor,
            createdAt: createdAt
        )
    }

    public init(bitcoin metadata: WalletMetadata, label: String? = nil) {
        self.init(
            id: metadata.id,
            network: .bitcoin(metadata.network),
            scriptType: metadata.scriptType,
            externalDescriptor: metadata.externalDescriptor,
            internalDescriptor: metadata.internalDescriptor,
            createdAt: metadata.createdAt,
            label: label
        )
    }
}
