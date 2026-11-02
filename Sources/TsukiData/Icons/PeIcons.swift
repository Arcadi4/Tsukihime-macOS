import Foundation
import TsukiCore
import TsukiEngine

/// The assembly-level marks of a managed assembly: its `AssemblyMetadata` pairs and its
/// informational version.
public struct AssemblyMarks: Equatable, Sendable {
    /// Every `[assembly: AssemblyMetadata(key, value)]` of the assembly.
    public let metadata: [String: String]

    /// The `AssemblyInformationalVersion`, or nil when the assembly has none.
    public let informationalVersion: String?

    public init(metadata: [String: String], informationalVersion: String?) {
        self.metadata = metadata
        self.informationalVersion = informationalVersion
    }

    /// True when the assembly carries `TsukiPersonalBuild = true`.
    public var isPersonalBuild: Bool {
        guard let value = metadata[PeIcons.personalBuildKey] else { return false }
        return value.lowercased() == "true"
    }
}

/// Reads icon groups and build marks out of executables and assemblies on disk: the icon group the
/// compiler writes for a project's `ApplicationIcon` (RT_GROUP_ICON 32512 and its RT_ICON images,
/// rebuilt into the .ico file they came from so that `FaceIcon.decodeIco` reads it) and the
/// assembly-level attributes that mark a personal build. No Win32 call and no runtime load: the PE
/// headers and the resource tree are walked here, and the attribute blob is decoded from the managed
/// metadata.
public enum PeIcons {
    /// The resource id of the icon group a compiler writes for `ApplicationIcon` (RT_GROUP_ICON
    /// 32512, IDI_APPLICATION).
    public static let applicationIconGroup = 32512

    /// The `AssemblyMetadata` key a personal build carries with the value `true`.
    public static let personalBuildKey = "TsukiPersonalBuild"

    private static let rtIcon = 3
    private static let rtGroupIcon = 14
    private static let subdirectoryBit = 0x8000_0000

    /// The ids of the icon groups of `path`: empty when it has resources but no icon group; nil when
    /// the file is not a PE image.
    public static func iconGroupIds(_ path: String) throws -> [Int]? {
        guard let pe = try readPE(path) else { return nil }
        guard let res = resourceDirectory(pe) else { return [] }
        var ids: [Int] = []
        if let typeDirectory = findResourceEntry(res, in: 0, id: rtGroupIcon) {
            for entry in resourceEntries(res, at: typeDirectory)
            where entry.isDirectory && (entry.id & subdirectoryBit) == 0 {
                ids.append(entry.id)                    // a named group (the bit set) has no id
            }
        }
        return ids
    }

    /// The icon group `groupId` of the executable `path` as the bytes of a .ico file (the directory
    /// of the group with its images appended, the form `FaceIcon.decodeIco` reads); nil when the file
    /// is not a PE image or has no such group.
    public static func iconGroup(_ path: String, groupId: Int = PeIcons.applicationIconGroup) throws -> [UInt8]? {
        guard let pe = try readPE(path), let res = resourceDirectory(pe) else { return nil }
        let group = firstResourceData(pe, res, type: rtGroupIcon, id: groupId)
        guard group.count >= 6 else { return nil }
        let count = Int(group.u16(4))
        guard group.count >= 6 + 14 * count else { return nil }

        // GRPICONDIR entries are 14 bytes (the image id instead of the file offset); the .ico
        // directory entries are 16 (a file offset).
        var writer = ByteWriter(reserving: 6 + 16 * count)
        writer.u16(0)
        writer.u16(1)
        writer.u16(UInt16(count))
        var images: [[UInt8]] = []
        images.reserveCapacity(count)
        var offset = 6 + 16 * count
        for i in 0..<count {
            let entry = group.slice(6 + 14 * i, 14)
            let imageId = Int(entry.u16(12))
            let image = firstResourceData(pe, res, type: rtIcon, id: imageId).toArray()
            images.append(image)
            writer.raw(entry.slice(0, 8).toArray())
            writer.u32(UInt32(image.count))
            writer.u32(UInt32(offset))
            offset += image.count
        }
        for image in images { writer.raw(image) }
        return writer.bytes
    }

