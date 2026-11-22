import Foundation

public struct Vault: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let createdAt: Date

    public var isBackupVerified: Bool

    public private(set) var accounts: [Account]

    public let displaySalt: String

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        isBackupVerified: Bool = false,
        accounts: [Account] = [],
        displaySalt: String = Self.newDisplaySalt()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.isBackupVerified = isBackupVerified
        self.accounts = accounts.sorted { $0.chain < $1.chain }
        self.displaySalt = displaySalt
    }

    public static func newDisplaySalt() -> String {
        UUID().uuidString + UUID().uuidString
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, isBackupVerified, accounts, displaySalt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isBackupVerified = try container.decode(Bool.self, forKey: .isBackupVerified)
        accounts = try container.decode([Account].self, forKey: .accounts)
            .sorted { $0.chain < $1.chain }
        displaySalt =
            try container.decodeIfPresent(String.self, forKey: .displaySalt)
            ?? Self.newDisplaySalt()
    }

    public var visibleAccounts: [Account] {
        accounts.filter { !$0.isHidden }
    }

    public func account(for chain: ChainKind) -> Account? {
        accounts.first { $0.chain == chain }
    }

    public func account(id: String) -> Account? {
        accounts.first { $0.id == id }
    }

    public var visibleChains: [ChainKind] {
        visibleAccounts.map(\.chain)
    }

    public var isSingleChain: Bool { visibleAccounts.count <= 1 }

    public var canReceive: Bool { isBackupVerified && !visibleAccounts.isEmpty }

    public var isTestNetwork: Bool {
        !accounts.isEmpty && accounts.allSatisfy(\.network.isTestNetwork)
    }

    public mutating func upsert(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.chain == account.chain }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        accounts.sort { $0.chain < $1.chain }
    }

    @discardableResult
    public mutating func setHidden(_ hidden: Bool, forChain chain: ChainKind) -> Bool {
        guard let index = accounts.firstIndex(where: { $0.chain == chain }) else { return false }
        if hidden, visibleAccounts.count <= 1, !accounts[index].isHidden { return false }
        accounts[index].isHidden = hidden
        return true
    }

    public mutating func setLabel(_ label: String?, forChain chain: ChainKind) {
        guard let index = accounts.firstIndex(where: { $0.chain == chain }) else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[index].label = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}
