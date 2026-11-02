import Foundation
import TsukiEngine

/// The mode banner (docs/formats/archives_ui_movies.md 5.2 DISP_PARTS child 10: Skip, Quicksaving, Autosaving, Auto).
public final class UiBanner {
    private static let rows: [[Int]] = [
        [8, 200, 424, 256],
        [8, 72, 424, 128],
        [8, 8, 424, 64],
        [8, 136, 424, 192],
    ]

    private var _out: Bool = false

    public init(_ kind: BannerKind) {
        self.kind = kind
    }

    /// Which banner.
    public let kind: BannerKind
    public var Kind: BannerKind { kind }

    /// The animation clock (0..3 rising, 1..0 falling).
    public private(set) var t: Float = 0
    public var T: Float { t }

    /// True once the banner has gone.
    public private(set) var done: Bool = false
    public var Done: Bool { done }

    /// True while the banner is leaving.
    public var leaving: Bool { _out }
    public var Leaving: Bool { leaving }

    /// A button while the banner holds sends it away.
    public func sendAway() {
        if !_out && t >= 1.0 {
            t = 3.0
        }
    }
    public func SendAway() { sendAway() }

    public func step() {
        if _out {
            t -= 0.04
            if t < 0.0 {
                done = true
            }
        } else {
            t += 0.04
            if t > 3.0 {
                _out = true
                t = 1.0
            }
        }
    }
    public func Step() { step() }

    public func draw(_ p: UiPainter, _ ctx: UiContext) {
        let k = min(max(t, 0.0) * 9.0, 9.0)
        let i = Int(k)
        let f = k - Float(i)
        let keys = ctx.assets.tables.bannerKeys
        let k0 = keys[min(i, 9)]
        let k1 = keys[min(i + 1, 9)]
        let sx = (k0.x * (1.0 - f)) + (k1.x * f)
        let sy = (k0.y * (1.0 - f)) + (k1.y * f)
        let r = Self.rows[kind.rawValue]
        let src = RectF.fromCorners(Float(r[0]), Float(r[1]), Float(r[2]), Float(r[3]))
        p.sprite(UiSheets.banner, src, RectF(0, UiMetrics.y(32.0), src.w * sx, src.h * sy))
    }
    public func Draw(_ p: UiPainter, _ ctx: UiContext) {
        draw(p, ctx)
    }
}
