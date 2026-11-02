// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (ListScroll, sub_27BD4)
import Foundation

/// A tween of a list's scroll position: ease-out quad over a number of 60 Hz frames (knife `ListScroll`, sub_27BD4).
final class ListScroll {
    /// The tween length in frames (1/6 s).
    static let frames: Float = 10.0
    static let Frames: Float = frames

    private var _from: Float = 0
    private var _t: Float = 0
    private var _len: Float = 0

    /// The shown position.
    private(set) var pos: Float = 0
    var Pos: Float { pos }

    /// The position it heads for.
    private(set) var target: Float = 0
    var Target: Float { target }

    /// Heads for `v` (clamped to 0..`max`), over the standard tween or at once.
    func to(_ v: Float, _ max: Float, _ animate: Bool) {
        over(v, max, animate ? Self.frames : 0)
    }
    func to(_ v: Float, _ max: Float, animate: Bool) {
        to(v, max, animate)
    }
    func To(_ v: Float, _ max: Float, _ animate: Bool) {
        to(v, max, animate)
    }

    /// Heads for `v` over `frames` frames (0: at once).
    func over(_ v: Float, _ max: Float, _ frames: Float) {
        target = min(Swift.max(v, 0), Swift.max(max, 0))
        _len = frames
        if frames > 0 {
            _from = pos
            _t = 0
        } else {
            pos = target
            _t = 0
        }
    }
    func Over(_ v: Float, _ max: Float, _ frames: Float) {
        over(v, max, frames)
    }

    /// Jumps to `v`.
    func set(_ v: Float) {
        pos = v
        target = v
        _len = 0
    }
    func Set(_ v: Float) {
        set(v)
    }

    /// One frame.
    func step() {
        if _t < _len {
            _t = min(_t + 1, _len)
            let t = _t / _len
            pos = _from + ((target - _from) * -(t * (t - 2)))
        }
    }
    func Step() {
        step()
    }

    /// True while the tween runs.
    var moving: Bool { _t < _len }
    var Moving: Bool { moving }
}