    /// The assembly-level marks of the managed assembly `path`; nil when the file is not a PE image
    /// or carries no managed metadata (an apphost).
    public static func marks(_ path: String) throws -> AssemblyMarks? {
        guard let pe = try readPE(path), let metadata = try MetadataImage.parse(pe) else { return nil }
        var values: [String: String] = [:]
        var informational: String?
        for attribute in try metadata.customAttributeRows() {
            guard attribute.parentTable == 0x20 else { continue }   // Assembly
            let type = metadata.attributeTypeName(attribute)
            if type == "System.Reflection.AssemblyMetadataAttribute" {
                guard attribute.value.count >= 2 else {
                    throw TsukiError.format("AssemblyMetadataAttribute value is truncated")
                }
                guard attribute.value.u16(0) == 1 else { continue }
                var cursor = 2
                let key = try serializedString(attribute.value, &cursor) ?? ""
                let value = try serializedString(attribute.value, &cursor) ?? ""
                values[key] = value
            } else if type == "System.Reflection.AssemblyInformationalVersionAttribute" {
                guard attribute.value.count >= 2 else {
                    throw TsukiError.format("AssemblyInformationalVersionAttribute value is truncated")
                }
                guard attribute.value.u16(0) == 1 else { continue }
                var cursor = 2
                informational = try serializedString(attribute.value, &cursor)
            }
        }
        return AssemblyMarks(metadata: values, informationalVersion: informational)
    }

    private static func readPE(_ path: String) throws -> PEImage? {
        let bytes: [UInt8]
        do {
            bytes = try [UInt8](Data(contentsOf: URL(fileURLWithPath: path)))
        } catch {
            throw TsukiError.io("\(path): \(error.localizedDescription)")
        }
        return PEImage.open(bytes)
    }
}

// ---- the PE image ------------------------------------------------------------------------------

private struct PEImage {
    struct Section {
        let virtualAddress: Int
        let virtualSize: Int
        let rawOffset: Int
        let rawSize: Int
    }

    let bytes: [UInt8]
    let sections: [Section]
    let resourceRva: Int
    let resourceSize: Int
    let corRva: Int
    let corSize: Int

    static func open(_ bytes: [UInt8]) -> PEImage? {
        guard bytes.count >= 0x40 else { return nil }
        let peOffset = le32(bytes, 0x3C)
        guard peOffset + 24 <= bytes.count, le32(bytes, peOffset) == 0x0000_4550 else { return nil }

        let coff = peOffset + 4
        let numberOfSections = le16(bytes, coff + 2)
        let sizeOfOptionalHeader = le16(bytes, coff + 16)
        let optional = coff + 20
        guard optional + sizeOfOptionalHeader <= bytes.count else { return nil }

        let directoryTable: Int
        let directoryCountOffset: Int
        switch le16(bytes, optional) {
        case 0x10B:                                         // PE32
            directoryTable = optional + 0x60
            directoryCountOffset = optional + 0x5C
        case 0x20B:                                         // PE32+
            directoryTable = optional + 0x70
            directoryCountOffset = optional + 0x6C
        default:
            return nil
        }

        let optionalEnd = optional + sizeOfOptionalHeader
        let declaredDirectories = directoryCountOffset + 4 <= optionalEnd ? le32(bytes, directoryCountOffset) : 0
        let availableDirectories = max(0, (optionalEnd - directoryTable) / 8)
        let directoryCount = min(declaredDirectories, availableDirectories)
        func directory(_ index: Int) -> (rva: Int, size: Int) {
            guard index < directoryCount else { return (0, 0) }
            let at = directoryTable + 8 * index
            guard at + 8 <= bytes.count else { return (0, 0) }
            return (le32(bytes, at), le32(bytes, at + 4))
        }

        let resource = directory(2)
        let cor = directory(14)

        let sectionTable = optionalEnd
        var sections: [Section] = []
        sections.reserveCapacity(numberOfSections)
        for i in 0..<numberOfSections {
            let at = sectionTable + 40 * i
            guard at + 40 <= bytes.count else { return nil }
            sections.append(Section(virtualAddress: le32(bytes, at + 12),
                                    virtualSize: le32(bytes, at + 8),
                                    rawOffset: le32(bytes, at + 20),
                                    rawSize: le32(bytes, at + 16)))
        }
        return PEImage(bytes: bytes, sections: sections,
                       resourceRva: resource.rva, resourceSize: resource.size,
                       corRva: cor.rva, corSize: cor.size)
    }

