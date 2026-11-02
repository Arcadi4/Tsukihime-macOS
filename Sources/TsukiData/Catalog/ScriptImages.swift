import Foundation
import TsukiCore
import TsukiEngine

/// How a script image id (`img2511`, `WHITE`, `boy_a_00_00_n01`) becomes a name-list key: VA 0x78410
/// (upper-case flag set at every call site) and the STCH / SCH2 variant suffix of VA 0x81760
/// (docs/formats/archives_ui_movies.md 2.4). A port of `script_image_key` and `stch_image_name`.
public enum ScriptImageNames {
    /// The key copies at most 32 bytes.
    public static let keyLength = 32

    /// The name-list key of a script id: at most 32 bytes, stopping at a NUL or a '.', bytes at least 0x80 unchanged, 'a'..'z'
    /// upper-cased. One character per byte.
    public static func key(_ name: ByteSpan) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(min(keyLength, name.count))
        for i in 0..<min(keyLength, name.count) {
            let ch = name[i]
            if ch == 0 || ch == 0x2E {
                break
            }

            scalars.append(UnicodeScalar(ch >= 0x61 && ch <= 0x7A ? ch - 0x20 : ch))
        }
        return String(scalars)
    }

    /// The key of an ASCII id.
    public static func key(_ name: String) throws -> String {
        key(ByteSpan(try ImageNameIndex.ascii(name)))
    }

    /// The name STCH / SCH2 look up for the arguments a9 = `aa` and a10 = `bb`: when either is non-zero the suffix
    /// `_%02d_%02d` is appended, with `v % 100` for a positive value and `00` otherwise.
    public static func stchName(_ baseName: String, _ aa: Int, _ bb: Int) -> String {
        (aa | bb) != 0 ? "\(baseName)_\(twoDigits(aa))_\(twoDigits(bb))" : baseName
    }

    /// The same for a name in bytes.
    public static func stchName(_ baseName: ByteSpan, _ aa: Int, _ bb: Int) -> [UInt8] {
        let base = baseName.toArray()
        guard (aa | bb) != 0 else { return base }
        return base + Array("_\(twoDigits(aa))_\(twoDigits(bb))".utf8)
    }

    private static func twoDigits(_ v: Int) -> String {
        v > 0 ? String(format: "%02d", v % 100) : "00"
    }
}

/// What the engine draws for one script image id.
public struct ResolvedImage: Sendable {
    /// The name-list key.
    public let key: String
    /// Image-table / name-list index k; -1 when the name is unknown.
    public let index: Int
    /// Record file, drawn first.
    public let file: String?
    /// Record overlay, drawn over the file (paired sprites only).
    public let overlay: String?
    /// The file found by the NAM search; nil when missing (3 retail bodies).
    public let fileId: ImageId?
    /// The overlay found by the NAM search.
    public let overlayId: ImageId?
    /// The allpac2 copy (`0x30000 | k`): the thumbnail path.
    public let reducedId: ImageId?

    public init(key: String, index: Int, file: String? = nil, overlay: String? = nil,
                fileId: ImageId? = nil, overlayId: ImageId? = nil, reducedId: ImageId? = nil) {
        self.key = key
        self.index = index
        self.file = file
        self.overlay = overlay
        self.fileId = fileId
        self.overlayId = overlayId
        self.reducedId = reducedId
    }

    /// True when the id is in the name list.
    public var found: Bool { index >= 0 }
}

/// The engine-faithful resolution of script image ids: key, then position in the embedded name list (the first of equal
/// names), then the image-table record, then its file and overlay through the NAM search. A port of
/// `tsuki.catalog.ScriptImageResolver`.
public struct ScriptImageResolver {
    private let map: [String: Int]
    private let table: [CatalogEntry]
    private let index: ImageNameIndex

    /// Creates a resolver.
    /// - Parameters:
    ///   - names: the name list of data VA 0x7F6800 (`PictureNameLists.read`).
    ///   - table: the image table records.
    ///   - index: the NAM search over allpac4, allpac3, allpac1_2, allpac1 and allpac0.
    public init(names: [String], table: [CatalogEntry], index: ImageNameIndex) {
        var map: [String: Int] = [:]
        map.reserveCapacity(names.count)
        for (k, name) in names.enumerated() where map[name] == nil {
            map[name] = k  // a std::map insert keeps the first key
        }
        self.map = map
        self.table = table
        self.index = index
    }

    /// Position of the id in the name list, or -1.
    public func indexOf(_ name: ByteSpan) -> Int {
        map[ScriptImageNames.key(name)] ?? -1
    }

    /// Position of an ASCII id in the name list, or -1.
    public func indexOf(_ name: String) throws -> Int {
        indexOf(ByteSpan(try ImageNameIndex.ascii(name)))
    }

    /// Resolves `name` as STCH / SCH2 would with a9 = `aa`, a10 = `bb` (pass 0, 0 for SPFC / SPRD / STCG and for a plain STCH).
    public func resolve(_ name: ByteSpan, aa: Int = 0, bb: Int = 0) throws -> ResolvedImage {
        let key = ScriptImageNames.key(ByteSpan(ScriptImageNames.stchName(name, aa, bb)))
        let k = map[key] ?? -1
        guard k >= 0, k < table.count else {
            return ResolvedImage(key: key, index: -1)
        }

        let record = table[k]
        var overlayId: ImageId? = nil
        if let overlay = record.name1 {
            overlayId = try index.find(overlay)
        }
        return ResolvedImage(key: key, index: k, file: record.name0, overlay: record.name1,
                             fileId: try index.find(record.name0), overlayId: overlayId,
                             reducedId: ImageId(archive: .allpac2, index: k))
    }

    /// Resolves an ASCII id.
    public func resolve(_ name: String, aa: Int = 0, bb: Int = 0) throws -> ResolvedImage {
        try resolve(ByteSpan(try ImageNameIndex.ascii(name)), aa: aa, bb: bb)
    }
}
