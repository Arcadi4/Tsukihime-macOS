import Foundation
import TsukiCore
import TsukiEngine

/// What the save file holds.
public struct SaveSummary: Sendable, Equatable {
    public let exists: Bool
    public let slots: Int
    public let manualSlots: Int
    public let lastWrite: Date?
    public let error: String?
    public let configLanguage: Int?
    public let windowMode: Int?
    public var writeError: String?

    public init(
        exists: Bool,
        slots: Int,
        manualSlots: Int,
        lastWrite: Date?,
        error: String?,
        configLanguage: Int? = nil,
        windowMode: Int? = nil,
        writeError: String? = nil
    ) {
        self.exists = exists
        self.slots = slots
        self.manualSlots = manualSlots
        self.lastWrite = lastWrite
        self.error = error
        self.configLanguage = configLanguage
        self.windowMode = windowMode
        self.writeError = writeError
    }

    public func describe() -> String {
        if let writeError = writeError {
            return "The save folder cannot be written: " + writeError
        }
        if let error = error {
            return "save.dat cannot be read: " + error
        }
        if !exists {
            return "No saves yet; they are created on the first play"
        }
        if slots == 1 {
            return "1 save slot"
        }
        return "\(slots) save slots"
    }
}

/// One backup folder.
public struct BackupInfo: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let path: String
    public let created: Date
    public let files: [String]
    public let bytes: Int64
    public let save: SaveSummary

    public init(name: String, path: String, created: Date, files: [String], bytes: Int64, save: SaveSummary) {
        self.name = name
        self.path = path
        self.created = created
        self.files = files
        self.bytes = bytes
        self.save = save
    }
}

/// Save summaries, backups and imports.
public enum SaveTools {
    private static let backedUp = ["save.dat", "settings.ini"]

    public static func summarize(_ savePath: String) -> SaveSummary {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: savePath, isDirectory: &isDir), isDir.boolValue {
            return SaveSummary(exists: true, slots: 0, manualSlots: 0, lastWrite: nil, error: "save.dat is a folder, not a file; move or rename it")
        }

        guard FileManager.default.fileExists(atPath: savePath) else {
            return SaveSummary(exists: false, slots: 0, manualSlots: 0, lastWrite: nil, error: nil)
        }

