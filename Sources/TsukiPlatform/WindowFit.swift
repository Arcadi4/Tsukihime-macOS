import Foundation

/// Window sizes: presets, the clamp to a monitor's work area, the default.
public enum WindowFit {
    /// The windowed size of a profile that has none: 1600 x 900, or the largest 16:9 size that fits a smaller monitor.
    public static let defaultWidth: Int = 1600

    /// The height that goes with defaultWidth.
    public static let defaultHeight: Int = 900

    /// The smallest width the window accepts.
    public static let minWidth: Int = 640

    /// The smallest height the window accepts.
    public static let minHeight: Int = 360

    /// The largest share of the work area's width and of its height a window may take (90 %).
    public static let share: Double = 0.9

    /// The window size presets, smallest first.
    public static let presets: [(width: Int, height: Int)] = [
        (1280, 720),
        (1600, 900),
        (1920, 1080),
        (2560, 1440),
    ]

    /// The largest width a window may have in a work area workWidth wide.
    public static func maxWidth(workWidth: Int) -> Int {
        max(2, Int(floor(Double(workWidth) * share)))
    }

    /// The largest height a window may have in a work area workHeight tall.
    public static func maxHeight(workHeight: Int) -> Int {
        max(2, Int(floor(Double(workHeight) * share)))
    }

    /// True when a width x height window stays inside the share of the work area.
    public static func fits(width: Int, height: Int, workWidth: Int, workHeight: Int) -> Bool {
        width <= maxWidth(workWidth: workWidth) && height <= maxHeight(workHeight: workHeight)
    }

    /// The largest 16:9 size that fits the work area (even width, so the height is whole).
    public static func largest(workWidth: Int, workHeight: Int) -> (width: Int, height: Int) {
        var w = min(maxWidth(workWidth: workWidth), Int(floor(Double(maxHeight(workHeight: workHeight)) * 16.0 / 9.0))) & ~1
        w = max(2, w)
        let h = max(1, Int(round(Double(w) * 9.0 / 16.0)))
        return (w, h)
    }

    /// A requested size made to fit: unchanged when it fits, else scaled down until both sides are inside the share of the work area.
    public static func clamp(width: Int, height: Int, workWidth: Int, workHeight: Int) -> (width: Int, height: Int) {
        let wIn = max(1, width)
        let hIn = max(1, height)
        if fits(width: wIn, height: hIn, workWidth: workWidth, workHeight: workHeight) {
            return (wIn, hIn)
        }

        let scale = min(Double(maxWidth(workWidth: workWidth)) / Double(wIn), Double(maxHeight(workHeight: workHeight)) / Double(hIn))
        let w = max(2, Int(floor(Double(wIn) * scale)) & ~1)
        let h = max(1, Int(round(Double(w) * Double(hIn) / Double(wIn))))
        return (w, h)
    }

    /// The windowed size for a profile that has none.
    public static func defaultSize(workWidth: Int, workHeight: Int) -> (width: Int, height: Int) {
        fits(width: defaultWidth, height: defaultHeight, workWidth: workWidth, workHeight: workHeight)
            ? (defaultWidth, defaultHeight)
            : largest(workWidth: workWidth, workHeight: workHeight)
    }

    /// The presets that fit the work area, smallest first.
    public static func presetsFor(workWidth: Int, workHeight: Int) -> [(width: Int, height: Int)] {
        presets.filter { fits(width: $0.width, height: $0.height, workWidth: workWidth, workHeight: workHeight) }
    }

    /// The top-left corner of a width x height client area centred in the work area.
    public static func centre(workX: Int, workY: Int, workWidth: Int, workHeight: Int, width: Int, height: Int) -> (x: Int, y: Int) {
        (workX + max(0, (workWidth - width) / 2), workY + max(0, (workHeight - height) / 2))
    }

    /// "1600 x 900".
    public static func name(width: Int, height: Int) -> String {
        "\(width) x \(height)"
    }
}
