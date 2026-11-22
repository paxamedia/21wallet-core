import BitcoinDevKit
import Foundation
import WalletCore

public enum SendError: Error, CustomStringConvertible {
    case invalidAddress
    case wrongNetwork(expected: BitcoinNetwork, found: BitcoinNetwork)
    case amountTooSmall
    case insufficientFunds
    case bumpTooLow
    case draftExpired
    case signingRefused
    case engine(String)

    public var description: String {
        switch self {
        case .invalidAddress: "That is not a valid Bitcoin address."
        case .wrongNetwork(let expected, let found):
            "That is a \(found.displayName) address. This wallet is on \(expected.displayName)."
        case .amountTooSmall: "That amount is too small to send."
        case .insufficientFunds: "There is not enough bitcoin in this wallet."
        case .bumpTooLow:
            "The replacement could not pay enough more than the original. Try again when fees have moved, or wait for the original to confirm."
        case .draftExpired: "This transaction is no longer available. Please build it again."
        case .signingRefused: "The transaction could not be signed."
        case .engine(let detail): detail
        }
    }
}

extension WalletEngine {
    public func validateAddress(_ text: String, network: BitcoinNetwork) -> Result<String, SendError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = PaymentURI(trimmed) else { return .failure(.invalidAddress) }

        if let address = try? Address(address: parsed.address, network: network.bdkNetwork),
            address.isValidForNetwork(network: network.bdkNetwork)
        {
            return .success(parsed.address)
        }