    /// The section from `rva` to the end of its section, the offset base of resource-tree entries.
    func sectionData(_ rva: Int) -> (offset: Int, length: Int)? {
        for section in sections {
            let span = max(section.virtualSize, section.rawSize)
            guard rva >= section.virtualAddress, rva < section.virtualAddress + span else { continue }
            let delta = rva - section.virtualAddress
            guard delta < section.rawSize, section.rawOffset + section.rawSize <= bytes.count else { return nil }
            return (section.rawOffset + delta, section.rawSize - delta)
        }
        return nil
    }
}

private func resourceDirectory(_ pe: PEImage) -> ByteSpan? {
    guard pe.resourceSize != 0, let block = pe.sectionData(pe.resourceRva), block.length > 0 else { return nil }
    return ByteSpan(pe.bytes, offset: block.offset, count: block.length)
}

private struct ResourceEntry {
    let id: Int
    let offset: Int
    let isDirectory: Bool
}

/// The entries of the resource directory at `at`: (name or id, offset of the child, whether the
/// child is a directory).
private func resourceEntries(_ res: ByteSpan, at directory: Int) -> [ResourceEntry] {
    guard directory >= 0, directory + 16 <= res.count else { return [] }
    let named = Int(res.u16(directory + 12))
    let ids = Int(res.u16(directory + 14))
    var entries: [ResourceEntry] = []
    entries.reserveCapacity(named + ids)
    for i in 0..<(named + ids) {
        let at = directory + 16 + 8 * i
        guard at + 8 <= res.count else { break }
        let id = Int(res.u32(at))
        let offset = res.u32(at + 4)
        entries.append(ResourceEntry(id: id,
                                     offset: Int(offset & ~UInt32(0x8000_0000)),
                                     isDirectory: (offset & UInt32(0x8000_0000)) != 0))
    }
    return entries
}

private func findResourceEntry(_ res: ByteSpan, in directory: Int, id: Int) -> Int? {
    for entry in resourceEntries(res, at: directory) where entry.isDirectory && entry.id == id {
        return entry.offset
    }
    return nil
}

/// The data of the first language of resource `id` of `type`; empty when it is not there.
private func firstResourceData(_ pe: PEImage, _ res: ByteSpan, type: Int, id: Int) -> ByteSpan {
    guard let typeDirectory = findResourceEntry(res, in: 0, id: type),
          let nameDirectory = findResourceEntry(res, in: typeDirectory, id: id) else { return ByteSpan() }
    for entry in resourceEntries(res, at: nameDirectory) {
        guard !entry.isDirectory, entry.offset + 8 <= res.count else { continue }
        let rva = res.i32(entry.offset)
        let size = res.i32(entry.offset + 4)
        guard rva > 0, size > 0 else { continue }
        guard let block = pe.sectionData(Int(rva)), block.length >= Int(size) else { continue }
        return ByteSpan(pe.bytes, offset: block.offset, count: Int(size))
    }
    return ByteSpan()
}

// ---- the managed metadata ----------------------------------------------------------------------

private struct CustomAttributeRow {
    let parentTable: Int
    let parentRow: Int
    let constructorTable: Int
    let constructorRow: Int
    let value: ByteSpan
}

/// The parts of a managed metadata image this reader needs: the string and blob heaps, the table
/// stream, and the row geometry of every table (ECMA-335 II.24).
private struct MetadataImage {
    let bytes: [UInt8]
    let stringsOffset: Int
    let stringsSize: Int
    let blobsOffset: Int
    let blobsSize: Int
    let rowCounts: [Int]
    let rowStarts: [Int]
    let rowSizes: [Int]
    let columnOffsets: [[Int]]
    let stringIndexSize: Int
    let blobIndexSize: Int
    let codedSizes: [Int]

