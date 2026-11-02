import Darwin
import Foundation
import TsukiCore

/// Error text and checked-call helper for FFmpeg wrappers.
public enum Av {
    public static func err(_ code: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        if let strerrorFn = FfmpegBindings.shared.av_strerror {
            _ = strerrorFn(code, &buf, 256)
            return String(cString: buf)
        }
        return "FFmpeg error \(code)"
    }

    public static func check(_ ret: Int32, _ what: String) throws {
        if ret < 0 {
            throw TsukiError.format("\(what): \(err(ret)) (\(ret))")
        }
    }
}
