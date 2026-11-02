import Foundation
import TsukiEngine

/// A small deterministic generator for the menu particles.
public final class UiRandom {
    private var _state: UInt64

    public init(seed: UInt64 = 0x9E3779B97F4A7C15) {
        _state = seed | 1
    }

    /// The next value in [0, 1).
    public func next() -> Float {
        _state ^= _state << 13
        _state ^= _state >> 7
        _state ^= _state << 17
        return Float(_state >> 40) / Float(1 << 24)
    }
    public func Next() -> Float { next() }

    /// A value in [a, b).
    public func range(_ a: Float, _ b: Float) -> Float {
        a + ((b - a) * next())
    }
    public func Range(_ a: Float, _ b: Float) -> Float { range(a, b) }

    /// An integer in [lo, hi] inclusive.
    public func int(_ lo: Int, _ hi: Int) -> Int {
        lo + Int(next() * Float(hi - lo + 1))
    }
    public func IntVal(_ lo: Int, _ hi: Int) -> Int { int(lo, hi) }
}

/// Easing used by the menu fades and tweens.
public enum UiEase {
    /// Ease-out quad.
    public static func out(_ t: Float) -> Float {
        let u = min(max(t, 0.0), 1.0)
        return u * (2.0 - u)
    }
    public static func Out(_ t: Float) -> Float { out(t) }

    /// Ease-in quad.
    public static func `in`(_ t: Float) -> Float {
        let u = min(max(t, 0.0), 1.0)
        return u * u
    }
    public static func In(_ t: Float) -> Float { `in`(t) }

    /// The 1 - |((t / period) mod 2) - 1| triangle wave between 0 and 1.
    public static func triangle(_ t: Float, period: Float = 1.0) -> Float {
        var x = (t / period).truncatingRemainder(dividingBy: 2.0)
        if x < 0 {
            x += 2.0
        }
        return 1.0 - abs(x - 1.0)
    }
    public static func triangle(_ t: Float, _ period: Float) -> Float {
        triangle(t, period: period)
    }
    public static func Triangle(_ t: Float, _ period: Float = 1.0) -> Float {
        triangle(t, period: period)
    }
}

/// What the screens share: the game services, the sheets and tables, the text drawer, the frame counter and the sound shortcut.
public final class UiContext {
    init(root: UiRoot, services: GameServices, assets: UiAssets) {
        self.root = root
        self.services = services
        self.assets = assets
        self.text = UiText(assets)
        let rng = UiRandom()
        self.random = rng
        self.backdrop = UiBackdrop(rng)
    }

    /// The root that owns the screens.
    public unowned let root: UiRoot
    public var Root: UiRoot { root }

    /// The game services.
    public let services: GameServices
    public var Services: GameServices { services }

    /// The sheets and eboot tables.
    public let assets: UiAssets
    public var Assets: UiAssets { assets }

    /// The glyph text drawer.
    public let text: UiText
    public var Text: UiText { text }

    /// The particle generator.
    public let random: UiRandom
    public var Random: UiRandom { random }

    /// The submenu backdrop shared by the title, the system menu and the screens opened from them.
    public let backdrop: UiBackdrop
    public var Backdrop: UiBackdrop { backdrop }

    /// The system menu tab under the cursor, kept across invocations.
    public var menuTab: Int = 0
    public var MenuTab: Int { get { menuTab } set { menuTab = newValue } }

    /// The returning player's intro (TM_CI and the second caution) has been shown this power-on.
    public var titleIntroShown: Bool = false
    public var TitleIntroShown: Bool { get { titleIntroShown } set { titleIntroShown = newValue } }

    /// What the gallery remembers between visits.
    public let gallery: GalleryMemory = GalleryMemory()
    public var Gallery: GalleryMemory { gallery }

    /// The 60 Hz step counter since the root was created.
    public internal(set) var frame: Int64 = 0
    public var Frame: Int64 { frame }

    /// The effective UI language.
    public var language: Language { assets.language }
    public var LanguageVal: Language { language }

    /// Plays a system sound.
    public func sound(_ sound: UiSound) {
        services.playSystemSound(sound)
    }
    public func Sound(_ sound: UiSound) { self.sound(sound) }

    /// The `ui_text` string with the PS4 id `id`.
    public func message(_ id: Int) -> String {
        assets.text(id)
    }
    public func Message(_ id: Int) -> String { message(id) }

    /// The `ui_text` string of knife's SYSMES number `knifeId`.
    public func sysmes(_ knifeId: Int) -> String {
        assets.text(UiAssets.sysmes(knifeId))
    }
    public func Sysmes(_ knifeId: Int) -> String { sysmes(knifeId) }
}
