import Foundation
import Testing

@testable import WalletCore

@Suite("Base58")
struct Base58Tests {
    private static let vectors: [(hex: String, encoded: String)] = [
        ("", ""),
        ("61", "2g"),
        ("626262", "a3gV"),
        ("636363", "aPEr"),
        ("73696d706c792061206c6f6e6720737472696e67", "2cFupjhnEsSn59qHXstmK2ffpLv2"),
        ("00eb15231dfceb60925886b67d065299925915aeb172c06647", "1NS17iag9jJgTHD1VXjvLCEnZuQ3rJDE9L"),
        ("516b6fcd0f", "ABnLTmg"),
        ("bf4f89001e670274dd", "3SEo3LWLoPntC"),
        ("572e4794", "3EFU7m"),
        ("ecac89cad93923c02321", "EJDM8drfXA6uyA"),
        ("10c8511e", "Rt5zm"),
        ("00000000000000000000", "1111111111"),
    ]

    private func data(fromHex hex: String) -> Data {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return Data(bytes)
    }

    @Test("Encoding matches the published vectors", arguments: Base58Tests.vectors)
    func encodesVectors(_ vector: (hex: String, encoded: String)) {
        #expect(Base58.encode(data(fromHex: vector.hex)) == vector.encoded)
    }

    @Test("Decoding matches the published vectors", arguments: Base58Tests.vectors)
    func decodesVectors(_ vector: (hex: String, encoded: String)) {
        guard !vector.encoded.isEmpty else {
            #expect(Base58.decode(vector.encoded) == nil)
            return
        }
        #expect(Base58.decode(vector.encoded) == data(fromHex: vector.hex))
    }

    @Test("Zero-valued input is exactly as long as it should be")
    func zeroValuedInput() {
        #expect(Base58.encode(Data()) == "")
        #expect(Base58.encode(Data([0x00])) == "1")
        #expect(Base58.encode(Data([0x00, 0x00])) == "11")
        #expect(Base58.decode("1") == Data([0x00]))
        #expect(Base58.decode("11") == Data([0x00, 0x00]))
    }

    @Test("Every vector survives a round trip")
    func roundTrips() {
        for vector in Self.vectors where !vector.encoded.isEmpty {
            let bytes = data(fromHex: vector.hex)
            #expect(Base58.decode(Base58.encode(bytes)) == bytes, "failed for \(vector.encoded)")
        }
    }

    @Test("A character outside the alphabet is refused")
    func rejectsNonAlphabet() {
        for candidate in ["0", "O", "I", "l", "abc0def", " "] {
            #expect(Base58.decode(candidate) == nil, "'\(candidate)' must not decode")
        }
    }
}
