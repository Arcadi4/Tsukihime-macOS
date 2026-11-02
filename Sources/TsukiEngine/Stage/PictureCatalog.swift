/// The catalog fields of a picture that the layer model reads (docs/formats/images.md 8,
/// layers.md 7.2).
public struct PictureInfo: Sendable {
    /// Catalog anchor x (+0x34): the point of the picture that sits on the layer position.
    public let anchorX: Int
    /// Catalog anchor y (+0x38).
    public let anchorY: Int
    /// Size class (+0x42): 0 A, 1 L, 2 M, 3 S.
    public let scaleClass: Int
    /// Draw flags (+0x3D): bit 0 = no own colour effect, bit 1 = ignores the screen shock (the seven
    /// colour fills), bit 2 = animated.
    public let drawFlags: Int
    /// The record has a face layer (catalog name1).
    public let hasFace: Bool

    public init(anchorX: Int, anchorY: Int, scaleClass: Int, drawFlags: Int, hasFace: Bool) {
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.scaleClass = scaleClass
        self.drawFlags = drawFlags
        self.hasFace = hasFace
    }

    /// The factor of the size class: 1, 0.5, 0.25, 0.125 for A, L, M, S (VA 0x526A3, 0x865A2).
    public var classFactor: Float {
        switch scaleClass {
        case 1: return 0.5
        case 2: return 0.25
        case 3: return 0.125
        default: return 1.0
        }
    }
}

/// The picture catalog and the picture-name map as the layer model uses them (STCH name lookup
/// VA 0x78410, the name list at data VA 0x7F6800, the image catalog at 0x671900). The data layer
/// implements it over the game catalog; tests over arrays.
public protocol PictureCatalog: AnyObject {
    /// Number of catalog records (14,744 in v01.01).
    var count: Int { get }

    /// The picture id of a script picture name (VA 0x78410: upper case up to the first '.', 32
    /// bytes), or -1.
    func lookup(_ name: String) -> Int

    /// The name list entry of a picture, without padding; "" outside 0..count-1.
    func name(_ pic: Int) -> String

    /// The catalog record of a picture in 0..count-1.
    func info(_ pic: Int) -> PictureInfo
}

/// Helpers on ``PictureCatalog`` that carry the engine's quirks.
public enum PictureNames {
    /// The name the engine reads for a picture (VA 0x82BD0): the 32-byte entry, NUL-terminated at
    /// byte 32; names of 30 or more characters carry the CR LF of the list (`name.ljust(30) +
    /// "\r\n"`, cut to 32 bytes).
    public static func engineName(_ c: PictureCatalog, _ pic: Int) -> String {
        let n = c.name(pic)
        if n.count < 30 {
            return n
        }
        var padded = n
        while padded.count < 30 {
            padded.append("\0")
        }
        return String((padded + "\r\n").prefix(32))
    }

    /// The catalog anchor of a picture; the id -1 (or any id outside the table) reads the bytes
    /// before the table, whose low halves are (256, 255).
    public static func catalogAnchor(_ c: PictureCatalog, _ pic: Int) -> (x: Int, y: Int) {
        if pic >= 0 && pic < c.count {
            let info = c.info(pic)
            return (info.anchorX, info.anchorY)
        }
        return (256, 255)
    }

    /// The size class of a picture (VA 0x41BA0: catalog +0x42 for ids 0..0x39B6, else 0).
    public static func scaleClass(_ c: PictureCatalog, _ pic: Int) -> Int {
        pic >= 0 && pic <= 0x39B6 && pic < c.count ? c.info(pic).scaleClass : 0
    }

