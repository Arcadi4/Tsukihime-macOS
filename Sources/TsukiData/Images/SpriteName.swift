import TsukiCore
import TsukiEngine
import Foundation

/// The parts of a sprite file name `CHR_S_PP_VV_Xnn[_...].MZP` (docs/formats/images.md 7):
/// `ARU_L_81_00_N00_B.MZP` is the body ("base") and `ARU_L_81_00_N00.MZP` or
/// `ARU_L_81_00_A01_00_01.MZP` are face layers on the same tile grid. A port of
/// `tsuki.image.split_sprite_name`.
public struct SpriteName: Equatable, Sendable {
    /// Character code, 3 letters (`ARU`).
    public let char: String

    /// Size class, 1 letter (`A`, `L`, `M`, `S`).
    public let size: String

    /// Pose, two digits.
    public let pose: String

    /// Variant, two digits.
    public let variant: String

    /// Face or expression, 3 characters (`N00`, `A01`).
    public let face: String

    /// The remaining `_xx` parts (`04`, `04`) or `B`.
    public let suffix: [String]

    public init(
        char: String, size: String, pose: String, variant: String, face: String, suffix: [String]
    ) {
        self.char = char
        self.size = size
        self.pose = pose
        self.variant = variant
        self.face = face
        self.suffix = suffix
    }

    /// True for a body layer: the suffix is exactly `B`.
    public var isBase: Bool { suffix.count == 1 && suffix[0] == "B" }

    /// The name shared by a base and its face layers: `CHAR_SIZE_POSE_VAR`.
    public var group: String { "\(char)_\(size)_\(pose)_\(variant)" }

    /// Parses a file name; nil for names that are not sprites (`IMG0001.MZP`, `BLACK.MZP` ...).
    public static func split(_ name: String) -> SpriteName? {
        let stem: String
        if let dot = name.lastIndex(of: ".") {
            stem = String(name[..<dot])
        } else {
            stem = name
        }

        let parts = stem.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5, parts[0].count == 3, parts[1].count == 1, parts[4].count == 3
        else {
            return nil
        }

        return SpriteName(
            char: parts[0], size: parts[1], pose: parts[2], variant: parts[3], face: parts[4],
            suffix: Array(parts[5...]))
    }
}
