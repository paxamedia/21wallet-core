# 21wallet-core

Bitcoin wallet core behind ₿21 Wallet, for iOS and macOS, built on [bdk-swift](https://github.com/bitcoindevkit/bdk-swift).

- `WalletCore`: amounts, networks, BIP21, extended keys. No platform imports.
- `BitcoinEngine`: descriptors, chain sync, PSBT build, sign and broadcast.
- `SecureStore`: recovery phrase encrypted under a Secure Enclave key.

Not independently audited.

## Install

```swift
.package(url: "https://github.com/paxamedia/21wallet-core.git", from: "0.1.0")
```

## Test

```sh
swift test
```

Network tests are off by default. Enable with `NETWORK_TESTS=1`, `MAINNET_PROBE=1`,
`BROADCAST_TESTS=1` (needs a funded `SIGNET_PHRASE`) or `ENCLAVE_TESTS=1`.

## License

[Apache-2.0](LICENSE)
