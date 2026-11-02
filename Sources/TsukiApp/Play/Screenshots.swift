import Foundation

/// The outcome of one screenshot.
public struct ScreenshotResult: Sendable {
    public let path: String
    public let width: Int
    public let height: Int
    public let error: String?

    public init(path: String, width: Int, height: Int, error: String? = nil) {
        self.path = path
        self.width = width
        self.height = height
        self.error = error
    }

    public var saved: Bool { error == nil }
    public var fileName: String { (path as NSString).lastPathComponent }
}

/// Writes screenshots into a folder off the main thread, and hands results back.
public final class ScreenshotWriter: @unchecked Sendable {
    public static let prefix = "Tsukihime_"

    private let lock = NSLock()
    private var results: [ScreenshotResult] = []
    private let nowFunc: () -> Date
    private var lastName: String?
    private var lastSuffix: Int = 0
    private var pendingCount: Int = 0

    public let folder: String

    public init(folder: String, now: (() -> Date)? = nil) {
        self.folder = folder
        self.nowFunc = now ?? { Date() }
    }

    public static var defaultFolder: String {
        let home = NSHomeDirectory()
        let pictures = (home as NSString).appendingPathComponent("Pictures")
        return (pictures as NSString).appendingPathComponent("Tsukihime")
    }

    public var pending: Int {
        lock.withLock { pendingCount }
    }

    public func nextPath() -> String {
        lock.lock()
        defer { lock.unlock() }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = Self.prefix + formatter.string(from: nowFunc())

        if stamp == lastName {
            lastSuffix += 1
        } else {
            lastName = stamp
            lastSuffix = 1
        }

        var path = (folder as NSString).appendingPathComponent("\(stamp)\(lastSuffix > 1 ? "-\(lastSuffix)" : "").png")
        while FileManager.default.fileExists(atPath: path) {
            lastSuffix += 1
            path = (folder as NSString).appendingPathComponent("\(stamp)-\(lastSuffix).png")
        }
        return path
    }

    @discardableResult
    public func save(width: Int, height: Int, rgba: [UInt8]) -> String {
        precondition(width >= 1 && height >= 1, "invalid width/height")
        precondition(rgba.count == width * height * 4, "pixel buffer size mismatch")

        let path = nextPath()
        lock.withLock { pendingCount += 1 }

        var pixels = rgba
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                for a in stride(from: 3, to: pixels.count, by: 4) {
                    pixels[a] = 255
                }
                try PngWriter.write(path: path, width: width, height: height, rgba: pixels)
                self.lock.withLock {
                    self.results.append(ScreenshotResult(path: path, width: width, height: height, error: nil))
                    self.pendingCount -= 1
                }
            } catch {
                self.lock.withLock {
                    self.results.append(ScreenshotResult(path: path, width: width, height: height, error: error.localizedDescription))
                    self.pendingCount -= 1
                }
            }
        }

        return path
    }

    public func tryTakeResult() -> ScreenshotResult? {
        lock.withLock {
            if results.isEmpty {
                return nil
            }
            return results.removeFirst()
        }
    }

    public func waitAll(timeout: TimeInterval) -> Bool {
        let start = Date()
        while pending > 0 {
            if Date().timeIntervalSince(start) > timeout {
                return false
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return true
    }
}
