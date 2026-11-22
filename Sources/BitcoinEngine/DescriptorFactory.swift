import BitcoinDevKit
import WalletCore

public struct WalletDescriptors {
    public let external: Descriptor
    public let change: Descriptor

    public init(external: Descriptor, change: Descriptor) {
        self.external = external
        self.change = change
    }
}

public enum DescriptorFactory {
    public static func descriptors(
        secret: WalletSecret,
        network: BitcoinNetwork,
        scriptType: ScriptType
    ) throws -> WalletDescriptors {
        switch secret {
        case .mnemonic(let words, let passphrase):
            return try descriptors(
                mnemonic: words, passphrase: passphrase, network: network, scriptType: scriptType
            )
        case .extendedKey(let key):
            return try descriptors(extendedKey: key, network: network, scriptType: scriptType)
        }
    }

    public static func descriptors(
        extendedKey raw: String,
        network: BitcoinNetwork,
        scriptType: ScriptType
    ) throws -> WalletDescriptors {
        let parsed = try ExtendedPrivateKey(raw)

        let wantsTestnet = network.isTestNetwork
        guard (parsed.network == .testnet) == wantsTestnet else {
            throw WalletImportError.networkMismatch(
                keyIsTestnet: parsed.network == .testnet, walletIsTestnet: wantsTestnet
            )
        }

        let resolved = parsed.resolvedScriptType(defaultingTo: scriptType)
        let kind = network.bdkNetworkKind
        let secretKey = try DescriptorSecretKey.fromString(privateKey: parsed.normalized)

        guard parsed.isAccountLevel else {
            switch resolved {
            case .nativeSegwit:
                return WalletDescriptors(
                    external: Descriptor.newBip84(secretKey: secretKey, keychainKind: .external, networkKind: kind),
                    change: Descriptor.newBip84(secretKey: secretKey, keychainKind: .internal, networkKind: kind)
                )
            case .taproot:
                return WalletDescriptors(
                    external: Descriptor.newBip86(secretKey: secretKey, keychainKind: .external, networkKind: kind),
                    change: Descriptor.newBip86(secretKey: secretKey, keychainKind: .internal, networkKind: kind)
                )
            }
        }

        // Account-level key: the hardened path is already applied, so only /0/* and /1/* remain.
        let fragment = resolved == .taproot ? "tr" : "wpkh"
        return WalletDescriptors(
            external: try Descriptor(
                descriptor: "\(fragment)(\(parsed.normalized)/0/*)", networkKind: kind
            ),
            change: try Descriptor(
                descriptor: "\(fragment)(\(parsed.normalized)/1/*)", networkKind: kind
            )
        )
    }

    public static func descriptors(
        mnemonic phrase: String,
        passphrase: String? = nil,
        network: BitcoinNetwork,
        scriptType: ScriptType
    ) throws -> WalletDescriptors {
        let mnemonic = try Mnemonic.fromString(mnemonic: MnemonicNormalizer.normalize(phrase))
        let password = (passphrase?.isEmpty ?? true) ? nil : passphrase
        let secretKey = DescriptorSecretKey(
            networkKind: network.bdkNetworkKind,
            mnemonic: mnemonic,
            password: password
        )
        let kind = network.bdkNetworkKind

        switch scriptType {
        case .nativeSegwit:
            return WalletDescriptors(
                external: Descriptor.newBip84(secretKey: secretKey, keychainKind: .external, networkKind: kind),
                change: Descriptor.newBip84(secretKey: secretKey, keychainKind: .internal, networkKind: kind)
            )
        case .taproot:
            return WalletDescriptors(
                external: Descriptor.newBip86(secretKey: secretKey, keychainKind: .external, networkKind: kind),
                change: Descriptor.newBip86(secretKey: secretKey, keychainKind: .internal, networkKind: kind)
            )
        }
    }
}
