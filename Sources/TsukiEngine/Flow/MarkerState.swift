import Foundation
import TsukiCore

/// The common processing of every marker `_Z<k><bbb><ss>` (docs/formats/script.md 3.7, engine.md 5.6): the previous
/// marker's line is recorded in `readmax` when the next marker is reached, then the new block / sub become current
/// and the "already read" test runs for them.
///
/// `readmax` is the system block's table (+0x738, 4,020 bytes; RAM 0x17DA278). The engine bound is a signed upper
/// bound only (`prev_block <= 0xFB3`); this port never writes outside the table (a negative block, possible only with
/// malformed digits, is not recorded) and treats the read test of a block outside 0..0xFB3 as reading 0 (the engine
/// reads the neighbouring memory there). Retail blocks are 0x00A..0xF82.
public final class MarkerState {
    /// Highest block the engine records (`cmp edi, 0xFB3; jg`).
    public static let maxRecordedBlock = 0xFB3

    private let system: SystemBlock

    /// Creates the state over the system block that holds `readmax`.
    public init(_ system: SystemBlock) {
        self.system = system
    }

    /// The previous marker's block id (VA 0x1654344; 0 before the first marker).
    public private(set) var block = 0

    /// The previous marker's sub id (VA 0x1654348).
    public private(set) var sub = 0

    /// True once a marker was reached (word VA 0x1654354 = 1).
    public private(set) var seen = false

    /// The "already read" result of the current marker.
    public private(set) var isRead = false

    /// Sets the current ids without touching `readmax` (restoring a history record or a save) and recomputes the
    /// "already read" result for them: the engine computes it from the current ids each time (0x75C90, adv_state.md 6),
    /// so a line re-displayed by a rewind is read when `readmax` says so, whatever the newest marker was.
    public func restore(_ block: Int, _ sub: Int) {
        self.block = block
        self.sub = sub
        seen = true
        isRead = readNow(block, sub)
    }

    private func readNow(_ block: Int, _ sub: Int) -> Bool {
        let max: Int = block >= 0 && block <= MarkerState.maxRecordedBlock ? Int(system.getReadmax(block)) : 0
        return max != 0 && (sub <= max || block > MarkerState.maxRecordedBlock)
    }

    /// Processes a marker with the decoded `block` and `sub` ids (script.md 3.7, in the engine's order) and returns
    /// its "already read" result.
    @discardableResult
    public func enter(_ block: Int, _ sub: Int) -> Bool {
        if self.block >= 0 && self.block <= MarkerState.maxRecordedBlock && sub > Int(system.getReadmax(self.block)) {
            system.setReadmax(self.block, UInt8(truncatingIfNeeded: sub))
        }

        self.block = block
        self.sub = sub
        seen = true
        isRead = readNow(block, sub)
        return isRead
    }
}
