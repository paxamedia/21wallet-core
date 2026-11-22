import Testing

@testable import WalletCore

@Suite("PaymentURI (BIP21)")
struct PaymentURITests {
    private let address = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"

    @Test("A full BIP21 URI yields address, amount, label and message")
    func parsesFullURI() throws {
        let uri = try #require(
            PaymentURI("bitcoin:\(address)?amount=0.001&label=Coffee%20Shop&message=Thanks%21")
        )
        #expect(uri.address == address)
        #expect(uri.amount == Amount(sats: 100_000))
        #expect(uri.label == "Coffee Shop")
        #expect(uri.message == "Thanks!")
    }

    @Test("A bare address parses with no parameters")
    func parsesBareAddress() throws {
        let uri = try #require(PaymentURI(address))
        #expect(uri.address == address)
        #expect(uri.amount == nil)
        #expect(uri.label == nil)
    }

    @Test("The scheme is case-insensitive")
    func acceptsUppercaseScheme() throws {
        let uri = try #require(PaymentURI("BITCOIN:\(address)"))
        #expect(uri.address == address)
    }

    @Test("Unknown parameters are preserved for forward compatibility")
    func preservesUnknownParameters() throws {
        let uri = try #require(PaymentURI("bitcoin:\(address)?lightning=lnbc1abc&pj=https://example.com"))
        #expect(uri.otherParameters["lightning"] == "lnbc1abc")
        #expect(uri.otherParameters["pj"] == "https://example.com")
    }

    @Test("An unparseable amount is dropped rather than faking a value")
    func ignoresInvalidAmount() throws {
        let uri = try #require(PaymentURI("bitcoin:\(address)?amount=0.000000001"))
        #expect(uri.address == address)
        #expect(uri.amount == nil)
    }

    @Test("Schemes this wallet cannot pay, and empty input, are rejected")
    func rejectsUnpayableInput() {
        #expect(PaymentURI("lightning:lnbc1pexample") == nil)
        #expect(PaymentURI("https://example.com") == nil)
        #expect(PaymentURI("bitcoin:?amount=1") == nil)
        #expect(PaymentURI("") == nil)
        #expect(PaymentURI("   ") == nil)
    }

    private let liquidAddress = "lq1qqw2v0v3ycnkkfnr9uxnjcrhevfvqxs8p4qhq6qzr6nxjcm4x2jkl"
    private let assetHex = "ce091c998b83c78bb71a632313ba3760f1763d9cfcffae02258ffa9865a37bd2"

    @Test("A bitcoin URI names its chain; a bare address does not")
    func chainComesFromTheScheme() throws {
        #expect(try #require(PaymentURI("bitcoin:\(address)")).chain == .bitcoin)

        #expect(try #require(PaymentURI(address)).chain == nil)
    }

    @Test("A liquidnetwork URI parses as Liquid")
    func parsesLiquidURI() throws {
        let uri = try #require(
            PaymentURI("liquidnetwork:\(liquidAddress)?amount=1.5&label=Invoice")
        )
        #expect(uri.chain == .liquid)
        #expect(uri.address == liquidAddress)
        #expect(uri.label == "Invoice")
        #expect(uri.amount == Amount(sats: 150_000_000))
    }

    @Test("An asset request keeps its amount but refuses to call it bitcoin")
    func assetAmountsAreNotBitcoin() throws {
        let uri = try #require(
            PaymentURI("liquidnetwork:\(liquidAddress)?amount=25.5&assetid=\(assetHex)")
        )
        #expect(uri.assetID?.hex == assetHex)
        #expect(uri.requestedAmount == "25.5")
        #expect(uri.amount == nil)
    }

    @Test("An unreadable asset id is preserved rather than silently ignored")
    func keepsUnparseableAssetID() throws {
        let uri = try #require(
            PaymentURI("liquidnetwork:\(liquidAddress)?amount=25.5&assetid=nonsense")
        )
        #expect(uri.assetID == nil)
        #expect(uri.otherParameters["assetid"] == "nonsense")
        #expect(uri.amount == nil)
    }

    @Test("The Liquid scheme is case-insensitive too")
    func liquidSchemeIsCaseInsensitive() throws {
        #expect(try #require(PaymentURI("LIQUIDNETWORK:\(liquidAddress)")).chain == .liquid)
    }
}