    /// Parses the metadata of `pe`; nil when the image carries no CLR header or no metadata.
    static func parse(_ pe: PEImage) throws -> MetadataImage? {
        guard pe.corRva != 0, pe.corSize != 0,
              let cor = pe.sectionData(pe.corRva), cor.length >= 16 else { return nil }
        let metadataRva = leI32(pe.bytes, cor.offset + 8)
        let metadataSize = leI32(pe.bytes, cor.offset + 12)
        guard metadataRva > 0, metadataSize > 0 else { return nil }
        guard let block = pe.sectionData(metadataRva) else {
            throw TsukiError.format("managed metadata directory is outside the image sections")
        }

        let root = block.offset
        let limit = min(root + metadataSize, root + block.length)
        guard root + 20 <= limit else { throw TsukiError.format("managed metadata root is truncated") }
        guard le32(pe.bytes, root) == 0x424A_5342 else {
            throw TsukiError.format("bad managed metadata signature")
        }

        let versionLength = le32(pe.bytes, root + 12)
        var cursor = root + 16 + versionLength
        guard cursor + 4 <= limit else { throw TsukiError.format("managed metadata version is truncated") }
        let streamCount = le16(pe.bytes, cursor + 2)
        cursor += 4

        var streams: [String: (offset: Int, size: Int)] = [:]
        for _ in 0..<streamCount {
            guard cursor + 8 <= limit else { throw TsukiError.format("metadata stream header is truncated") }
            let offset = le32(pe.bytes, cursor)
            let size = le32(pe.bytes, cursor + 4)
            let nameStart = cursor + 8
            var end = nameStart
            while end < limit && pe.bytes[end] != 0 { end += 1 }
            guard end < limit else { throw TsukiError.format("metadata stream name is not terminated") }
            let name = String(decoding: pe.bytes[nameStart..<end], as: UTF8.self)
            var next = end + 1
            while (next - nameStart) % 4 != 0 { next += 1 }
            guard next <= limit else { throw TsukiError.format("metadata stream name is truncated") }
            streams[name] = (root + offset, size)
            cursor = next
        }

        guard let strings = streams["#Strings"], let blobs = streams["#Blob"] else {
            throw TsukiError.format("managed metadata has no #Strings or #Blob stream")
        }
        guard let tableStream = streams["#~"] ?? streams["#-"] else {
            throw TsukiError.format("managed metadata has no table stream")
        }

        // the table stream header: reserved, version, heap sizes, valid and sorted masks, row counts
        let start = tableStream.offset
        let tableLimit = min(tableStream.offset + tableStream.size, limit)
        guard start + 24 <= tableLimit else { throw TsukiError.format("metadata table stream is truncated") }
        let heapSizes = pe.bytes[start + 6]
        let valid = le64(pe.bytes, start + 8)
        var rowCounts = [Int](repeating: 0, count: 64)
        var p = start + 24                             // reserved, version, heap sizes, valid, sorted
        for table in 0..<64 where (valid >> UInt64(table)) & 1 != 0 {
            guard p + 4 <= tableLimit else { throw TsukiError.format("metadata row counts are truncated") }
            rowCounts[table] = le32(pe.bytes, p)
            p += 4
        }

        let stringIndexSize = (heapSizes & 1) != 0 ? 4 : 2
        let blobIndexSize = (heapSizes & 4) != 0 ? 4 : 2
        let guidIndexSize = (heapSizes & 2) != 0 ? 4 : 2

        var codedSizes = [Int](repeating: 2, count: codedDefinitions.count)
        for id in 0..<codedDefinitions.count {
            let definition = codedDefinitions[id]
            var maxRows = 0
            for table in definition.tables where table >= 0 {
                maxRows = max(maxRows, rowCounts[table])
            }
            codedSizes[id] = maxRows < (1 << (16 - definition.bits)) ? 2 : 4
        }

        var rowSizes = [Int](repeating: 0, count: 64)
        var columnOffsets = [[Int]](repeating: [], count: 64)
        for table in 0..<64 where (valid >> UInt64(table)) & 1 != 0 {
            guard table < tableSchemas.count else {
                throw TsukiError.format("unknown metadata table 0x\(String(table, radix: 16))")
            }
            var offsets: [Int] = []
            var size = 0
            for column in tableSchemas[table] {
                offsets.append(size)
                switch column {
                case .u8: size += 1
                case .u16: size += 2
                case .u32: size += 4
                case .string: size += stringIndexSize
                case .guid: size += guidIndexSize
                case .blob: size += blobIndexSize
                case let .table(target): size += rowCounts[target] < 0x10000 ? 2 : 4
                case let .coded(id): size += codedSizes[id]
                }
            }
            rowSizes[table] = size
            columnOffsets[table] = offsets
        }

        var rowStarts = [Int](repeating: 0, count: 64)
        var tableCursor = p
        for table in 0..<64 where (valid >> UInt64(table)) & 1 != 0 {
            rowStarts[table] = tableCursor
            let bytesNeeded = rowSizes[table] * rowCounts[table]
            guard tableCursor + bytesNeeded <= tableLimit else {
                throw TsukiError.format("metadata table 0x\(String(table, radix: 16)) exceeds its stream")
            }
            tableCursor += bytesNeeded
        }

        let stringsEnd = min(strings.offset + strings.size, pe.bytes.count)
        let blobsEnd = min(blobs.offset + blobs.size, pe.bytes.count)
        return MetadataImage(bytes: pe.bytes,
                             stringsOffset: strings.offset,
                             stringsSize: max(0, stringsEnd - strings.offset),
                             blobsOffset: blobs.offset,
                             blobsSize: max(0, blobsEnd - blobs.offset),
                             rowCounts: rowCounts,
                             rowStarts: rowStarts,
                             rowSizes: rowSizes,
                             columnOffsets: columnOffsets,
                             stringIndexSize: stringIndexSize,
                             blobIndexSize: blobIndexSize,
                             codedSizes: codedSizes)
    }

