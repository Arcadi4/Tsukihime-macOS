import Foundation

extension String {
    /// Decodes bytes as UTF-8, replacing malformed sequences; the game's text tables are UTF-8.
    public init(utf8Bytes span: ByteSpan) {
        self = String(decoding: span, as: UTF8.self)
    }

    /// Decodes ASCII and stops at the first NUL. Bytes outside ASCII become U+FFFD.
    public init(asciiZ span: ByteSpan) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(span.count)
        for byte in span {
            if byte == 0 { break }
            bytes.append(byte < 0x80 ? byte : 0x3F)
        }
        self = String(decoding: bytes, as: UTF8.self)
    }

    /// The string's UTF-8 bytes.
    public var utf8Array: [UInt8] { Array(utf8) }
}

/// Differences the engine computes between two byte ranges, used by the save and history writers.
public func firstDifference(_ left: ByteSpan, _ right: ByteSpan) -> Int? {
    let limit = min(left.count, right.count)
    for i in 0..<limit where left[i] != right[i] { return i }
    return left.count == right.count ? nil : limit
}
