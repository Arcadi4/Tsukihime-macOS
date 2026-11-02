/// The STRA haze parameter table of the eboot (text VA 0x219910: 558 entries of 10 float32, ids
/// 1..557; the data layer implements it over its haze table).
public protocol HazeTable: AnyObject {
    /// The ten parameters of a STRA id, or nil for an id outside the table.
    func tryGetEntry(_ straId: Int) -> [Float]?
}

/// The STRA haze of one layer as the renderer needs it: the table entry and the phase / fade
/// counters of the drawn record (docs/formats/layers.md 4.2, 6). The meaning of the ten floats is
/// knife's `Haze::params` (hypothesis for the PS4); the stage only keeps the counters.
public struct HazeState: Sendable {
    /// The STRA id of the layer (+0x2C8).
    public let id: Int
    /// The table entry of the id.
    public let entry: [Float]
    /// Frames since the effect started, modulo 6000 (+0x2CA).
    public let phase: Int
    /// Fade-in length in frames, 0 once reached (+0x2CC).
    public let fadeIn: Int
    /// Fade-out length in frames, 0 when none runs (+0x2CE).
    public let fadeTotal: Int
    /// Fade-out frames left (+0x2D0).
    public let fadeLeft: Int

    public init(id: Int, entry: [Float], phase: Int, fadeIn: Int, fadeTotal: Int, fadeLeft: Int) {
        self.id = id
        self.entry = entry
        self.phase = phase
        self.fadeIn = fadeIn
        self.fadeTotal = fadeTotal
        self.fadeLeft = fadeLeft
    }
}