    func rowStart(_ table: Int, _ row: Int) -> Int {
        rowStarts[table] + (row - 1) * rowSizes[table]
    }

    func readIndex(at offset: Int, size: Int) -> Int {
        guard offset >= 0, offset + size <= bytes.count else { return 0 }
        return size == 4 ? le32(bytes, offset) : le16(bytes, offset)
    }

    func tableIndexSize(_ table: Int) -> Int {
        rowCounts[table] < 0x10000 ? 2 : 4
    }

    func tableReference(_ table: Int, _ row: Int, _ column: Int, target: Int) -> Int {
        readIndex(at: rowStart(table, row) + columnOffsets[table][column], size: tableIndexSize(target))
    }

    func coded(_ table: Int, _ row: Int, _ column: Int, _ codedIndex: Int) -> (table: Int, row: Int) {
        let definition = codedDefinitions[codedIndex]
        let value = readIndex(at: rowStart(table, row) + columnOffsets[table][column],
                               size: codedSizes[codedIndex])
        let tag = value & ((1 << definition.bits) - 1)
        let index = value >> definition.bits
        guard tag < definition.tables.count else { return (-1, index) }
        let target = definition.tables[tag]
        guard target >= 0, index >= 1, index <= rowCounts[target] else { return (-1, index) }
        return (target, index)
    }

    func string(_ index: Int) -> String {
        guard index > 0 else { return "" }
        let start = stringsOffset + index
        let end = stringsOffset + stringsSize
        guard start < end else { return "" }
        var stop = start
        while stop < end && bytes[stop] != 0 { stop += 1 }
        return String(decoding: bytes[start..<stop], as: UTF8.self)
    }

    func stringReference(_ table: Int, _ row: Int, _ column: Int) -> String {
        string(readIndex(at: rowStart(table, row) + columnOffsets[table][column], size: stringIndexSize))
    }

    func blob(_ index: Int) throws -> ByteSpan {
        guard index > 0 else { return ByteSpan() }
        let start = blobsOffset + index
        let end = blobsOffset + blobsSize
        guard start < end else { return ByteSpan() }
        let (length, size) = try compressedUInt(at: start, limit: end)
        let content = start + size
        guard content + length <= end else {
            throw TsukiError.format("metadata blob \(index) exceeds the #Blob heap")
        }
        return ByteSpan(bytes, offset: content, count: length)
    }

