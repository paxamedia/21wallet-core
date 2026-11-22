import Testing

@testable import WalletCore

@Suite("Address display")
struct AddressDisplayTests {
    @Test(
        "The pieces always reassemble into the address",
        arguments: [
            "",
            "a",
            "abcd",
            "abcdefghijkl",
            "abcdefghijklmnop",
            "abcdefghijklmnopq",
            "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
            "bc1p5cyxnuxmeuwuvkwfem96l2gxvxvz9tv2s3pkxwgvjtjmecdz5cnqvcpqhc",
        ]
    )
    func piecesAlwaysReassemble(_ address: String) {
        let split = AddressDisplay(address)
        #expect(split.reassembled == address, "the address shown must be the address signed")
        #expect(split.head.count + split.middle.count + split.tail.count == address.count)
    }

    @Test("Short input does not repeat characters at both ends")
    func shortInputDoesNotOverlap() {
        let split = AddressDisplay("abcdefghijkl")
        #expect(split.head == "abcdef")
        #expect(split.tail == "ghijkl")
        #expect(split.middle.isEmpty)
    }

    @Test("An empty recipient produces empty pieces rather than trapping")
    func emptyInput() {
        let split = AddressDisplay("")
        #expect(split.head.isEmpty)
        #expect(split.middle.isEmpty)
        #expect(split.tail.isEmpty)
    }

    @Test("A real address shows both ends in full, with the rest in the middle")
    func realAddressKeepsBothEnds() {
        let address = "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
        let split = AddressDisplay(address)

        #expect(split.head == "bc1qcr8t")
        #expect(split.tail == "8z306fyu")
        #expect(split.head.count == AddressDisplay.endLength)
        #expect(split.tail.count == AddressDisplay.endLength)
        #expect(!split.middle.isEmpty)
    }
}
