import Foundation
/// Appends to `crash.log` in the profile folder.
public enum CrashLog {
    public static let fileName = "crash.log"

    @discardableResult
    public static func write(dataDirectory: String?, logFile: String?, error: Error) -> String? {
        append(dataDirectory: dataDirectory, logFile: logFile, text: "\(error)")
    }

    @discardableResult
    public static func append(dataDirectory: String?, logFile: String?, text: String) -> String? {
        for dir in candidates(dataDirectory: dataDirectory, logFile: logFile) {
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let path = (dir as NSString).appendingPathComponent(fileName)
                let formatter = ISO8601DateFormatter()
                let stamp = formatter.string(from: Date())
                let line = "\(stamp)  \(text)\n\n"
                if let data = line.data(using: .utf8) {
                    if let fileHandle = FileHandle(forWritingAtPath: path) {
                        defer { try? fileHandle.close() }
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                    } else {
                        try line.write(toFile: path, atomically: true, encoding: .utf8)
                    }
                }
                return path
            } catch {
                continue
            }
        }
        return nil
    }

    private static func candidates(dataDirectory: String?, logFile: String?) -> [String] {
        var list = [String]()
        if let d = dataDirectory, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list.append(d)
        }
        if let l = logFile, !l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let logDir = (l as NSString).deletingLastPathComponent
            if !logDir.isEmpty {
                list.append(logDir)
            }
        }
        list.append(ProfileDirectory.forUser())
        return list
    }
}

/// A lock guard ensuring only one game instance runs per profile folder.
public final class SingleInstanceLock {
    private let fd: Int32
    public let lockPath: String

    init(fd: Int32, lockPath: String) {
        self.fd = fd
        self.lockPath = lockPath
    }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }
}

public enum SingleInstance {
    public static func tryAcquire(dataDirectory: String) -> SingleInstanceLock? {
        guard !dataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        try? FileManager.default.createDirectory(atPath: dataDirectory, withIntermediateDirectories: true)
        let lockPath = (dataDirectory as NSString).appendingPathComponent(".tsukihime.lock")
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o666)
        guard fd >= 0 else {
            return nil
        }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return nil
        }

        return SingleInstanceLock(fd: fd, lockPath: lockPath)
    }
}