    private func compressedUInt(at offset: Int, limit: Int) throws -> (value: Int, size: Int) {
        guard offset < limit else { throw TsukiError.format("metadata blob has no length") }
        let first = Int(bytes[offset])
        if first & 0x80 == 0 { return (first, 1) }
        if first & 0xC0 == 0x80 {
            guard offset + 2 <= limit else { throw TsukiError.format("metadata blob length is truncated") }
            return ((first & 0x3F) << 8 | Int(bytes[offset + 1]), 2)
        }
        if first & 0xE0 == 0xC0 {
            guard offset + 4 <= limit else { throw TsukiError.format("metadata blob length is truncated") }
            return ((first & 0x1F) << 24 | Int(bytes[offset + 1]) << 16
                        | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3]), 4)
        }
        throw TsukiError.format("invalid compressed integer 0x\(String(first, radix: 16)) in the #Blob heap")
    }

    func customAttributeRows() throws -> [CustomAttributeRow] {
        let count = rowCounts[0x0C]
        guard count > 0 else { return [] }
        var rows: [CustomAttributeRow] = []
        rows.reserveCapacity(count)
        for row in 1...count {
            let parent = coded(0x0C, row, 0, CodedIndex.hasCustomAttribute)
            let constructor = coded(0x0C, row, 1, CodedIndex.customAttributeType)
            let value = try blob(readIndex(at: rowStart(0x0C, row) + columnOffsets[0x0C][2],
                                           size: blobIndexSize))
            rows.append(CustomAttributeRow(parentTable: parent.table, parentRow: parent.row,
                                           constructorTable: constructor.table,
                                           constructorRow: constructor.row,
                                           value: value))
        }
        return rows
    }

    func attributeTypeName(_ attribute: CustomAttributeRow) -> String {
        switch attribute.constructorTable {
        case 0x0A:                                          // MemberRef
            let parent = coded(0x0A, attribute.constructorRow, 0, CodedIndex.memberRefParent)
            guard parent.table == 0x01 else { return "" }
            return qualifiedName(table: 0x01, row: parent.row)
        case 0x06:                                          // MethodDef
            let type = declaringType(ofMethod: attribute.constructorRow)
            guard type > 0 else { return "" }
            return qualifiedName(table: 0x02, row: type)
        default:
            return ""
        }
    }

    /// `namespace.name` of a TypeRef (0x01) or TypeDef (0x02) row.
    private func qualifiedName(table: Int, row: Int) -> String {
        let name = stringReference(table, row, 1)
        let namespace = stringReference(table, row, 2)
        return namespace + "." + name
    }

    /// The TypeDef row whose method range holds `method`; 0 when none does.
    private func declaringType(ofMethod method: Int) -> Int {
        let count = rowCounts[0x02]
        guard count > 0 else { return 0 }
        var found = 0
        for type in 1...count {
            let first = tableReference(0x02, type, 5, target: 0x06)
            if first <= method {
                found = type
            } else {
                break                                       // MethodList is sorted
            }
        }
        return found
    }
}

// ---- metadata table schemas (ECMA-335 II.22) ---------------------------------------------------

private enum MetadataColumn {
    case u8, u16, u32
    case string, guid, blob
    case table(Int)
    case coded(Int)
}

private struct CodedIndexDefinition {
    let tables: [Int]
    let bits: Int
}

private enum CodedIndex {
    static let typeDefOrRef = 0
    static let hasConstant = 1
    static let hasCustomAttribute = 2
    static let hasFieldMarshal = 3
    static let hasDeclSecurity = 4
    static let memberRefParent = 5
    static let hasSemantics = 6
    static let methodDefOrRef = 7
    static let memberForwarded = 8
    static let implementation = 9
    static let customAttributeType = 10
    static let resolutionScope = 11
    static let typeOrMethodDef = 12
}

