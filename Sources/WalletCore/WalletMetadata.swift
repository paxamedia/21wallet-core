import Foundation

public struct WalletMetadata: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let network: BitcoinNetwork
    public let scriptType: ScriptType
    public let externalDescriptor: String
    public let internalDescriptor: String
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        network: BitcoinNetwork,
        scriptType: ScriptType,
        externalDescriptor: String,
        internalDescriptor: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.network = network
        self.scriptType = scriptType
        self.externalDescriptor = externalDescriptor
        self.internalDescriptor = internalDescriptor
        self.createdAt = createdAt
    }
}
