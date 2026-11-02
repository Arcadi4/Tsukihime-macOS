import AppKit
import Foundation

/// Native message boxes using AppKit's NSAlert.
public enum MessageBox {
    /// Shows a modal error box; returns true when shown and dismissed.
    @discardableResult
    public static func showError(title: String, message: String, parent: NSWindow? = nil) -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                showAlert(title: title, message: message, parent: parent)
            }
        } else {
            return DispatchQueue.main.sync {
                showAlert(title: title, message: message, parent: parent)
            }
        }
    }

    @MainActor
    private static func showAlert(title: String, message: String, parent: NSWindow?) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")

        if let parent = parent {
            alert.beginSheetModal(for: parent, completionHandler: nil)
            return true
        } else {
            _ = alert.runModal()
            return true
        }
    }
}
