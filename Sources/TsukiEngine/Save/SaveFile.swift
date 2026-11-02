import Foundation
import TsukiCore

/// Our own save file (`%APPDATA%/Tsuki/…`, the path is the app's choice) and the PS4 save image import / export.
///
/// File layout, version 1, all integers little-endian:
/// ```
/// 0x00  char[8] "TSUKISAV"
/// 0x08  u32 version (1)       0x0C u32 flags (0)
/// 0x10  u32 systemSize (0x18AC)   0x14 u32 slotSize (0x7108)
/// 0x18  u32 slotRecords           0x1C u32 CRC-32 of bytes 0x00..0x1B
/// 0x20  system block (0x18AC bytes, the PS4 layout of adv_state.md 7.5) + u32 CRC-32 of those bytes
/// then slotRecords records:  u16 slot index (strictly ascending, 0..139), u16 thumbnail format (0 = none),
///       u32 thumbnail length, slot (0x7108 bytes, the PS4 layout of adv_state.md 7.4), thumbnail bytes,
///       u32 CRC-32 of the whole record before the CRC
/// footer: char[8] "TSUKIEND", u32 total file length, u32 CRC-32 of every byte before the footer's CRC
/// ```
public enum SaveFile {
    /// The file magic.
    public static let magic: [UInt8] = Array("TSUKISAV".utf8)

    private static let footerMagic: [UInt8] = Array("TSUKIEND".utf8)

    /// The format version this code writes and reads.
    public static let version = 1

    private static let headerSize = 0x20
    private static let maxThumbnailBytes = 8 * 1024 * 1024
    private static let maxFileBytes = 256 * 1024 * 1024

    /// Size of a PS4 save image (4 MiB).
    public static let ps4ImageSize = 0x400000

    private static let ps4SlotBase = 0x1A00
    private static let ps4SlotStride = 0x7140

    // -- writing -----------------------------------------------------------------------------------------------------

    /// The file's bytes.
    public static func toBytes(_ store: SaveStore) throws -> [UInt8] {
        var body: [UInt8] = []
        let slots = store.storedSlots()

        var header = [UInt8](repeating: 0, count: headerSize)
        for i in 0..<magic.count {
            header[i] = magic[i]
        }
        writeU32LE(&header, 8, UInt32(version))
        writeU32LE(&header, 0x10, UInt32(SystemBlock.size))
        writeU32LE(&header, 0x14, UInt32(SlotImage.size))
        writeU32LE(&header, 0x18, UInt32(slots.count))
        let headerCrc = Crc32.compute(Array(header[0..<0x1C]))
        writeU32LE(&header, 0x1C, headerCrc)
        body.append(contentsOf: header)

        let system = store.systemData.block
        system.magic = SystemBlock.magicValue
        if system.used == 0 {
            system.used = 1
        }
        let systemBytes = Array(system.bytes)
        body.append(contentsOf: systemBytes)
        let sysCrc = Crc32.compute(systemBytes)
        appendU32LE(&body, sysCrc)

        for slot in slots {
            guard let image = store.getSlot(slot) else { continue }
            let thumb = store.getThumbnail(slot)
            if let thumb = thumb {
                if thumb.data.count > maxThumbnailBytes || thumb.format == 0 {
                    throw TsukiError.format("slot \(slot): a thumbnail needs a non-zero format and at most \(maxThumbnailBytes) bytes")
                }
            }

            let start = body.count
            var head = [UInt8](repeating: 0, count: 8)
            writeU16LE(&head, 0, UInt16(slot))
            writeU16LE(&head, 2, thumb?.format ?? 0)
            writeU32LE(&head, 4, UInt32(thumb?.data.count ?? 0))
            body.append(contentsOf: head)
            body.append(contentsOf: image.bytes)
            if let thumb = thumb {
                body.append(contentsOf: thumb.data)
            }
            let recordBytes = Array(body[start..<body.count])
            let crc = Crc32.compute(recordBytes)
            appendU32LE(&body, crc)
        }

        body.append(contentsOf: footerMagic)
        let totalLen = UInt32(body.count + 8)
        appendU32LE(&body, totalLen)
        let totalCrc = Crc32.compute(body)
        appendU32LE(&body, totalCrc)

        return body
    }

