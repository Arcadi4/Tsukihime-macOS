import Foundation
import TsukiCore
import TsukiEngine

final class LayerNameTracker {
    static let layerCount = 40
    private var names: [Int: String] = [:]

    func sourceName(_ s: StatementView) -> String? {
        if s.key != "STCH" && s.key != "SCH2" { return nil }
        guard let src = s.expr(18) else { return nil }
        return names[src]
    }

    static func pictureName(_ s: StatementView, sourceName: String?, aa: inout Int, bb: inout Int) -> [UInt8]? {
        aa = 0
        bb = 0
        guard s.textCount > 1 else { return nil }
        let arg = s.textValue(1).toArray()
        if arg.isEmpty { return nil }

        let clipped = arg.count > 255 ? Array(arg.prefix(255)) : arg

        var h = 0
        var v = 0
        if let src = s.expr(18), src >= 0 && src < layerCount,
           let sn = sourceName, !sn.isEmpty,
           let dv = variantDigits(sn) {
            h = dv.h
            v = dv.v
        }

        h = s.expr(9) ?? h
        v = s.expr(10) ?? v
        aa = h
        bb = v
        return clipped
    }

    func update(_ s: StatementView, pictureKey: String?) {
        if s.key == "STCH" || s.key == "SCH2" {
            if let layer = s.expr(0), layer >= 0 && layer < Self.layerCount,
               let pk = pictureKey, !pk.isEmpty {
                names[layer] = pk
            }
        } else if s.key == "STCC", let l = s.expr(0) {
            if l == -1 {
                names.removeAll()
            } else {
                names.removeValue(forKey: l)
            }
        }
    }

    static func variantDigits(_ name: String) -> (h: Int, v: Int)? {
        let n = name.count
        if n < 7 { return nil }
        let chars = Array(name)
        if chars[n - 6] != "_" || chars[n - 3] != "_" {
            return nil
        }
        if !(name.hasPrefix("IMG") || n >= 15) {
            return nil
        }

        func d(_ at: Int) -> Int {
            Int(chars[at].asciiValue ?? 0) - 48
        }
        return ((10 * d(n - 5)) + d(n - 4), (10 * d(n - 2)) + d(n - 1))
    }

    static func text(_ bytes: [UInt8]) -> String {
        latin1(bytes)
    }
}