        let written: Date?
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: savePath)
            written = attrs[.modificationDate] as? Date
        } catch {
            written = nil
        }

        var usedBackup = false
        do {
            guard let store = try SaveFile.readWithFallback(path: savePath, usedBackup: &usedBackup) else {
                return SaveSummary(exists: false, slots: 0, manualSlots: 0, lastWrite: written, error: nil)
            }
            let slots = store.storedSlots()
            let manual = slots.filter { $0 < SaveStore.manualSlotCount }.count
            let lang = store.systemData.config.language
            let validLang: Int? = (lang >= 0 && lang <= 3) ? Int(lang) : nil
            let windowMode = Int(store.systemData.block.bytes[0xA9])
            return SaveSummary(
                exists: true,
                slots: slots.count,
                manualSlots: manual,
                lastWrite: written,
                error: nil,
                configLanguage: validLang,
                windowMode: windowMode
            )
        } catch {
            return SaveSummary(exists: true, slots: 0, manualSlots: 0, lastWrite: written, error: error.localizedDescription)
        }
    }

    public static func probeWritable(_ directory: String) -> String? {
        guard !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Directory cannot be empty"
        }
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let probe = (directory as NSString).appendingPathComponent(".write_test_\(UUID().uuidString)")
            try "probe".write(toFile: probe, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: probe)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public static func backup(_ paths: LauncherPaths, now: Date = Date()) -> BackupInfo? {
        let manager = FileManager.default
        let sources = backedUp
            .map { (paths.dataDirectory as NSString).appendingPathComponent($0) }
            .filter { manager.fileExists(atPath: $0) }

        guard !sources.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = formatter.string(from: now)

        var name = baseName
        var folder = (paths.backupsDirectory as NSString).appendingPathComponent(name)
        var n = 2
        while manager.fileExists(atPath: folder) {
            name = "\(baseName)-\(n)"
            folder = (paths.backupsDirectory as NSString).appendingPathComponent(name)
            n += 1
        }

        do {
            try manager.createDirectory(atPath: folder, withIntermediateDirectories: true)
            for source in sources {
                let filename = (source as NSString).lastPathComponent
                let dest = (folder as NSString).appendingPathComponent(filename)
                try manager.copyItem(atPath: source, toPath: dest)
            }
            return describe(folder: folder)
        } catch {
            return nil
        }
    }

    public static func list(_ paths: LauncherPaths) -> [BackupInfo] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: paths.backupsDirectory) else {
            return []
        }

        do {
            let entries = try manager.contentsOfDirectory(atPath: paths.backupsDirectory)
            return entries.compactMap { entry in
                let full = (paths.backupsDirectory as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard manager.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { return nil }
                let info = describe(folder: full)
                return info.files.isEmpty ? nil : info
            }
            .sorted { (a, b) in
                if a.created != b.created {
                    return a.created > b.created
                }
                return a.name > b.name
            }
        } catch {
            return []
        }
    }

    public static func restore(_ paths: LauncherPaths, backup: BackupInfo, now: Date = Date()) throws -> BackupInfo? {
        let manager = FileManager.default
        let source = (backup.path as NSString).appendingPathComponent("save.dat")
        guard manager.fileExists(atPath: source) else {
            throw TsukiError.io("this backup holds no save.dat at \(source)")
        }

        let previous = self.backup(paths, now: now)
        try manager.createDirectory(atPath: paths.dataDirectory, withIntermediateDirectories: true)
        let temp = paths.saveFile + ".restore.tmp"
        if manager.fileExists(atPath: temp) {
            try? manager.removeItem(atPath: temp)
        }
        try manager.copyItem(atPath: source, toPath: temp)
        if manager.fileExists(atPath: paths.saveFile) {
            _ = try manager.replaceItemAt(URL(fileURLWithPath: paths.saveFile), withItemAt: URL(fileURLWithPath: temp))
        } else {
            try manager.moveItem(atPath: temp, toPath: paths.saveFile)
        }
        return previous
    }

    private static func describe(folder: String) -> BackupInfo {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(atPath: folder))?
            .filter { !($0.hasPrefix(".")) }
            .sorted() ?? []

        var totalBytes: Int64 = 0
        for f in files {
            let full = (folder as NSString).appendingPathComponent(f)
            if let attrs = try? manager.attributesOfItem(atPath: full),
               let size = attrs[.size] as? NSNumber {
                totalBytes += size.int64Value
            }
        }

        let name = (folder as NSString).lastPathComponent
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let prefix = String(name.prefix(15))
        let created = formatter.date(from: prefix) ?? (try? manager.attributesOfItem(atPath: folder)[.creationDate] as? Date) ?? Date()

        let saveDat = (folder as NSString).appendingPathComponent("save.dat")
        let summary = summarize(saveDat)

        return BackupInfo(name: name, path: folder, created: created, files: files, bytes: totalBytes, save: summary)
    }

    public static func findShadPs4Image(appData: String? = nil, titleId: String = "CUSA47999") -> String? {
        let manager = FileManager.default
        let home = NSHomeDirectory()
        var searchRoots: [String] = []

        if let appData = appData {
            searchRoots.append((appData as NSString).appendingPathComponent("shadPS4/home"))
        }
        searchRoots.append((home as NSString).appendingPathComponent("Library/Application Support/shadPS4/home"))
        searchRoots.append((home as NSString).appendingPathComponent(".config/shadPS4/home"))
        searchRoots.append((home as NSString).appendingPathComponent("Documents/shadPS4/home"))

        for root in searchRoots {
            guard manager.fileExists(atPath: root) else { continue }
            guard let users = try? manager.contentsOfDirectory(atPath: root) else { continue }
            for user in users {
                let saveDir = (root as NSString)
                    .appendingPathComponent(user)
                    .appending("/savedata/\(titleId)")
                guard manager.fileExists(atPath: saveDir) else { continue }
                guard let enumerator = manager.enumerator(atPath: saveDir) else { continue }
                while let file = enumerator.nextObject() as? String {
                    let full = (saveDir as NSString).appendingPathComponent(file)
                    if let attrs = try? manager.attributesOfItem(atPath: full),
                       let size = (attrs[.size] as? NSNumber)?.intValue,
                       size == SaveFile.ps4ImageSize {
                        return full
                    }
                }
            }
        }
        return nil
    }

    public static func readPs4Image(_ imagePath: String) throws -> SaveStore {
        let data = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        guard data.count == SaveFile.ps4ImageSize else {
            throw TsukiError.format("a PS4 save image is \(SaveFile.ps4ImageSize) bytes, this file has \(data.count)")
        }
        return try SaveFile.importPs4Image([UInt8](data))
    }

    public static func importPs4(paths: LauncherPaths, imagePath: String, now: Date = Date()) throws -> (backup: BackupInfo?, slots: Int) {
        let imported = try readPs4Image(imagePath)
        let backup = self.backup(paths, now: now)
        try FileManager.default.createDirectory(atPath: paths.dataDirectory, withIntermediateDirectories: true)
        try SaveFile.writeAtomic(path: paths.saveFile, store: imported)
        return (backup, imported.storedSlots().count)
    }

    public static func exportPs4(paths: LauncherPaths, outputPath: String) throws {
        var usedBackup = false
        guard let store = try SaveFile.readWithFallback(path: paths.saveFile, usedBackup: &usedBackup) else {
            throw TsukiError.io("No save file found at \(paths.saveFile)")
        }
        let image = SaveFile.exportPs4Image(store)
        try Data(image).write(to: URL(fileURLWithPath: outputPath))
    }
}