    /// Writes the store to `path` atomically: the bytes go to a temporary file in the same folder, are
    /// flushed to disk, and replace the old file in one step; the previous generation stays as `path + ".bak"`.
    public static func writeAtomic(path: String, store: SaveStore) throws {
        guard !path.isEmpty else {
            throw TsukiError.io("path cannot be empty")
        }
        let url = URL(fileURLWithPath: path).standardized
        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        let tmpUrl = dir.appendingPathComponent(url.lastPathComponent + ".\(uuid).tmp")
        let bakUrl = dir.appendingPathComponent(url.lastPathComponent + ".bak")

        do {
            let bytes = try toBytes(store)
            let data = Data(bytes)
            try data.write(to: tmpUrl, options: .atomic)

            if fm.fileExists(atPath: url.path) {
                if fm.fileExists(atPath: bakUrl.path) {
                    try? fm.removeItem(at: bakUrl)
                }
                try? fm.copyItem(at: url, to: bakUrl)
                _ = try? fm.replaceItemAt(url, withItemAt: tmpUrl, backupItemName: nil, options: [])
                if fm.fileExists(atPath: tmpUrl.path) {
                    try? fm.removeItem(at: url)
                    try fm.moveItem(at: tmpUrl, to: url)
                }
            } else {
                try fm.moveItem(at: tmpUrl, to: url)
            }
        } catch {
            try? fm.removeItem(at: tmpUrl)
            throw error
        }
    }

    /// SaveImage_Commit: copies G[0..499] of the interpreter's variables into the system data, then writes the file
    /// atomically (`writeAtomic`). Call it after every manual, quick or auto save and when the config closes.
    ///
    /// - Parameters:
    ///   - path: The save file.
    ///   - store: The save state.
    ///   - vars: The interpreter's variables, or nil when G did not change.
    public static func commit(path: String, store: SaveStore, vars: Vars? = nil) throws {
        if let vars = vars {
            store.systemData.captureGlobalsFrom(vars)
        }
        try writeAtomic(path: path, store: store)
    }

    // -- reading -----------------------------------------------------------------------------------------------------

    /// Parses the bytes of a save file.
    ///
    /// - Throws: `TsukiError.format` when the data is not a complete, undamaged save file of a known version.
    public static func fromBytes(_ data: [UInt8]) throws -> SaveStore {
        if data.count > maxFileBytes {
            throw TsukiError.format("the file is larger than any valid save")
        }

        if data.count < headerSize + 4 {
            throw TsukiError.format("the file is too short (\(data.count) bytes)")
        }

        if !data[0..<8].elementsEqual(magic) {
            throw TsukiError.format("not a Tsuki save file (bad magic)")
        }

        if Crc32.compute(Array(data[0..<0x1C])) != readU32LE(data, 0x1C) {
            throw TsukiError.format("the header is damaged (CRC mismatch)")
        }

        let ver = readU32LE(data, 8)
        if ver != UInt32(version) {
            throw TsukiError.format(ver > UInt32(version)
                ? "the save file has version \(ver), newer than this game understands (\(version))"
                : "unknown save file version \(ver)")
        }

        if readU32LE(data, 0x10) != UInt32(SystemBlock.size)
            || readU32LE(data, 0x14) != UInt32(SlotImage.size) {
            throw TsukiError.format("the block sizes in the header do not match this version")
        }

        let records = readU32LE(data, 0x18)
        if records > UInt32(SaveStore.slotCount) {
            throw TsukiError.format("\(records) slot records (at most \(SaveStore.slotCount))")
        }

        let footerSize = 16
        if data.count < headerSize + SystemBlock.size + 4 + footerSize {
            throw TsukiError.format("the file is truncated")
        }

        let footer = Array(data[(data.count - footerSize)...])
        if !footer[0..<8].elementsEqual(footerMagic) {
            throw TsukiError.format("the file is truncated (no end marker)")
        }

        if readU32LE(footer, 8) != UInt32(data.count) {
            throw TsukiError.format("the file length differs from the length it records")
        }

        if Crc32.compute(Array(data[0..<(data.count - 4)])) != readU32LE(footer, 12) {
            throw TsukiError.format("the file is damaged (CRC mismatch)")
        }

        var pos = headerSize
        let systemBytes = Array(data[pos..<(pos + SystemBlock.size)])
        pos += SystemBlock.size
        if Crc32.compute(systemBytes) != readU32LE(data, pos) {
            throw TsukiError.format("the system block is damaged (CRC mismatch)")
        }

        pos += 4
        let system = SystemBlock()
        system.copy(from: ByteSpan(systemBytes))
        try validateSystem(system)
        let store = SaveStore(SystemData(system))

        let end = data.count - footerSize
        var previous = -1
        for r in 0..<records {
            if pos + 8 > end {
                throw TsukiError.format("a slot record is truncated")
            }

            let start = pos
            let index = Int(readU16LE(data, pos))
            let format = readU16LE(data, pos + 2)
            let thumbLength = Int(readU32LE(data, pos + 4))
            pos += 8

            if index >= SaveStore.slotCount || index <= previous {
                throw TsukiError.format("slot record \(r) has the bad or repeated index \(index)")
            }

            previous = index
            if thumbLength > maxThumbnailBytes || (format == 0) != (thumbLength == 0)
                || pos + SlotImage.size + thumbLength + 4 > end {
                throw TsukiError.format("slot \(index): bad thumbnail header or truncated record")
            }

            let slotBytes = Array(data[pos..<(pos + SlotImage.size)])
            pos += SlotImage.size
            let thumbBytes: [UInt8]? = thumbLength == 0 ? nil : Array(data[pos..<(pos + thumbLength)])
            pos += thumbLength

            if Crc32.compute(Array(data[start..<pos])) != readU32LE(data, pos) {
                throw TsukiError.format("slot \(index) is damaged (CRC mismatch)")
            }

            pos += 4
            let image = SlotImage(bytes: slotBytes)
            try validateSlot(index, image)
            store.setSlot(index, image, thumbBytes.map { SlotThumbnail(format: format, data: $0) })
        }

        if pos != end {
            throw TsukiError.format("unexpected bytes after the last slot record")
        }

        return store
    }

