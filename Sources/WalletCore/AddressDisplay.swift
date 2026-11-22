import Foundation

public struct AddressDisplay: Sendable, Equatable {
    public let head: String
    public let middle: String
    public let tail: String

    public static let endLength = 8

    public init(_ address: String, endLength: Int = AddressDisplay.endLength) {
        let split = min(max(endLength, 0), address.count / 2)
        let start = address.index(address.startIndex, offsetBy: split)
        let end = address.index(address.endIndex, offsetBy: -split)

        head = String(address.prefix(split))
        tail = String(address.suffix(split))
        middle = start < end ? String(address[start..<end]) : ""
    }

    public var reassembled: String { head + middle + tail }
}
