import CryptoKit
import Foundation

/// Lower-case hexadecimal, the representation the game's tables and logs use.
public func hexLower(_ bytes: some Sequence<UInt8>) -> String {
    var text = ""
    text.reserveCapacity(bytes.underestimatedCount * 2)
    for byte in bytes {
        text += String(format: "%02x", byte)
    }
    return text
}

public func sha1Hex(_ bytes: [UInt8]) -> String {
    hexLower(Insecure.SHA1.hash(data: Data(bytes)).map { $0 })
}

public func sha256Hex(_ bytes: [UInt8]) -> String {
    hexLower(SHA256.hash(data: Data(bytes)).map { $0 })
}

public func sha256Hex(_ span: ByteSpan) -> String {
    sha256Hex(span.toArray())
}
