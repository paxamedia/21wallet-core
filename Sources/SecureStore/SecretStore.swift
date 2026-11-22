import Foundation

public protocol SecretStore: Sendable {
    func save(_ secret: Data, id: String) async throws

    func load(id: String, prompt: String) async throws -> Data

    func delete(id: String) async throws

    func contains(id: String) async -> Bool

    // The wrapping key is shared by every id. Only for wiping every wallet on the device.
    func destroyKeyMaterial() async throws
}

public enum SecretStoreError: Error, Equatable {
    case secureEnclaveUnavailable
    case noDeviceAuthentication
    case notFound
    case authenticationFailed
    case authenticationCancelled
    case keychain(OSStatus)
    case cryptography(String)
}

extension SecretStoreError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .secureEnclaveUnavailable:
            "This device does not support hardware-backed key storage."
        case .noDeviceAuthentication:
            "Set a passcode on this device to create a wallet. Keys are never stored on a device that has no lock."
        case .notFound:
            "No stored secret was found."
        case .authenticationFailed:
            "Authentication failed."
        case .authenticationCancelled:
            "Authentication was cancelled."
        case .keychain(let status):
            "Keychain error \(status)."
        case .cryptography(let detail):
            "Cryptographic operation failed: \(detail)"
        }
    }
}
