import Foundation
import TsukiCore

/// The state that outlives a playthrough: the system block (config, read tracking, picture and music unlocks, choices taken, the first 500 G
/// words) and the variable block whose G words (G0..G1999) the story reads and writes. A new game clears the F and Z words and keeps both
/// (adv_state.md 7.5, gallery.md 2; vm_variables.md). Save and load (package K4) read and write these blocks; the interpreter only mutates them.
public final class GameProfile {
    /// The system block.
    public let system: SystemBlock

    /// The F / Z / G words.
    public let vars: Vars

    /// Creates a profile around existing blocks.
    public init(system: SystemBlock, vars: Vars) {
        self.system = system
        self.vars = vars
    }

    /// A fresh profile: the boot config (language set), zero unlocks, zero variables (the first start of the game).
    public static func createNew(_ language: Language) -> GameProfile {
        let system = SystemBlock()
        system.magic = SystemBlock.magicValue
        system.config.copy(from: ConfigBlock.createBootDefaults())
        system.config.language = Int16(language.rawValue)
        return GameProfile(system: system, vars: Vars())
    }

    /// Clears the F and Z words (a new game); the G words stay.
    public func clearPlaythrough() {
        let count = 2 * Vars.gWord
        for i in 0..<count {
            vars.storage.bytes[vars.offset + i] = 0
        }
    }

    /// Copies G0..G499 of the variable block into the system block (what a system save stores).
    public func syncToSystem() {
        for i in 0..<SystemBlock.gCount {
            system.setG(i, vars.getG(i))
        }
    }

    /// Copies G0..G499 of the system block into the variable block (what loading the system data does, gallery.md 2.1).
    public func syncFromSystem() {
        for i in 0..<SystemBlock.gCount {
            vars.setG(i, system.getG(i))
        }
    }
}
