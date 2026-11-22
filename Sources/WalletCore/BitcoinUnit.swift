public enum BitcoinUnit: String, Sendable, CaseIterable, Codable {
    case sat
    case btc

    public var symbol: String {
        switch self {
        case .sat: "sats"
        case .btc: "BTC"
        }
    }
}
