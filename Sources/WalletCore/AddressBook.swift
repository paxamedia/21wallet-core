import Foundation

public struct KnownRecipient: Sendable, Equatable, Codable, Identifiable {
    public let address: String

    public var chain: ChainKind
    public var label: String?
    public var lastUsed: Date

    public var id: String { "\(chain.rawValue):\(address)" }

    public init(
        address: String,
        chain: ChainKind = .bitcoin,
        label: String? = nil,
        lastUsed: Date = Date()
    ) {
        self.address = address
        self.chain = chain
        self.label = label
        self.lastUsed = lastUsed
    }

    private enum CodingKeys: String, CodingKey {
        case address, chain, label, lastUsed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(String.self, forKey: .address)
        chain = try container.decodeIfPresent(ChainKind.self, forKey: .chain) ?? .bitcoin
        label = try container.decodeIfPresent(String.self, forKey: .label)
        lastUsed = try container.decode(Date.self, forKey: .lastUsed)
    }
}

public enum RecipientWarning: Sendable, Equatable {
    case resemblesKnownAddress(KnownRecipient)

    public var message: String {
        switch self {
        case .resemblesKnownAddress(let known):
            let label = known.label.map { " (\($0))" } ?? ""
            return
                "This address looks like one you paid before\(label), but it is not the same address. Check every character."
        }
    }
}

public struct AddressBook: Sendable, Equatable, Codable {
    public private(set) var recipients: [KnownRecipient]

    public init(recipients: [KnownRecipient] = []) {
        self.recipients = recipients
    }

    public mutating func remember(
        _ address: String,
        chain: ChainKind = .bitcoin,
        label: String? = nil
    ) {
        if let index = recipients.firstIndex(where: {
            $0.address == address && $0.chain == chain
        }) {
            recipients[index].lastUsed = Date()
            if let label { recipients[index].label = label }
        } else {
            recipients.append(KnownRecipient(address: address, chain: chain, label: label))
        }
    }

    public func recipient(for address: String, chain: ChainKind = .bitcoin) -> KnownRecipient? {
        recipients.first { $0.address == address && $0.chain == chain }
    }

    public func warning(for address: String, chain: ChainKind = .bitcoin) -> RecipientWarning? {
        guard recipient(for: address, chain: chain) == nil else { return nil }
        guard
            let lookalike = recipients.first(where: {
                $0.chain == chain
                    && AddressSimilarity.isSuspiciouslySimilar(address, $0.address)
            })
        else { return nil }
        return .resemblesKnownAddress(lookalike)
    }
}

public enum AddressSimilarity {
    static let affixLength = 6

    public static func isSuspiciouslySimilar(_ candidate: String, _ known: String) -> Bool {
        let a = candidate.lowercased()
        let b = known.lowercased()
        guard a != b else { return false }
        guard a.count >= affixLength * 2, b.count >= affixLength * 2 else { return false }

        if a.prefix(affixLength) == b.prefix(affixLength),
            a.suffix(affixLength) == b.suffix(affixLength)
        {
            return true
        }

        guard a.count == b.count else { return false }
        let distance = levenshtein(a, b)
        return distance > 0 && distance <= 4
    }

    public static func levenshtein(_ a: String, _ b: String) -> Int {
        let source = Array(a)
        let target = Array(b)
        if source.isEmpty { return target.count }
        if target.isEmpty { return source.count }

        var previous = Array(0...target.count)
        var current = [Int](repeating: 0, count: target.count + 1)

        for i in 1...source.count {
            current[0] = i
            for j in 1...target.count {
                let substitution = previous[j - 1] + (source[i - 1] == target[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[target.count]
    }
}
