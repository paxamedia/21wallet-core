import Foundation
import Testing

@testable import WalletCore

@Suite("Assets and asset amounts")
struct AssetAmountTests {
    private let usdtLike = AssetID(
        hex: "ce091c998b83c78bb71a632313ba3760f1763d9cfcffae02258ffa9865a37bd2"
    )!
    private let otherAsset = AssetID(
        hex: "0000000000000000000000000000000000000000000000000000000000000001"
    )!

    @Test("An asset id must be exactly 32 bytes of hex")
    func rejectsMalformedIdentifiers() {
        #expect(AssetID(hex: String(repeating: "a", count: 64)) != nil)
        #expect(AssetID(hex: String(repeating: "a", count: 63)) == nil)
        #expect(AssetID(hex: String(repeating: "a", count: 65)) == nil)
        #expect(AssetID(hex: "") == nil)
        #expect(AssetID(hex: String(repeating: "z", count: 64)) == nil)
    }

    @Test("Asset ids normalise case and whitespace")
    func normalisesInput() {
        let upper = AssetID(hex: "  " + String(repeating: "AB", count: 32) + "\n")
        let lower = AssetID(hex: String(repeating: "ab", count: 32))
        #expect(upper == lower)
        #expect(upper?.hex == String(repeating: "ab", count: 32))
    }

    @Test("An unrecognised asset is shown by its identifier, never by its claimed ticker")
    func unverifiedAssetsShowIdentifiers() {
        #expect(!AssetRegistry.isVerified(usdtLike))
        #expect(AssetRegistry.displayTicker(for: usdtLike, claiming: "USDt") == usdtLike.truncated)
        #expect(usdtLike.truncated.contains("…"))
    }

    @Test("The verified asset list is empty")
    func registryStartsEmpty() {
        #expect(AssetRegistry.verified.isEmpty)
        #expect(AssetRegistry.asset(for: usdtLike) == nil)
    }

    @Test("Precision comes from the asset, not from bitcoin's eight places")
    func honoursPerAssetPrecision() {
        let twoPlaces = AssetAmount(asset: usdtLike, units: 12_345, precision: 2)
        #expect(twoPlaces.decimal == Decimal(string: "123.45"))

        let eightPlaces = AssetAmount(asset: usdtLike, units: 12_345, precision: 8)
        #expect(eightPlaces.decimal == Decimal(string: "0.00012345"))
    }

    @Test("Amounts of the same asset add")
    func addsMatchingAssets() throws {
        let a = AssetAmount(asset: usdtLike, units: 100, precision: 2)
        let b = AssetAmount(asset: usdtLike, units: 250, precision: 2)
        let sum = try #require(a.adding(b))
        #expect(sum.units == 350)
        #expect(sum.asset == usdtLike)
    }

    @Test("Amounts of different assets refuse to add rather than trapping")
    func refusesToMixAssets() {
        let a = AssetAmount(asset: usdtLike, units: 100, precision: 2)
        let b = AssetAmount(asset: otherAsset, units: 100, precision: 2)
        #expect(a.adding(b) == nil)
    }

    @Test("The same asset at two precisions is not addable either")
    func refusesMismatchedPrecision() {
        let a = AssetAmount(asset: usdtLike, units: 100, precision: 2)
        let b = AssetAmount(asset: usdtLike, units: 100, precision: 8)
        #expect(a.adding(b) == nil)
    }

    @Test("Parsing honours the asset's precision and both decimal separators")
    func parsesDecimalStrings() {
        let comma = AssetAmount(asset: usdtLike, decimalString: "12,34", precision: 2)
        let dot = AssetAmount(asset: usdtLike, decimalString: "12.34", precision: 2)
        #expect(comma?.units == 1_234)
        #expect(dot?.units == 1_234)
    }

    @Test("More fractional digits than the asset can express is refused, not rounded away")
    func refusesOverPreciseInput() {
        #expect(AssetAmount(asset: usdtLike, decimalString: "1.234", precision: 2) == nil)
        #expect(AssetAmount(asset: usdtLike, decimalString: "1.23", precision: 2) != nil)
    }

    @Test("Ambiguous, negative and non-numeric input is refused")
    func refusesJunk() {
        #expect(AssetAmount(asset: usdtLike, decimalString: "1.234,5", precision: 8) == nil)
        #expect(AssetAmount(asset: usdtLike, decimalString: "-1", precision: 8) == nil)
        #expect(AssetAmount(asset: usdtLike, decimalString: "abc", precision: 8) == nil)
        #expect(AssetAmount(asset: usdtLike, decimalString: "", precision: 8) == nil)
        #expect(AssetAmount(asset: usdtLike, decimalString: "1.2.3", precision: 8) == nil)
    }

    @Test("Asset amounts round-trip through storage")
    func codable() throws {
        let amount = AssetAmount(asset: usdtLike, units: -4_200, precision: 2)
        let data = try JSONEncoder().encode(amount)
        let decoded = try JSONDecoder().decode(AssetAmount.self, from: data)
        #expect(decoded == amount)
        #expect(decoded.isNegative)
        #expect(decoded.magnitude.units == 4_200)
    }
}
