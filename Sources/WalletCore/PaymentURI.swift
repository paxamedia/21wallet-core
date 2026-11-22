import Foundation

public struct PaymentURI: Sendable, Equatable {
    public let address: String

    public let chain: ChainKind?

    public let assetID: AssetID?

    public let amount: Amount?

    public let requestedAmount: String?

    public let label: String?
    public let message: String?
    public let otherParameters: [String: String]

    public init(
        address: String,
        chain: ChainKind? = nil,
        assetID: AssetID? = nil,
        amount: Amount? = nil,
        requestedAmount: String? = nil,
        label: String? = nil,
        message: String? = nil,
        otherParameters: [String: String] = [:]
    ) {
        self.address = address
        self.chain = chain
        self.assetID = assetID
        self.amount = amount
        self.requestedAmount = requestedAmount
        self.label = label
        self.message = message
        self.otherParameters = otherParameters
    }

    private static let schemes: [(prefix: String, chain: ChainKind)] = [
        ("bitcoin:", .bitcoin),
        ("liquidnetwork:", .liquid),
    ]

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var body = trimmed
        var chain: ChainKind?

        if let match = Self.schemes.first(where: {
            body.range(of: $0.prefix, options: [.caseInsensitive, .anchored]) != nil
        }) {
            body = String(body.dropFirst(match.prefix.count))
            chain = match.chain
        } else if body.contains(":") {
            return nil
        }

        let parts = body.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let address = String(parts[0])
        guard !address.isEmpty else { return nil }

        var requestedAmount: String?
        var assetID: AssetID?
        var label: String?
        var message: String?
        var others: [String: String] = [:]

        var namesAnAsset = false

        if parts.count == 2 {
            for pair in parts[1].split(separator: "&", omittingEmptySubsequences: true) {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(kv[0]).lowercased()
                let rawValue = kv.count == 2 ? String(kv[1]) : ""
                let value = rawValue.removingPercentEncoding ?? rawValue
                switch key {
                case "amount":
                    requestedAmount = value
                case "assetid":
                    namesAnAsset = true
                    assetID = AssetID(hex: value)
                    if assetID == nil { others["assetid"] = value }
                case "label":
                    label = value
                case "message":
                    message = value
                default:
                    others[key] = value
                }
            }
        }

        let amount: Amount? =
            namesAnAsset ? nil : requestedAmount.flatMap(Amount.init(btcString:))

        self.init(
            address: address,
            chain: chain,
            assetID: assetID,
            amount: amount,
            requestedAmount: requestedAmount,
            label: label,
            message: message,
            otherParameters: others
        )
    }
}
