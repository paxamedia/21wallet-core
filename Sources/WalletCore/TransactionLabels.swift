import Foundation

public struct TransactionLabels: Sendable, Equatable, Codable {
    private var labels: [String: String]

    public init(labels: [String: String] = [:]) {
        self.labels = labels
    }

    private static func key(_ chain: ChainKind, _ txid: String) -> String {
        "\(chain.rawValue):\(txid)"
    }

    public subscript(chain: ChainKind, txid: String) -> String? {
        get { labels[Self.key(chain, txid)] }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                labels[Self.key(chain, txid)] = trimmed
            } else {
                labels.removeValue(forKey: Self.key(chain, txid))
            }
        }
    }

    public var count: Int { labels.count }
}
