import Foundation
import TsukiCore

extension StageRuntime {
    /// Starts a look-ahead scan (package K8): the statements after the interpreter's position are fed to it, and it names the picture tiles, with their colour
    /// grade, that the layers will hold at the next commits. The scan keeps its own picture and grade per layer and starts from the script-side scene state.
    public func beginLookAhead() -> LookAheadScan {
        LookAheadScan(stage: self)
    }

    /// Key for tracking (picture, grade key) pairs already emitted.
    public struct LookAheadKey: Hashable, Sendable {
        public let pic: Int
        public let key: Int

        public init(pic: Int, key: Int) {
            self.pic = pic
            self.key = key
        }
    }

    /// The prediction of the pictures a run of statements will put on the layers (`beginLookAhead`).
    public final class LookAheadScan {
        private let stage: StageRuntime
        private var pic = [Int](repeating: -2, count: StageRuntime.layerCount)
        private var fx = [(mode: Int, a: Int, b: Int, rgb: Int)](repeating: (0, 0, 0, 0), count: StageRuntime.layerCount)
        private var pending = [Bool](repeating: false, count: StageRuntime.layerCount)

        init(stage: StageRuntime) {
            self.stage = stage
            for l in 0..<StageRuntime.layerCount {
                pic[l] = -2 // -2: not touched by the scan, the scene state holds the layer's picture
            }
        }

        private func picOf(_ l: Int) -> Int {
            pic[l] != -2 ? pic[l] : Int(stage.scene.getPic(l))
        }

        private func fxOf(_ l: Int) -> (mode: Int, a: Int, b: Int, rgb: Int) {
            pic[l] != -2 ? fx[l] : (Int(stage.scene.getFxMode(l)), Int(stage.scene.getFxA(l)), Int(stage.scene.getFxB(l)), 0xFFFFFF)
        }

        /// Reads one statement: `_STCH` / `_SCH2` put a picture on a layer, `_STEC` / `_SNX2` / `_SNX3` grade it, `_STCC` clears it.
        /// - Returns: True when the statement commits the scene (`_FADS`): the pending pictures should be named now.
        public func feed(_ st: Statement) -> Bool {
            let first = st.name.first
            if first != UInt8(ascii: "S") && first != UInt8(ascii: "F") {
                return false
            }

            let name = st.name.description
            switch name {
            case "STCH", "SCH2":
                put(st)
            case "STEC":
                grade(st, which: 0)
            case "SNX2":
                grade(st, which: 1)
            case "SNX3":
                grade(st, which: 2)
            case "STCC":
                let a = StageArgs(st)
                let l = a.has(0) ? a.expr(0) : 0
                for k in 0..<StageRuntime.layerCount {
                    if l < 0 || k == l {
                        pic[k] = -1
                        pending[k] = false
                    }
                }
            case "FADS":
                return true
            default:
                break
            }

            return false
        }

        private func put(_ st: Statement) {
            let a = StageArgs(st)
            let l = a.has(0) ? a.expr(0) : -1
            var name = a.str(1)
            guard (0...39).contains(l) else { return }

            if name.isEmpty {
                pic[l] = -1
                pending[l] = false
                return
            }

            let src = a.has(18) ? a.expr(18) : -1
            let hasSrc = (0...39).contains(src)
            var h = 0
            var v = 0
            if hasSrc {
                let sp = picOf(src)
                if sp >= 0 && sp < stage.catalog.count {
                    let digits = PictureNames.variantDigitsStch(stage.catalog.name(sp))
                    h = digits.h
                    v = digits.v
                }
            }

            if a.has(9) {
                h = a.expr(9)
            }
            if a.has(10) {
                v = a.expr(10)
            }

            if (h | v) != 0 {
                let hStr = String(format: "%02d", h > 0 ? h % 100 : 0)
                let vStr = String(format: "%02d", v > 0 ? v % 100 : 0)
                name += "_\(hStr)_\(vStr)"
            }

            let picId = stage.catalog.lookup(name)
            var fxVal: (mode: Int, a: Int, b: Int, rgb: Int) = hasSrc ? fxOf(src) : (0, 0, 0, 0xFFFFFF)
            if !hasSrc && stage.defaultColourEffect > 0 && (picId < 0 || (stage.catalog.info(picId).drawFlags & 1) == 0) {
                fxVal = (stage.defaultColourEffect, 0, 0, 0xFFFFFF)
            }

            pic[l] = picId
            fx[l] = fxVal
            pending[l] = picId >= 0
        }

        private func grade(_ st: Statement, which: Int) {
            let a = StageArgs(st)
            let l = a.has(0) ? a.expr(0) : -1
            guard (0...39).contains(l) else { return }

            if pic[l] == -2 {
                let (m0, a0, b0, c0) = fxOf(l)
                pic[l] = Int(stage.scene.getPic(l)) // simulated state starts from scene
                fx[l] = (m0, a0, b0, c0)
            }

            var (mode, fa, fb, rgb) = fx[l]
            switch which {
            case 0:
                let m = a.has(1) ? a.expr(1) : 0
                guard (0...81).contains(m) else { return }
                mode = m
                rgb = m == 1 ? StageRuntime.strtol0(a.str(2)) & 0xFFFFFF : 0xFFFFFF
            case 1:
                fa = Int(StageMath.i16(Int64(a.expr(1))))
            default:
                fb = Int(StageMath.i8(Int64(a.expr(1))))
            }

            fx[l] = (mode, fa, fb, rgb)
        }

        /// Appends the tiles of the pictures that were put on layers since the last call, each with the colour grade its layer holds now, and forgets them.
        /// Pairs (picture, grade) in `done` are not named again.
        public func flush(_ into: inout [TextureRef], _ done: inout Set<LookAheadKey>) {
            for l in 0..<StageRuntime.layerCount {
                guard pending[l] else { continue }
                pending[l] = false
                let picId = pic[l]
                let (mode, fa, fb, rgb) = fx[l]
                let key = GradeKeys.intern(ColourGrade.from(mode, brightness: fa, contrast: fb, rgb: rgb, globalColourMode: Int(stage.scene.colourMode)))
                let doneKey = LookAheadKey(pic: picId, key: key)
                guard picId >= 0, let layouts = stage.layouts, !done.contains(doneKey), let layout = layouts.get(picId, stage.language) else {
                    continue
                }
                done.insert(doneKey)

                for file in layout.files {
                    for t in file.tiles {
                        into.append(TextureRef.pictureTile(archive: file.archive, entry: file.entry, tile: t.tile, colourEffect: key))
                    }
                }
            }
        }
    }
}