/// Tag order is the ECMA-335 order; -1 marks a tag value no metadata may use.
private let codedDefinitions: [CodedIndexDefinition] = [
    CodedIndexDefinition(tables: [0x02, 0x01, 0x1B, -1], bits: 2),                    // TypeDefOrRef
    CodedIndexDefinition(tables: [0x04, 0x08, 0x17, -1], bits: 2),                    // HasConstant
    CodedIndexDefinition(tables: [0x06, 0x04, 0x01, 0x02, 0x08, 0x09, 0x0A, 0x00,
                                  0x0E, 0x17, 0x14, 0x11, 0x1A, 0x1B, 0x20, 0x23,
                                  0x26, 0x27, 0x28, 0x2A, 0x2C, 0x2B,
                                  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1], bits: 5),  // HasCustomAttribute
    CodedIndexDefinition(tables: [0x04, 0x08], bits: 1),                              // HasFieldMarshal
    CodedIndexDefinition(tables: [0x02, 0x06, 0x20, -1], bits: 2),                    // HasDeclSecurity
    CodedIndexDefinition(tables: [0x02, 0x01, 0x1A, 0x06, 0x1B, -1, -1, -1], bits: 3),  // MemberRefParent
    CodedIndexDefinition(tables: [0x14, 0x17], bits: 1),                              // HasSemantics
    CodedIndexDefinition(tables: [0x06, 0x0A], bits: 1),                              // MethodDefOrRef
    CodedIndexDefinition(tables: [0x04, 0x06], bits: 1),                              // MemberForwarded
    CodedIndexDefinition(tables: [0x26, 0x23, 0x27, -1], bits: 2),                    // Implementation
    CodedIndexDefinition(tables: [-1, -1, 0x06, 0x0A, -1, -1, -1, -1], bits: 3),      // CustomAttributeType
    CodedIndexDefinition(tables: [0x00, 0x1A, 0x23, 0x01], bits: 2),                  // ResolutionScope
    CodedIndexDefinition(tables: [0x02, 0x06], bits: 1),                              // TypeOrMethodDef
]

private let tableSchemas: [[MetadataColumn]] = [
    /* 0x00 Module */                 [.u16, .string, .guid, .guid, .guid],
    /* 0x01 TypeRef */                [.coded(CodedIndex.resolutionScope), .string, .string],
    /* 0x02 TypeDef */                [.u32, .string, .string, .coded(CodedIndex.typeDefOrRef), .table(0x04), .table(0x06)],
    /* 0x03 FieldPtr */               [.table(0x04)],
    /* 0x04 Field */                  [.u16, .string, .blob],
    /* 0x05 MethodPtr */              [.table(0x06)],
    /* 0x06 MethodDef */              [.u32, .u16, .u16, .string, .blob, .table(0x08)],
    /* 0x07 ParamPtr */               [.table(0x08)],
    /* 0x08 Param */                  [.u16, .u16, .string],
    /* 0x09 InterfaceImpl */          [.table(0x02), .coded(CodedIndex.typeDefOrRef)],
    /* 0x0A MemberRef */              [.coded(CodedIndex.memberRefParent), .string, .blob],
    /* 0x0B Constant */               [.u8, .u8, .coded(CodedIndex.hasConstant), .blob],
    /* 0x0C CustomAttribute */        [.coded(CodedIndex.hasCustomAttribute), .coded(CodedIndex.customAttributeType), .blob],
    /* 0x0D FieldMarshal */           [.coded(CodedIndex.hasFieldMarshal), .blob],
    /* 0x0E DeclSecurity */           [.u16, .coded(CodedIndex.hasDeclSecurity), .blob],
    /* 0x0F ClassLayout */            [.u16, .u32, .table(0x02)],
    /* 0x10 FieldLayout */            [.u32, .table(0x04)],
    /* 0x11 StandAloneSig */          [.blob],
    /* 0x12 EventMap */               [.table(0x02), .table(0x14)],
    /* 0x13 EventPtr */               [.table(0x14)],
    /* 0x14 Event */                  [.u16, .string, .coded(CodedIndex.typeDefOrRef)],
    /* 0x15 PropertyMap */            [.table(0x02), .table(0x17)],
    /* 0x16 PropertyPtr */            [.table(0x17)],
    /* 0x17 Property */               [.u16, .string, .blob],
    /* 0x18 MethodSemantics */        [.u16, .table(0x06), .coded(CodedIndex.hasSemantics)],
    /* 0x19 MethodImpl */             [.table(0x02), .coded(CodedIndex.methodDefOrRef), .coded(CodedIndex.methodDefOrRef)],
    /* 0x1A ModuleRef */              [.string],
    /* 0x1B TypeSpec */               [.blob],
    /* 0x1C ImplMap */                [.u16, .coded(CodedIndex.memberForwarded), .string, .table(0x1A)],
    /* 0x1D FieldRVA */               [.u32, .table(0x04)],
    /* 0x1E EncLog */                 [.u32, .u32],
    /* 0x1F EncMap */                 [.u32],
    /* 0x20 Assembly */               [.u32, .u16, .u16, .u16, .u16, .u32, .blob, .string, .string],
    /* 0x21 AssemblyProcessor */      [.u32],
    /* 0x22 AssemblyOS */             [.u32, .u32, .u32],
    /* 0x23 AssemblyRef */            [.u16, .u16, .u16, .u16, .u32, .blob, .string, .string, .blob],
    /* 0x24 AssemblyRefProcessor */   [.u32, .table(0x23)],
    /* 0x25 AssemblyRefOS */          [.u32, .u32, .u32, .table(0x23)],
    /* 0x26 File */                   [.u32, .string, .blob],
    /* 0x27 ExportedType */           [.u32, .u32, .string, .string, .coded(CodedIndex.implementation)],
    /* 0x28 ManifestResource */       [.u32, .u32, .string, .coded(CodedIndex.implementation)],
    /* 0x29 NestedClass */            [.table(0x02), .table(0x02)],
    /* 0x2A GenericParam */           [.u16, .u16, .coded(CodedIndex.typeOrMethodDef), .string],
    /* 0x2B MethodSpec */             [.coded(CodedIndex.methodDefOrRef), .blob],
    /* 0x2C GenericParamConstraint */ [.table(0x2A), .coded(CodedIndex.typeDefOrRef)],
]

