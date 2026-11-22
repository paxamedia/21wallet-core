import Foundation
import LocalAuthentication
import Security

public enum KeyProtectionLevel: String, Sendable, CaseIterable {
    case biometricsWithInvalidation
    case userPresence

    var accessFlags: SecAccessControlCreateFlags {
        switch self {
        case .biometricsWithInvalidation: [.privateKeyUsage, .biometryCurrentSet]
        case .userPresence: [.privateKeyUsage, .userPresence]
        }
    }

    public var explanation: String {
        switch self {
        case .biometricsWithInvalidation: "Protected by Face ID or Touch ID"
        case .userPresence: "Protected by your device passcode"
        }
    }
}

// The enclave only supports P-256, so it wraps the recovery phrase. It never holds a Bitcoin key.
public actor SecureEnclaveSecretStore: SecretStore {
    private static let algorithm: SecKeyAlgorithm = .eciesEncryptionCofactorX963SHA256AESGCM

    private let service: String
    private let keyTag: Data

    public init(service: String, keyTag: String) {
        self.service = service
        self.keyTag = Data(keyTag.utf8)
    }

    public enum Availability: Sendable, Equatable {
        case available(KeyProtectionLevel)
        case noDeviceAuthentication
        case unsupportedHardware

        public var protectionLevel: KeyProtectionLevel? {
            if case .available(let level) = self { return level }
            return nil
        }
    }

    public static func availability() -> Availability {
        if let level = availableProtection() {
            return .available(level)
        }
        var error: NSError?
        let canAuthenticate = LAContext().canEvaluatePolicy(
            .deviceOwnerAuthentication, error: &error
        )
        return canAuthenticate ? .unsupportedHardware : .noDeviceAuthentication
    }

    public static func availableProtection() -> KeyProtectionLevel? {
        KeyProtectionLevel.allCases.first { canCreateKey(protection: $0) }
    }

    public static func isAvailable() -> Bool {
        availableProtection() != nil
    }

    private static func canCreateKey(protection: KeyProtectionLevel) -> Bool {
        var error: Unmanaged<CFError>?
        guard let access = accessControl(for: protection, error: &error) else {
            error?.release()
            return false
        }
        let key = SecKeyCreateRandomKey(
            keyAttributes(access: access, permanent: false) as CFDictionary, &error
        )
        error?.release()
        return key != nil
    }

    private static func accessControl(
        for protection: KeyProtectionLevel,
        error: inout Unmanaged<CFError>?
    ) -> SecAccessControl? {
        SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            protection.accessFlags,
            &error
        )
    }

    private static func keyAttributes(access: SecAccessControl, permanent: Bool, tag: Data? = nil)
        -> [String: Any]
    {
        var privateAttributes: [String: Any] = [
            kSecAttrIsPermanent as String: permanent,
            kSecAttrAccessControl as String: access,
        ]
        if let tag { privateAttributes[kSecAttrApplicationTag as String] = tag }

        return [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: privateAttributes,
        ]
    }

    public func save(_ secret: Data, id: String) throws {
        let privateKey = try existingKey(context: nil) ?? createKey()
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SecretStoreError.cryptography("could not derive the public key")
        }
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, Self.algorithm) else {
            throw SecretStoreError.cryptography("ECIES is unavailable for this key")
        }

        var error: Unmanaged<CFError>?
        guard
            let ciphertext = SecKeyCreateEncryptedData(
                publicKey, Self.algorithm, secret as CFData, &error
            ) as Data?
        else {
            throw Self.cryptoError(from: &error)
        }
        try storeCiphertext(ciphertext, id: id)
    }

    public func load(id: String, prompt: String) throws -> Data {
        let ciphertext = try loadCiphertext(id: id)

        let context = LAContext()
        context.localizedReason = prompt
        guard let privateKey = try existingKey(context: context) else {
            throw SecretStoreError.notFound
        }

        var error: Unmanaged<CFError>?
        guard
            let plaintext = SecKeyCreateDecryptedData(
                privateKey, Self.algorithm, ciphertext as CFData, &error
            ) as Data?
        else {
            throw Self.cryptoError(from: &error)
        }
        return plaintext
    }

    public func delete(id: String) throws {
        let status = SecItemDelete(baseQuery(id: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychain(status)
        }
    }

    // Checks the enclave key too: a biometry change invalidates the key but leaves the ciphertext.
    public func contains(id: String) -> Bool {
        var query = baseQuery(id: id)
        query[kSecReturnData as String] = false
        guard SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess else {
            return false
        }
        return hasEnclaveKey()
    }

    private func hasEnclaveKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) != errSecItemNotFound
    }

    public func destroyKeyMaterial() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychain(status)
        }
    }

    private func existingKey(context: LAContext?) throws -> SecKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let item else { throw SecretStoreError.keychain(status) }
            return (item as! SecKey)
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled:
            throw SecretStoreError.authenticationCancelled
        case errSecAuthFailed:
            throw SecretStoreError.authenticationFailed
        default:
            throw SecretStoreError.keychain(status)
        }
    }

    private func createKey() throws -> SecKey {
        guard let protection = Self.availableProtection() else {
            throw SecretStoreError.secureEnclaveUnavailable
        }

        var error: Unmanaged<CFError>?
        guard let access = Self.accessControl(for: protection, error: &error) else {
            throw Self.cryptoError(from: &error)
        }

        let attributes = Self.keyAttributes(access: access, permanent: true, tag: keyTag)
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            guard error != nil else { throw SecretStoreError.secureEnclaveUnavailable }
            throw Self.cryptoError(from: &error)
        }
        return key
    }

    private func baseQuery(id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
    }

    private func storeCiphertext(_ ciphertext: Data, id: String) throws {
        SecItemDelete(baseQuery(id: id) as CFDictionary)

        var attributes = baseQuery(id: id)
        attributes[kSecValueData as String] = ciphertext
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
    }

    private func loadCiphertext(id: String) throws -> Data {
        var query = baseQuery(id: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw SecretStoreError.keychain(status) }
            return data
        case errSecItemNotFound:
            throw SecretStoreError.notFound
        default:
            throw SecretStoreError.keychain(status)
        }
    }

    private static func cryptoError(from error: inout Unmanaged<CFError>?) -> SecretStoreError {
        guard let cfError = error?.takeRetainedValue() else {
            return .cryptography("unknown failure")
        }
        error = nil
        let code = CFErrorGetCode(cfError)
        switch code {
        case Int(errSecUserCanceled), LAError.userCancel.rawValue:
            return .authenticationCancelled
        case Int(errSecAuthFailed), LAError.authenticationFailed.rawValue:
            return .authenticationFailed
        default:
            return .cryptography(CFErrorCopyDescription(cfError) as String? ?? "code \(code)")
        }
    }
}