        for candidate in BitcoinNetwork.allCases where candidate != network {
            if (try? Address(address: parsed.address, network: candidate.bdkNetwork)) != nil {
                return .failure(.wrongNetwork(expected: network, found: candidate))
            }
        }
        return .failure(.invalidAddress)
    }

    public func feeOptions(using source: any ChainSource) -> FeeOptions {
        guard let estimates = try? source.feeEstimates() else { return .fallback }
        var rates: [FeePriority: UInt64] = [:]
        for priority in FeePriority.presets {
            let candidates = estimates.keys.filter { $0 >= priority.blockTarget }.sorted()
            let key = candidates.first ?? estimates.keys.sorted().last
            if let key, let rate = estimates[key] {
                rates[priority] = max(1, UInt64(rate.rounded()))
            }
        }
        return rates.isEmpty ? .fallback : FeeOptions(rates: rates)
    }

    public func probeChainSource(_ source: any ChainSource) throws -> Int {
        try source.feeEstimates().count
    }

    public func buildDraft(
        for metadata: WalletMetadata,
        recipient: String,
        amount: WalletCore.Amount,
        feeRate: UInt64,
        drainWallet: Bool = false
    ) throws -> TransactionDraft {
        guard case .success(let address) = validateAddress(recipient, network: metadata.network)
        else {
            throw SendError.invalidAddress
        }
        guard drainWallet || amount.sats > 0 else { throw SendError.amountTooSmall }

        let (wallet, _) = try wallet(for: metadata)
        let script = try Address(address: address, network: metadata.network.bdkNetwork)
            .scriptPubkey()
        let rate = try FeeRate.fromSatPerVb(satVb: max(1, feeRate))

        var builder = TxBuilder().feeRate(feeRate: rate)
        if drainWallet {
            builder = builder.drainWallet().drainTo(script: script)
        } else {
            builder = builder.addRecipient(
                script: script, amount: BitcoinDevKit.Amount.fromSat(satoshi: UInt64(amount.sats))
            )
        }

        let psbt: Psbt
        do {
            psbt = try builder.finish(wallet: wallet)
        } catch {
            throw SendError.insufficientFunds
        }

        let draft = try describe(psbt, wallet: wallet, metadata: metadata, recipient: address)
        pendingDrafts[draft.id] = psbt
        return draft
    }

    private func describe(
        _ psbt: Psbt,
        wallet: Wallet,
        metadata: WalletMetadata,
        recipient: String?
    ) throws -> TransactionDraft {
        let transaction = try psbt.extractTx()
        let fee = try wallet.calculateFee(tx: transaction)
        let actualRate = try wallet.calculateFeeRate(tx: transaction)

        var outputs: [DraftOutput] = []
        var sentOut = WalletCore.Amount.zero
        var firstExternalAddress: String?
        for (index, output) in transaction.output().enumerated() {
            let outputAddress = try? Address.fromScript(
                script: output.scriptPubkey, network: metadata.network.bdkNetwork
            )
            let text = outputAddress?.description
            // Change is the internal keychain, not isMine: paying your own address is a real payment.
            let isChange =
                wallet.derivationOfSpk(spk: output.scriptPubkey)?.keychain == .internal
            let value = WalletCore.Amount(sats: Int64(output.value.toSat()))
            if !isChange {
                sentOut = sentOut + value
                if firstExternalAddress == nil { firstExternalAddress = text }
            }
            outputs.append(
                DraftOutput(id: index, address: text, amount: value, isChange: isChange)
            )
        }

        return TransactionDraft(
            recipient: recipient ?? firstExternalAddress ?? "",
            amount: sentOut,
            fee: WalletCore.Amount(sats: Int64(fee.toSat())),
            feeRate: actualRate.toSatPerVbCeil(),
            inputCount: transaction.input().count,
            outputs: outputs,
            network: metadata.network
        )
    }

    public func buildFeeBump(
        for metadata: WalletMetadata,
        txid: String,
        newFeeRate: UInt64
    ) throws -> TransactionDraft {
        let (wallet, _) = try wallet(for: metadata)
        guard
            let canonical = wallet.transactions().first(where: {
                $0.transaction.computeTxid().description == txid
            })
        else {
            throw SendError.draftExpired
        }

        let originalRate =
            (try? wallet.calculateFeeRate(tx: canonical.transaction))?.toSatPerVbCeil() ?? 1
        let effectiveRate = max(FeeOptions.sanitise(newFeeRate), originalRate + 2)

        let builder = BumpFeeTxBuilder(
            txid: canonical.transaction.computeTxid(),
            feeRate: try FeeRate.fromSatPerVb(satVb: effectiveRate)
        )
        let psbt: Psbt
        do {
            psbt = try builder.finish(wallet: wallet)
        } catch {
            let detail = String(describing: error).lowercased()
            throw detail.contains("fee") ? SendError.bumpTooLow : SendError.insufficientFunds
        }

        let draft = try describe(psbt, wallet: wallet, metadata: metadata, recipient: nil)
        pendingDrafts[draft.id] = psbt
        return draft
    }

    public func discardDraft(_ id: UUID) {
        pendingDrafts[id] = nil
    }

    public func signDraft(
        _ id: UUID,
        for metadata: WalletMetadata,
        secret: WalletSecret
    ) throws -> String {
        guard let psbt = pendingDrafts[id] else { throw SendError.draftExpired }
        let signer = try signingWallet(for: metadata, secret: secret)
        guard try signer.sign(psbt: psbt) else { throw SendError.signingRefused }
        return try psbt.extractTx().computeTxid().description
    }

    // Reveal as far as the watch wallet has derived. A fixed cap fails to sign for long-lived wallets.
    func signingWallet(for metadata: WalletMetadata, secret: WalletSecret) throws -> Wallet {
        let descriptors = try DescriptorFactory.descriptors(
            secret: secret,
            network: metadata.network,
            scriptType: metadata.scriptType
        )
        let signer = try Wallet(
            descriptor: descriptors.external,
            changeDescriptor: descriptors.change,
            network: metadata.network.bdkNetwork,
            persister: try Persister.newInMemory()
        )
        let target = try signingRevealTarget(for: metadata)
        _ = signer.revealAddressesTo(keychain: .external, index: target.external)
        _ = signer.revealAddressesTo(keychain: .internal, index: target.change)
        return signer
    }

    func signingRevealTarget(
        for metadata: WalletMetadata
    ) throws -> (external: UInt32, change: UInt32) {
        let (watch, _) = try wallet(for: metadata)
        return (
            external: max(watch.nextDerivationIndex(keychain: .external), 100),
            change: max(watch.nextDerivationIndex(keychain: .internal), 100)
        )
    }

    public func broadcastDraft(
        _ id: UUID,
        for metadata: WalletMetadata,
        using source: any ChainSource
    ) throws -> String {
        guard let psbt = pendingDrafts[id] else { throw SendError.draftExpired }
        let transaction = try psbt.extractTx()
        try source.broadcast(transaction)
        pendingDrafts[id] = nil

        if let (wallet, _) = try? wallet(for: metadata) {
            // Best-effort: the payment is already broadcast. Reporting failure here invites a double send.
            try? commit(wallet, for: metadata)
        }

        return transaction.computeTxid().description
    }

    public func signAndBroadcast(
        draft id: UUID,
        for metadata: WalletMetadata,
        secret: WalletSecret,
        using source: any ChainSource
    ) throws -> String {
        _ = try signDraft(id, for: metadata, secret: secret)
        return try broadcastDraft(id, for: metadata, using: source)
    }
}