// ---- byte helpers ------------------------------------------------------------------------------

private func le16(_ bytes: [UInt8], _ offset: Int) -> Int {
    Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
}

private func le32(_ bytes: [UInt8], _ offset: Int) -> Int {
    Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
}

private func leI32(_ bytes: [UInt8], _ offset: Int) -> Int {
    Int(Int32(bitPattern: UInt32(truncatingIfNeeded: le32(bytes, offset))))
}

private func le64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for i in 0..<8 { value |= UInt64(bytes[offset + i]) << (8 * UInt64(i)) }
    return value
}

/// A SerString of a custom attribute value: 0xFF is nil, else a compressed length and UTF-8 text.
private func serializedString(_ blob: ByteSpan, _ cursor: inout Int) throws -> String? {
    guard cursor < blob.count else { throw TsukiError.format("custom attribute value is truncated") }
    let first = Int(blob[cursor])
    if first == 0xFF {
        cursor += 1
        return nil
    }
    let length: Int
    let size: Int
    if first & 0x80 == 0 {
        length = first
        size = 1
    } else if first & 0xC0 == 0x80 {
        guard cursor + 2 <= blob.count else { throw TsukiError.format("custom attribute string is truncated") }
        length = (first & 0x3F) << 8 | Int(blob[cursor + 1])
        size = 2
    } else if first & 0xE0 == 0xC0 {
        guard cursor + 4 <= blob.count else { throw TsukiError.format("custom attribute string is truncated") }
        length = (first & 0x1F) << 24 | Int(blob[cursor + 1]) << 16
            | Int(blob[cursor + 2]) << 8 | Int(blob[cursor + 3])
        size = 4
    } else {
        throw TsukiError.format("invalid custom attribute string length 0x\(String(first, radix: 16))")
    }
    let start = cursor + size
    guard start + length <= blob.count else { throw TsukiError.format("custom attribute string is truncated") }
    cursor = start + length
    return String(decoding: blob.slice(start, length), as: UTF8.self)
}
