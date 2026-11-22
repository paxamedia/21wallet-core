import Foundation
import Testing

@testable import WalletCore

@Suite("Vault and accounts")
struct VaultTests {
    private func account(
        _ network: AccountNetwork,
        id: String = UUID().uuidString,
        hidden: Bool = false
    ) -> Account {
        Account(
            id: id,
            network: network,
            scriptType: .nativeSegwit,
            externalDescriptor: "wpkh(xpub.../0/*)",
            internalDescriptor: "wpkh(xpub.../1/*)",
            isHidden: hidden
        )
    }

    @Test("A chain and its network cannot disagree")
    func networkCarriesItsChain() {
        #expect(AccountNetwork.bitcoin(.mainnet).chain == .bitcoin)
        #expect(AccountNetwork.liquid(.mainnet).chain == .liquid)
        #expect(AccountNetwork.liquid(.mainnet).bitcoinNetwork == nil)
        #expect(AccountNetwork.bitcoin(.signet).liquidNetwork == nil)
    }

    @Test("A second account lands on the network the first one is already using")
    func counterpartMatchesEnvironment() {
        #expect(AccountNetwork.bitcoin(.mainnet).counterpart(on: .liquid) == .liquid(.mainnet))
        #expect(AccountNetwork.bitcoin(.signet).counterpart(on: .liquid) == .liquid(.testnet))
        #expect(AccountNetwork.liquid(.testnet).counterpart(on: .bitcoin) == .bitcoin(.signet))
    }

    @Test("Accounts sort Bitcoin first however they were added")
    func bitcoinComesFirst() {
        var vault = Vault()
        vault.upsert(account(.liquid(.mainnet)))
        vault.upsert(account(.bitcoin(.mainnet)))
        #expect(vault.accounts.map(\.chain) == [.bitcoin, .liquid])
    }

    @Test("A second account on the same chain replaces the first")
    func upsertReplacesPerChain() {
        var vault = Vault()
        vault.upsert(account(.bitcoin(.mainnet), id: "first"))
        vault.upsert(account(.bitcoin(.mainnet), id: "second"))

        #expect(vault.accounts.count == 1)
        #expect(vault.account(for: .bitcoin)?.id == "second")
    }

    @Test("A single-chain vault hides every chain affordance")
    func singleChainDrivesDisclosure() {
        var vault = Vault()
        #expect(vault.isSingleChain)

        vault.upsert(account(.bitcoin(.mainnet)))
        #expect(vault.isSingleChain)

        vault.upsert(account(.liquid(.mainnet)))
        #expect(!vault.isSingleChain)

        let didHide = vault.setHidden(true, forChain: .liquid)
        #expect(didHide)
        #expect(vault.isSingleChain)
        #expect(vault.visibleChains == [.bitcoin])
    }

    @Test("The last visible account cannot be hidden")
    func refusesToHideEverything() {
        var vault = Vault()
        vault.upsert(account(.bitcoin(.mainnet)))

        let didHide = vault.setHidden(true, forChain: .bitcoin)
        #expect(didHide == false)
        #expect(vault.visibleAccounts.count == 1)
    }

    @Test("A hidden account is still derived and still in the vault")
    func hidingIsNotDeleting() {
        var vault = Vault()
        vault.upsert(account(.bitcoin(.mainnet)))
        vault.upsert(account(.liquid(.mainnet), id: "liquid"))
        _ = vault.setHidden(true, forChain: .liquid)

        #expect(vault.accounts.count == 2)
        #expect(vault.account(for: .liquid)?.isHidden == true)
        #expect(vault.account(id: "liquid") != nil)
    }

    @Test("Funds may not be received until the phrase is verified")
    func backupGatesReceiving() {
        var vault = Vault()
        vault.upsert(account(.bitcoin(.mainnet)))
        #expect(!vault.canReceive)

        vault.isBackupVerified = true
        #expect(vault.canReceive)
    }

    @Test("Backup verification belongs to the vault, not an account")
    func backupLivesOnTheVault() throws {
        var vault = Vault(isBackupVerified: true)
        vault.upsert(account(.bitcoin(.mainnet)))
        vault.upsert(account(.liquid(.mainnet)))

        #expect(vault.isBackupVerified)
        let metadata = try #require(vault.account(for: .bitcoin)?.bitcoinMetadata)
        #expect(metadata.network == .mainnet)
    }

