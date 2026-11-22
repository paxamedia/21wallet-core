import Foundation

public struct ChainSourcePreference: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable, Identifiable {
        case publicServer
        case ownNode

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .publicServer: "mempool.space"
            case .ownNode: "Your own node"
            }
        }
    }

    public var kind: Kind
    public var customURL: String

    public var gapLimit: UInt64

    public static let defaultGapLimit: UInt64 = 20
    public static let maximumGapLimit: UInt64 = 500

    public init(
        kind: Kind = .publicServer,
        customURL: String = "",
        gapLimit: UInt64 = ChainSourcePreference.defaultGapLimit
    ) {
        self.kind = kind
        self.customURL = customURL
        self.gapLimit = Self.clampGapLimit(gapLimit)
    }

    public static func clampGapLimit(_ value: UInt64) -> UInt64 {
        min(max(value, 1), maximumGapLimit)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, customURL, gapLimit
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        customURL = try container.decode(String.self, forKey: .customURL)
        gapLimit = Self.clampGapLimit(
            try container.decodeIfPresent(UInt64.self, forKey: .gapLimit) ?? Self.defaultGapLimit
        )
    }

    public static let `default` = ChainSourcePreference()

    public var resolvedURL: String? {
        guard kind == .ownNode else { return nil }
        return Self.normalize(customURL)
    }

    public var isUsable: Bool {
        kind == .publicServer || resolvedURL != nil
    }

    public static func normalize(_ text: String) -> String? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if !lowered.hasPrefix("http://"), !lowered.hasPrefix("https://") {
            trimmed = (isLocalNetworkHost(host(inAuthority: trimmed)) ? "http://" : "https://")
                + trimmed
        }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }

        guard let url = URL(string: trimmed), let host = url.host(), !host.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func host(inAuthority text: String) -> String {
        var candidate = text
        if let slash = candidate.firstIndex(of: "/") { candidate = String(candidate[..<slash]) }
        if let at = candidate.lastIndex(of: "@") {
            candidate = String(candidate[candidate.index(after: at)...])
        }
        if candidate.hasPrefix("["), let close = candidate.firstIndex(of: "]") {
            return String(candidate[candidate.index(after: candidate.startIndex)..<close])
                .lowercased()
        }
        if candidate.filter({ $0 == ":" }).count > 1 { return candidate.lowercased() }
        if let colon = candidate.lastIndex(of: ":") { candidate = String(candidate[..<colon]) }
        return candidate.lowercased()
    }

    static func isLocalNetworkHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if host.hasSuffix(".local") || host.hasSuffix(".onion") { return true }
        if host == "::1" || host == "0:0:0:0:0:0:0:1" { return true }

        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        guard parts.count == 4, octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (127, _): return true  // loopback
        case (10, _), (192, 168), (172, 16...31): return true  // RFC1918
        case (169, 254): return true
        default: return false
        }
    }
}
