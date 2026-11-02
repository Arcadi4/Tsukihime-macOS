import Foundation
import TsukiEngine

/// The PS4 colour-grade kernel: recolours RGBA pixels in place for `_STEC`, `_SNX2`, `_SNX3`.
public enum StecKernel {
    /// The brightness table (SNX2, i16): `clamp(i + b, 0, 255)`, identity for 0.
    public static func brightnessLut(_ brightness: Int, _ lut: inout [UInt8]) {
        if lut.count < 256 { lut = [UInt8](repeating: 0, count: 256) }
        lut.withUnsafeMutableBufferPointer { buf in
            brightnessLut(brightness, buf)
        }
    }

    public static func brightnessLut(_ brightness: Int, _ lut: UnsafeMutableBufferPointer<UInt8>) {
        precondition(lut.count >= 256)
        let b = Int(Int16(truncatingIfNeeded: brightness))
        for i in 0..<256 {
            let v = b == 0 ? i : max(0, min(255, i + b))
            lut[i] = UInt8(v)
        }
    }

    /// The contrast table (SNX3, i8 `c`):
    /// c > 0 is 0 for i < c, `(i - c) * 255 / (255 - 2c)` up to 255 - c, and 255 above;
    /// c < 0 is `trunc(i * (255 + 2c) / 255) - c`; identity for 0.
    public static func contrastLut(_ contrast: Int, _ lut: inout [UInt8]) {
        if lut.count < 256 { lut = [UInt8](repeating: 0, count: 256) }
        lut.withUnsafeMutableBufferPointer { buf in
            contrastLut(contrast, buf)
        }
    }

    public static func contrastLut(_ contrast: Int, _ lut: UnsafeMutableBufferPointer<UInt8>) {
        precondition(lut.count >= 256)
        let c = Int(Int8(truncatingIfNeeded: contrast))
        for i in 0..<256 {
            let v: Int
            if c > 0 {
                v = i < c ? 0 : (i >= 255 - c ? 255 : (255 * (i - c)) / (255 - (2 * c)))
            } else if c < 0 {
                v = ((i * (255 + (2 * c))) / 255) - c
            } else {
                v = i
            }
            lut[i] = UInt8(v & 0xFF)
        }
    }

    /// True when `apply` would change pixels for `grade`.
    public static func changes(_ grade: ColourGrade, _ tables: StecTables) -> Bool {
        var baseMode = 0
        var sub = 0
        return plan(grade, tables, &baseMode, &sub)
    }

    /// Recolours RGBA pixels in place.
    public static func apply(_ rgba: inout [UInt8], _ grade: ColourGrade, _ tables: StecTables) {
        rgba.withUnsafeMutableBufferPointer { buf in
            apply(buf, grade, tables)
        }
    }

    /// Recolours RGBA pixels in place via buffer pointer.
    public static func apply(_ rgba: UnsafeMutableBufferPointer<UInt8>, _ grade: ColourGrade, _ tables: StecTables) {
        var baseMode = 0
        var sub = 0
        guard plan(grade, tables, &baseMode, &sub) else {
            return
        }

        var lut1 = [UInt8](repeating: 0, count: 256)
        var lut2 = [UInt8](repeating: 0, count: 256)
        brightnessLut(grade.brightness, &lut1)
        contrastLut(grade.contrast, &lut2)

        let useBright = (sub & 0x10) != 0
        let useContrast = (sub & 1) != 0

        var t0: [UInt8] = []
        var t1: [UInt8] = []
        var t2: [UInt8] = []
        var wb = 0
        var wr = 0

        let id = grade.mode
        if baseMode == 0x100 || baseMode == 0x200 {
            t0 = tables.lut(id, 0)
            t1 = tables.lut(id, 1)
            t2 = tables.lut(id, 2)
            wb = tables.weightBlue(id)
            wr = tables.weightRed(id)
        }

        let fillR = UInt8((grade.rgb >> 16) & 0xFF)
        let fillG = UInt8((grade.rgb >> 8) & 0xFF)
        let fillB = UInt8(grade.rgb & 0xFF)
        let offset = tables.lumaOffset
        let divisor = tables.lumaDivisor

        var p = 0
        let limit = rgba.count - 3
        while p < limit {
            var r = Int(rgba[p])
            var g = Int(rgba[p + 1])
            var b = Int(rgba[p + 2])

            switch baseMode {
            case 0x100:
                b = Int(t0[b])
                g = Int(t1[g])
                r = Int(t2[r])
            case 0x200:
                let sum = (b * wb) + (g * 0x224) + (r * wr)
                let y = Int((Float(sum) + offset) / divisor)
                let clampedY = max(0, min(255, y))
                b = Int(t0[clampedY])
                g = Int(t1[clampedY])
                r = Int(t2[clampedY])
            case 0x400:
                r = Int(fillR)
                g = Int(fillG)
                b = Int(fillB)
            default:
                break
            }

            if useBright {
                r = Int(lut1[r])
                g = Int(lut1[g])
                b = Int(lut1[b])
            }

            if useContrast {
                r = Int(lut2[r])
                g = Int(lut2[g])
                b = Int(lut2[b])
            }

            rgba[p] = UInt8(r & 0xFF)
            rgba[p + 1] = UInt8(g & 0xFF)
            rgba[p + 2] = UInt8(b & 0xFF)
            p += 4
        }
    }

    private static func plan(_ grade: ColourGrade, _ tables: StecTables, _ baseMode: inout Int, _ sub: inout Int) -> Bool {
        let flags = (grade.mode >= 1 && grade.mode <= StecTables.count) ? tables.flags(grade.mode) : 0
        let bNonZero = Int16(truncatingIfNeeded: grade.brightness) != 0
        let cNonZero = Int8(truncatingIfNeeded: grade.contrast) != 0
        let mode = flags | (bNonZero ? 0x10 : 0) | (cNonZero ? 1 : 0)
        sub = mode & 0xFF
        baseMode = mode & ~0xFF
        if baseMode == 0 && sub != 1 && sub != 0x10 && sub != 0x11 {
            return false
        }
        let validBase = (baseMode == 0 || baseMode == 0x100 || baseMode == 0x200 || baseMode == 0x400)
        let validSub = (sub == 0 || sub == 1 || sub == 0x10 || sub == 0x11)
        return validBase && validSub
    }
}
