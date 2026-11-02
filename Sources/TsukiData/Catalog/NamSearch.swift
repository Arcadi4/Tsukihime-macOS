import Foundation
import TsukiCore
import TsukiEngine

/// The engine's NAM file-name search (VA 0xC3270, docs/formats/archives_ui_movies.md 2.3): the key of a file name and the
/// search over the five name tables in the order allpac4, allpac3, allpac1_2, allpac1, allpac0. A port of
/// `tsuki.catalog.nam_key`, `find_image` and `ImageNameIndex`.
public struct ImageNameIndex {
    /// Compared characters of a name (0x1C), extension included.
    public static let keyLength = 28

    /// Records scanned per table (0x5014).
    public static let scanLimit = 0x5014

    /// The archives searched by name, in search order (allpac2 is never searched).
    public static let searchOrder: [ImageArchive] = [.allpac4, .allpac3, .allpac1_2, .allpac1, .allpac0]

    private let maps: [ImageArchive: [String: Int]]
    private let nams: [ImageArchive: NamTable]

    /// Builds the index from the name tables of the archives (missing archives are skipped).
    public init(_ nams: [ImageArchive: NamTable]) {
        self.nams = nams
        var maps: [ImageArchive: [String: Int]] = [:]
        maps.reserveCapacity(nams.count)
        for (archive, table) in nams {
            var map: [String: Int] = [:]
            let limit = min(table.count, Self.scanLimit)
            map.reserveCapacity(limit)
            for i in 0..<limit {
                let name = table[i]
                if name.isEmpty {
                    break  // 'cmp byte [rcx], 0; je': the end of this table
                }

                let key = Self.truncate(name)
                if map[key] == nil {
                    map[key] = i
                }
            }
            maps[archive] = map
        }
        self.maps = maps
    }

    /// The lookup key of `name` exactly as VA 0xC3280..0xC32FE builds it: the key starts after the last
    /// backslash seen in the first 256 bytes before a NUL; 28 bytes are copied, 'a'..'z' become upper case unless the
    /// previous output byte is at least 0x80 (a Shift-JIS lead byte). Returned without padding: the bytes before the
    /// first NUL.
    public static func key(_ name: ByteSpan) -> [UInt8] {
        let nul = name.firstIndex(of: 0) ?? name.count
        let raw = name.slice(0, nul)
        var start = 0
        for i in 0..<min(256, raw.count) where raw[i] == 0x5C {
            start = i + 1
        }

        let length = min(keyLength, raw.count - start)
        var output = [UInt8](repeating: 0, count: length)
        var previous: UInt8 = 0
        for i in 0..<length {
            let ch = raw[start + i]
            let value = (ch >= 0x61 && ch <= 0x7A && previous < 0x80) ? ch - 0x20 : ch
            output[i] = value
            previous = value
        }
        return output
    }

    /// The key of an ASCII name.
    /// - Throws: `TsukiError.format` when the name has a character above 0x7F: pass the bytes instead.
    public static func key(_ name: String) throws -> [UInt8] {
        key(ByteSpan(try ascii(name)))
    }

    /// Packs an ASCII string into bytes.
    /// - Throws: `TsukiError.format` when a character is above 0x7F.
    static func ascii(_ name: String) throws -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(name.utf8.count)
        for scalar in name.unicodeScalars {
            guard scalar.value <= 0x7F else {
                throw TsukiError.format("the name has a character above 0x7F; pass its bytes (Shift-JIS) instead")
            }
            bytes.append(UInt8(scalar.value))
        }
        return bytes
    }

    /// The first match of `name` (a file name with its extension) in the search order, or nil.
    /// With `allpac1Available` false allpac1 and allpac1_2 are skipped (the PlayGo chunks are not there).
    public func find(_ name: ByteSpan, allpac1Available: Bool = true) -> ImageId? {
        let key = EbootReader.latin1(ByteSpan(Self.key(name)))
        for archive in Self.searchOrder {
            if !allpac1Available && (archive == .allpac1 || archive == .allpac1_2) {
                continue
            }

            if let index = maps[archive]?[key] {
                return ImageId(archive: archive, index: index)
            }
        }
        return nil
    }

    /// The first match of an ASCII file name.
    public func find(_ name: String, allpac1Available: Bool = true) throws -> ImageId? {
        find(ByteSpan(try Self.ascii(name)), allpac1Available: allpac1Available)
    }

    /// The engine's own linear scan (`find_image`): the same result as `find(_:allpac1Available:)` without the dictionaries.
    public func findLinear(_ name: ByteSpan, allpac1Available: Bool = true) -> ImageId? {
        let key = EbootReader.latin1(ByteSpan(Self.key(name)))
        for archive in Self.searchOrder {
            if !allpac1Available && (archive == .allpac1 || archive == .allpac1_2) {
                continue
            }

            guard let table = nams[archive] else { continue }
            for i in 0..<min(table.count, Self.scanLimit) {
                let record = table[i]
                if record.isEmpty {
                    break
                }

                if Self.truncate(record) == key {
                    return ImageId(archive: archive, index: i)
                }
            }
        }
        return nil
    }

    /// The first match of an ASCII file name by the engine's linear scan.
    public func findLinear(_ name: String, allpac1Available: Bool = true) throws -> ImageId? {
        findLinear(ByteSpan(try Self.ascii(name)), allpac1Available: allpac1Available)
    }

    private static func truncate(_ name: String) -> String {
        name.count > keyLength ? String(name.prefix(keyLength)) : name
    }
}
