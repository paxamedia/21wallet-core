public enum ScriptType: String, Sendable, CaseIterable, Codable {
    case nativeSegwit
    case taproot

    public var purpose: UInt32 {
        switch self {
        case .nativeSegwit: 84
        case .taproot: 86
        }
    }

    public var displayName: String {
        switch self {
        case .nativeSegwit: "Native SegWit"
        case .taproot: "Taproot"
        }
    }
}