    /// The variant digits (hh, vv) of a `<base>_hh_vv` picture name (STCH 0x81900, motion 0xBEB9C):
    /// length of 7 or more, '_' at len-6 and len-3, prefix "IMG" (exact case as the oracle's motion
    /// path) or length of 15 or more; digits are read without validation.
    public static func variantDigits(_ n: String) -> (h: Int, v: Int) {
        let c = Array(n)
        guard c.count >= 7, c[c.count - 6] == "_", c[c.count - 3] == "_",
              n.hasPrefix("IMG") || c.count >= 15 else {
            return (0, 0)
        }
        return (digits2(c[c.count - 5], c[c.count - 4]), digits2(c[c.count - 2], c[c.count - 1]))
    }

    /// The same test as STCH makes for the source layer's name (prefix compared case-insensitively).
    public static func variantDigitsStch(_ n: String) -> (h: Int, v: Int) {
        let c = Array(n)
        guard c.count >= 7, c[c.count - 6] == "_", c[c.count - 3] == "_",
              hasIMGPrefix(n, ignoringCase: true) || c.count >= 15 else {
            return (0, 0)
        }
        return (digits2(c[c.count - 5], c[c.count - 4]), digits2(c[c.count - 2], c[c.count - 1]))
    }

    /// Two name characters read as decimal digits without validation (VA 0x81900).
    public static func digits2(_ a: Character, _ b: Character) -> Int {
        (Int(a.asciiValue ?? 48) - 48) * 10 + (Int(b.asciiValue ?? 48) - 48)
    }

    /// VA 0xBEE91..0xBF03F: the picture name for new digits (nh, nv). (0, 0) cuts the `_hh_vv`
    /// suffix off; a name without digits gets `_00_00` appended; then the units digits are written,
    /// and the tens digit only for values of 10 or more (a quirk: 12 to 5 gives 15).
    public static func variantName(_ name: String, _ hh: Int, _ vv: Int, _ nh: Int, _ nv: Int) -> String {
        var b = Array(name.utf8)
        if (nh | nv) == 0 {
            return String(decoding: b.prefix(max(b.count - 6, 0)), as: UTF8.self)
        }
        if (hh | vv) == 0 {
            b.append(contentsOf: Array("_00_00".utf8))
        }
        let n = b.count
        b[n - 4] = UInt8(truncatingIfNeeded: 48 + nh % 10)
        if nh >= 10 {
            b[n - 5] = UInt8(truncatingIfNeeded: 48 + nh / 10 % 10)
        }
        b[n - 1] = UInt8(truncatingIfNeeded: 48 + nv % 10)
        if nv >= 10 {
            b[n - 2] = UInt8(truncatingIfNeeded: 48 + nv / 10 % 10)
        }
        return String(decoding: b, as: UTF8.self)
    }

    private static func hasIMGPrefix(_ n: String, ignoringCase: Bool) -> Bool {
        let prefix = n.prefix(3)
        return ignoringCase ? prefix.uppercased() == "IMG" : prefix == "IMG"
    }
}

/// A ``PictureCatalog`` over arrays: the name list and the catalog records in id order (tests,
/// golden data). The name lookup is the oracle's: the upper-cased text up to the first '.', cut to
/// 32 characters, in a dictionary where a later duplicate wins.
public final class ArrayPictureCatalog: PictureCatalog {
    private let names: [String]
    private let infos: [PictureInfo]
    private let index: [String: Int]

    /// Creates the catalog.
    public init(names: [String], info: [PictureInfo]) {
        self.names = names
        infos = info
        var index: [String: Int] = [:]
        index.reserveCapacity(names.count)
        for (i, name) in names.enumerated() {
            index[name.uppercased()] = i
        }
        self.index = index
    }

    public var count: Int { infos.count }

    public func lookup(_ name: String) -> Int {
        let key: String
        if let dot = name.firstIndex(of: ".") {
            key = String(name[..<dot])
        } else {
            key = name
        }
        return index[(key.count > 32 ? String(key.prefix(32)) : key).uppercased()] ?? -1
    }

    public func name(_ pic: Int) -> String {
        pic >= 0 && pic < names.count ? names[pic] : ""
    }

    public func info(_ pic: Int) -> PictureInfo {
        infos[pic]
    }
}