    /// Reads a save file; when it is damaged, tries the previous generation (`path + ".bak"`).
    ///
    /// - Parameters:
    ///   - path: The save file.
    ///   - usedBackup: True when the backup was read.
    /// - Returns: The store, or nil when there is no save file at all.
    /// - Throws: `TsukiError.format` when the file (and the backup, if any) is damaged.
    public static func readWithFallback(path: String, usedBackup: inout Bool) throws -> SaveStore? {
        guard !path.isEmpty else {
            throw TsukiError.io("path cannot be empty")
        }
        usedBackup = false
        let backup = path + ".bak"
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try fromBytes([UInt8](data))
        } catch let primary as TsukiError {
            if case .format(let primaryMsg) = primary, fm.fileExists(atPath: backup) {
                do {
                    let backupData = try Data(contentsOf: URL(fileURLWithPath: backup))
                    let store = try fromBytes([UInt8](backupData))
                    usedBackup = true
                    return store
                } catch let backupErr as TsukiError {
                    if case .format(let backupMsg) = backupErr {
                        throw TsukiError.format("\(primaryMsg); the backup: \(backupMsg)")
                    }
                    throw backupErr
                }
            }
            throw primary
        }
    }

    private static func validateSystem(_ system: SystemBlock, checkLatestSlot: Bool = true) throws {
        if system.magic != SystemBlock.magicValue || system.used == 0 {
            throw TsukiError.format("the system block has no magic")
        }

        if checkLatestSlot && Int(system.latestSlot) > SaveStore.autoSaveLast {
            throw TsukiError.format("latest slot \(system.latestSlot) is out of range")
        }
    }

    private static func validateSlot(_ index: Int, _ slot: SlotImage) throws {
        if !slot.isStored {
            throw TsukiError.format("slot \(index) is not a complete save (magic or end marker missing)")
        }

        if slot.hasStateB < 0 || slot.hasStateB > 1 {
            throw TsukiError.format("slot \(index): state-B flag \(slot.hasStateB)")
        }

        if !slot.date.isPlausible {
            throw TsukiError.format("slot \(index): implausible date \(slot.date)")
        }

        if slot.stateA.serial < 0 {
            throw TsukiError.format("slot \(index): state A has a negative serial")
        }
    }

    // -- PS4 images (adv_state.md 7, tools/eboot/savedata.py) ------------------------------------------------------------

    /// Imports a PS4 save image (`savedata000`, 4 MiB: the system block at 0, slot i at `0x1A00 + i * 0x7140`).
    /// Only slots with the magic, a used flag and the end marker are taken. The thumbnails are not part of the image. A latest-slot
    /// word that names no stored slot is recomputed from the dates.
    ///
    /// - Throws: `TsukiError.format` when the image has the wrong size or no system block.
    public static func importPs4Image(_ image: [UInt8]) throws -> SaveStore {
        if image.count != ps4ImageSize {
            throw TsukiError.format("a PS4 save image is 0x\(String(ps4ImageSize, radix: 16)) bytes, got 0x\(String(image.count, radix: 16))")
        }

        let system = SystemBlock()
        system.copy(from: ByteSpan(Array(image[0..<SystemBlock.size])))
        try validateSystem(system, checkLatestSlot: false)
        let store = SaveStore(SystemData(system))
        for i in 0..<SaveStore.slotCount {
            let off = ps4SlotBase + (i * ps4SlotStride)
            let slotBytes = Array(image[off..<(off + SlotImage.size)])
            let slot = SlotImage(bytes: slotBytes)
            if slot.isStored {
                try validateSlot(i, slot)
                store.setSlot(i, slot, nil)
            }
        }

        if Int(system.latestSlot) > SaveStore.autoSaveLast || !store.hasSave(Int(system.latestSlot)) {
            store.updateLatestSlot()
        }

        return store
    }

    /// ByteSpan overload for `importPs4Image`.
    public static func importPs4Image(_ image: ByteSpan) throws -> SaveStore {
        try importPs4Image(Array(image))
    }

    /// The PS4 image of a store (4 MiB; slots that hold no save carry the magic only, as the console writes them).
    public static func exportPs4Image(_ store: SaveStore) -> [UInt8] {
        var image = [UInt8](repeating: 0, count: ps4ImageSize)
        let sysBytes = Array(store.systemData.block.bytes)
        for i in 0..<sysBytes.count {
            image[i] = sysBytes[i]
        }

        for i in 0..<SaveStore.slotCount {
            let off = ps4SlotBase + (i * ps4SlotStride)
            if let slot = store.getSlot(i) {
                let bytes = Array(slot.bytes)
                for j in 0..<bytes.count {
                    image[off + j] = bytes[j]
                }
            } else {
                writeU16LE(&image, off, SlotImage.magic)
            }
        }

        return image
    }

    // -- helpers -------------------------------------------------------------------------------------------------------

    private static func readU16LE(_ data: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readU32LE(_ data: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func writeU16LE(_ data: inout [UInt8], _ offset: Int, _ value: UInt16) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private static func writeU32LE(_ data: inout [UInt8], _ offset: Int, _ value: UInt32) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
        data[offset + 2] = UInt8((value >> 16) & 0xFF)
        data[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private static func appendU32LE(_ data: inout [UInt8], _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    /// CRC-32 (IEEE 802.3, reflected, polynomial 0xEDB88320), the checksum of the file's blocks.
    public enum Crc32 {
        private static let table: [UInt32] = buildTable()

        /// CRC-32 of `data`.
        public static func compute(_ data: [UInt8]) -> UInt32 {
            var crc: UInt32 = 0xFFFFFFFF
            for b in data {
                let idx = Int((crc ^ UInt32(b)) & 0xFF)
                crc = table[idx] ^ (crc >> 8)
            }
            return ~crc
        }

        /// CRC-32 of `span`.
        public static func compute(_ span: ByteSpan) -> UInt32 {
            var crc: UInt32 = 0xFFFFFFFF
            for b in span {
                let idx = Int((crc ^ UInt32(b)) & 0xFF)
                crc = table[idx] ^ (crc >> 8)
            }
            return ~crc
        }

        private static func buildTable() -> [UInt32] {
            var t = [UInt32](repeating: 0, count: 256)
            for i in 0..<256 {
                var c = UInt32(i)
                for _ in 0..<8 {
                    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : (c >> 1)
                }
                t[i] = c
            }
            return t
        }
    }
}
