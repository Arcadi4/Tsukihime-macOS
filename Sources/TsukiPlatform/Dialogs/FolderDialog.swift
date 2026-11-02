import AppKit
import Foundation

/// State of a folder-dialog request.
public enum FolderDialogOutcome: Sendable {
    /// The dialog is still open.
    case pending
    /// The user chose a folder.
    case chosen
    /// The user cancelled.
    case cancelled
    /// The dialog failed.
    case failed
}

/// One open folder dialog request.
public final class FolderDialogRequest: @unchecked Sendable {
    private let lock = NSLock()
    private let condition = NSCondition()
    private var _outcome: FolderDialogOutcome = .pending
    private var _path: String?
    private var _error: String?

    public init() {}

    /// Current outcome.
    public var outcome: FolderDialogOutcome {
        lock.withLock { _outcome }
    }

    /// True once the dialog has closed.
    public var isCompleted: Bool {
        lock.withLock { _outcome != .pending }
    }

    /// The chosen folder (chosen only).
    public var path: String? {
        lock.withLock { _path }
    }

    /// Error text (failed only).
    public var error: String? {
        lock.withLock { _error }
    }

    /// Blocks until the dialog closes or the timeout passes; true when it closed.
    public func wait(timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }

        if _outcome != .pending {
            return true
        }

        let deadline = Date(timeIntervalSinceNow: timeout)
        while _outcome == .pending {
            if !condition.wait(until: deadline) {
                return _outcome != .pending
            }
        }
        return true
    }

    public func complete(outcome: FolderDialogOutcome, path: String? = nil, error: String? = nil) {
        condition.lock()
        _outcome = outcome
        _path = path
        _error = error
        condition.broadcast()
        condition.unlock()
    }
}

/// Shows the native macOS "choose folder" dialog (NSOpenPanel).
public enum FolderDialog {
    /// Shows a modal folder chooser on the main thread and returns the chosen path, or nil if cancelled.
    @MainActor
    public static func showModal(title: String? = nil, defaultPath: String? = nil, window: NSWindow? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let title = title {
            panel.title = title
            panel.message = title
        }
        if let defaultPath = defaultPath {
            panel.directoryURL = URL(fileURLWithPath: defaultPath)
        }

        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            return url.path
        }
        return nil
    }

    /// Starts an asynchronous folder dialog request.
    public static func show(title: String? = nil, defaultPath: String? = nil, window: NSWindow? = nil) -> FolderDialogRequest {
        let request = FolderDialogRequest()

        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            if let title = title {
                panel.title = title
                panel.message = title
            }
            if let defaultPath = defaultPath {
                panel.directoryURL = URL(fileURLWithPath: defaultPath)
            }

            let completion: (NSApplication.ModalResponse) -> Void = { response in
                if response == .OK, let url = panel.url {
                    request.complete(outcome: .chosen, path: url.path)
                } else {
                    request.complete(outcome: .cancelled)
                }
            }

            if let window = window {
                panel.beginSheetModal(for: window, completionHandler: completion)
            } else {
                panel.begin(completionHandler: completion)
            }
        }

        return request
    }
}
