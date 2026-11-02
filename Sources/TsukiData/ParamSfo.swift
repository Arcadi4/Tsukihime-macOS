import Foundation
import TsukiCore
import TsukiEngine

/// The key / value pairs of a param.sfo, the PS4's `sce_sys/param.sfo`: a header, 16-byte index
/// entries, a key table and a data table. Read-only.
public struct ParamSfo {
    private var values: [String: String]

    /// Every key, in file order.
    public private(set) var keys: [String]

    private init(values: [String: String], keys: [String]) {
        self.values = values
        self.keys = keys
    }

    /// The value of a key such as `TITLE_ID`, `APP_VER`, `VERSION` or `TITLE`; nil when the key is not there.
    public subscript(key: String) -> String? { values[key] }

    /// A param.sfo is a few kilobytes; a file larger than this is not one (the data layer never reads
    /// a whole archive into memory).
    public static let maxFileSize = 1 << 20

    /// Reads a file; nil when it is missing, too large to be a param.sfo, or is not one.
    public static func tryRead(_ path: String) -> ParamSfo? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: path),
              let attributes = try? manager.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= maxFileSize,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return tryParse(ByteSpan([UInt8](data)))
    }

    /// Parses the bytes; nil when the header, an entry or an offset is wrong.
    public static func tryParse(_ data: ByteSpan) -> ParamSfo? {
        guard data.count >= 20, data.u32(0) == 0x46535000 else { return nil }

        let keyTable = Int(data.u32(8))
        let dataTable = Int(data.u32(12))
        let count = Int(data.u32(16))
        guard count <= 512, keyTable <= data.count, dataTable <= data.count, 20 + count * 16 <= data.count else {
            return nil
        }

        var values: [String: String] = [:]
        var keys: [String] = []
        keys.reserveCapacity(count)
        for i in 0..<count {
            let entry = data.slice(20 + i * 16, 16)
            let keyOffset = Int(entry.u16(0))
            let format = entry.u16(2)
            let length = Int(entry.u32(4))
            let dataOffset = Int(entry.u32(12))
            let keyStart = keyTable + keyOffset
            let valueStart = dataTable + dataOffset
            guard keyStart >= 0, keyStart < data.count, valueStart >= 0, length >= 0,
                  valueStart <= data.count, length <= data.count - valueStart else {
                return nil
            }

            let keyBytes = data.suffix(from: keyStart)
            var keyEnd = keyBytes.count
            for j in 0..<keyBytes.count where keyBytes[j] == 0 {
                keyEnd = j
                break
            }
            let key = String(utf8Bytes: keyBytes.slice(0, keyEnd))

            let value = data.slice(valueStart, length)
            let text: String
            if format == 0x0404 && length == 4 {
                text = String(value.u32(0))
            } else {
                var end = value.count
                for j in 0..<value.count where value[j] == 0 {
                    end = j
                    break
                }
                text = String(utf8Bytes: value.slice(0, end))
            }

            if values[key] == nil { keys.append(key) }
            values[key] = text
        }

        return ParamSfo(values: values, keys: keys)
    }

    /// Parses the bytes of a param.sfo.
    /// - Throws: `TsukiError.format` when the header, an entry or an offset is wrong.
    public static func parse(_ data: ByteSpan) throws -> ParamSfo {
        guard let sfo = tryParse(data) else {
            throw TsukiError.format("param.sfo does not follow the PSF layout")
        }
        return sfo
    }
}