    @Test("A Liquid account has no Bitcoin metadata to give")
    func liquidHasNoBitcoinMetadata() {
        #expect(account(.liquid(.mainnet)).bitcoinMetadata == nil)
        #expect(account(.bitcoin(.signet)).bitcoinMetadata?.network == .signet)
    }

    @Test("An account round-trips through the Bitcoin engine's view of it")
    func bitcoinMetadataRoundTrips() throws {
        let original = account(.bitcoin(.mainnet), id: "keep-this-id")
        let metadata = try #require(original.bitcoinMetadata)
        let rebuilt = Account(bitcoin: metadata)

        #expect(rebuilt.id == original.id)
        #expect(rebuilt.network == original.network)
        #expect(rebuilt.externalDescriptor == original.externalDescriptor)
        #expect(rebuilt.internalDescriptor == original.internalDescriptor)
        #expect(rebuilt.scriptType == original.scriptType)
    }

    @Test("A vault round-trips through storage")
    func codable() throws {
        var vault = Vault(isBackupVerified: true)
        vault.upsert(account(.bitcoin(.mainnet)))
        vault.upsert(account(.liquid(.testnet)))
        vault.setLabel("Spending", forChain: .bitcoin)

        let data = try JSONEncoder().encode(vault)
        let decoded = try JSONDecoder().decode(Vault.self, from: data)

        #expect(decoded == vault)
        #expect(decoded.account(for: .bitcoin)?.label == "Spending")
        #expect(decoded.account(for: .liquid)?.network == .liquid(.testnet))
    }

    @Test("A blank label is no label")
    func blankLabelClears() {
        var vault = Vault()
        vault.upsert(account(.bitcoin(.mainnet)))

        vault.setLabel("   ", forChain: .bitcoin)
        #expect(vault.account(for: .bitcoin)?.label == nil)
        #expect(vault.account(for: .bitcoin)?.displayName == "Bitcoin")
    }

    @Test("Only Liquid carries a trust note")
    func trustNotes() {
        #expect(ChainKind.bitcoin.trustNote == nil)
        #expect(ChainKind.liquid.trustNote?.contains("federated") == true)
        #expect(ChainKind.liquid.supportsIssuedAssets)
        #expect(!ChainKind.bitcoin.supportsIssuedAssets)
        #expect(ChainKind.liquid.isConfidential)
    }

    @Test("Liquid derivation uses coin type 1776 on mainnet and 1 on testnet")
    func liquidCoinTypes() {
        #expect(LiquidNetwork.mainnet.bip44CoinType == 1776)
        #expect(LiquidNetwork.testnet.bip44CoinType == 1)
        #expect(LiquidNetwork.mainnet.confidentialHRP == "lq")
        #expect(LiquidNetwork.testnet.confidentialHRP == "tlq")
    }

    @Test("The visual identity is random per vault, not derived from anything public")
    func displaySaltIsNotComputable() {
        let a = Vault()
        let b = Vault()

        #expect(a.displaySalt != b.displaySalt)
        #expect(a.displaySalt.count >= 32)

        var withAccount = Vault()
        withAccount.upsert(account(.bitcoin(.mainnet)))
        #expect(!withAccount.displaySalt.contains(withAccount.accounts[0].externalDescriptor))
        #expect(withAccount.displaySalt != withAccount.accounts[0].externalDescriptor)
        #expect(withAccount.displaySalt != withAccount.id)
    }

    @Test("The visual identity survives storage unchanged")
    func displaySaltRoundTrips() throws {
        var vault = Vault(isBackupVerified: true)
        vault.upsert(account(.bitcoin(.mainnet)))

        let data = try JSONEncoder().encode(vault)
        let decoded = try JSONDecoder().decode(Vault.self, from: data)
        #expect(decoded.displaySalt == vault.displaySalt)
    }

    @Test("A vault stored before the salt existed decodes with a fresh one")
    func legacyVaultGainsASalt() throws {
        let legacy = """
            {"id":"v1","createdAt":0,"isBackupVerified":true,"accounts":[]}
            """
        let decoded = try JSONDecoder().decode(Vault.self, from: Data(legacy.utf8))
        #expect(!decoded.displaySalt.isEmpty)
        #expect(decoded.id == "v1")
        #expect(decoded.isBackupVerified)
    }
}
