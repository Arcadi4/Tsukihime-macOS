import Foundation

/// The colour grade a layer's picture is built with (STEC mode, SNX2 brightness, SNX3 contrast and
/// the colour of mode 1; docs/formats/compositing.md 9): the CPU recolour 0xD36F0 runs over the
/// decoded pixels when the texture is built.
public struct ColourGrade: Hashable, Sendable {
    /// The STEC id 1..81 (0 = no recolour).
    public var mode: Int
    /// SNX2 value (i16).
    public var brightness: Int
    /// SNX3 value (i8).
    public var contrast: Int
    /// 0xRRGGBB, used by mode 1 (the solid fill) only; 0 for every other mode.
    public var rgb: Int

    public init(mode: Int = 0, brightness: Int = 0, contrast: Int = 0, rgb: Int = 0) {
        self.mode = mode
        self.brightness = brightness
        self.contrast = contrast
        self.rgb = rgb
    }

    /// True when the grade changes nothing.
    public var isNone: Bool { mode == 0 && brightness == 0 && contrast == 0 }

    /// Builds the grade from a record's fields. Modes outside 1..81 do not recolour; a mode other
    /// than 1 ignores the colour. The global colour mode word (scene +2: 2 = grey, 3 = sepia)
    /// overrides the mode (0x4BB50).
    public static func from(_ mode: Int, brightness: Int, contrast: Int, rgb: Int, globalColourMode: Int = 0) -> ColourGrade {
        var mode = mode
        if globalColourMode == 2 || globalColourMode == 3 {
            mode = globalColourMode
        }
        if mode < 1 || mode > 81 {
            mode = 0
        }
        return ColourGrade(mode: mode, brightness: brightness, contrast: contrast, rgb: mode == 1 ? rgb & 0xFF_FFFF : 0)
    }
}

/// The table that gives a `ColourGrade` an integer key for `TextureRef.d` (the colour-effect key of
/// a picture tile). Key 0 is "no grade". The table only grows, is process-wide and thread-safe.
public enum GradeKeys {
    private static let gate = NSLock()
    nonisolated(unsafe) private static var grades: [ColourGrade] = []
    nonisolated(unsafe) private static var keys: [ColourGrade: Int] = [:]

    /// The key of `grade` (0 for a grade that changes nothing).
    public static func intern(_ grade: ColourGrade) -> Int {
        if grade.isNone { return 0 }
        gate.lock()
        defer { gate.unlock() }
        if let key = keys[grade] { return key }
        grades.append(grade)
        let key = grades.count
        keys[grade] = key
        return key
    }

    /// The grade of a key; the default (none) for key 0.
    public static func resolve(_ key: Int) -> ColourGrade {
        if key == 0 { return ColourGrade() }
        gate.lock()
        defer { gate.unlock() }
        precondition(key > 0 && key <= grades.count, "no such colour-grade key")
        return grades[key - 1]
    }
}
