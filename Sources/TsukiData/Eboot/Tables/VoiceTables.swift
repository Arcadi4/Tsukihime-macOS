import TsukiCore
import TsukiEngine
import Foundation

/// The voice speaker tables (knife `game.rs` `VOICE_SPEAKERS`, `SPEAKER_ROW_BIT`,
/// `VOICE_ROW_WORDS`). A voice file name starts with a three-letter prefix (`A00_0001`); the speaker
/// number picks the character's config voice row.
public struct VoiceSpeakerTable: Sendable {
    /// Text VA of the speaker records: 36 x 16 bytes {char key[8]; i32 speaker; i32 0}, the key
    /// reversed (`00A` for `A00`).
    public static let va: Int = 0x215E90
    /// Number of speaker records.
    public static let recordCount: Int = 36
    /// Data VA of `i32[24]`: speaker to config voice row bit (row = log2).
    public static let rowBitVa: Int = 0x86A850
    /// Number of speakers.
    public static let speakerCount: Int = 24
    /// Text VA of `i32[19]`: config voice row to its progress F word.
    public static let rowWordVa: Int = 0x1A6850
    /// Number of config voice rows.
    public static let rowCount: Int = 19

    /// The voice file name prefixes (file-name order, upper case) with their speaker; unlisted
    /// prefixes are speaker 0.
    public let prefixes: [String: Int]
    /// Speaker to config voice row bit, 24 entries.
    public let rowBits: [Int]
    /// Config voice row to progress word, 19 entries.
    public let rowWords: [Int]

    public init(prefixes: [String: Int], rowBits: [Int], rowWords: [Int]) {
        self.prefixes = prefixes
        self.rowBits = rowBits
        self.rowWords = rowWords
    }

    /// Reads the three tables.
    public static func read(_ reader: EbootReader) throws -> VoiceSpeakerTable {
        var prefixes: [String: Int] = [:]
        let records = reader.layout.voiceSpeakerRecords
        prefixes.reserveCapacity(records)
        for k in 0..<records {
            let record = try reader.read(reader.layout.voiceSpeakers + 16 * k, 16)
            var end = 8
            for i in 0..<8 where record[i] == 0 {
                end = i
                break
            }

            // The stored key is the file name's prefix backwards, in ASCII.
            var key: [UInt8] = []
            key.reserveCapacity(end)
            var i = end - 1
            while i >= 0 {
                key.append(record[i] < 0x80 ? record[i] : 0x3F)
                i -= 1
            }
            prefixes[String(decoding: key, as: UTF8.self)] = Int(record.i32(8))
        }

        return VoiceSpeakerTable(
            prefixes: prefixes,
            rowBits: try readInts(reader, reader.layout.voiceRowBits, speakerCount),
            rowWords: try readInts(reader, reader.layout.voiceRowWords, rowCount))
    }

    /// The speaker of a voice file name (first three letters, case-insensitive); 0 when unlisted.
    public func speaker(of voiceName: String) -> Int {
        guard voiceName.count >= 3 else { return 0 }
        return prefixes[String(voiceName.prefix(3)).uppercased()] ?? 0
    }

    /// Reads `count` little-endian `i32` values at a VA.
    static func readInts(_ reader: EbootReader, _ va: Int, _ count: Int) throws -> [Int] {
        let raw = try reader.read(va, 4 * count)
        var values = [Int](repeating: 0, count: count)
        for k in 0..<count {
            values[k] = Int(raw.i32(4 * k))
        }
        return values
    }
}
