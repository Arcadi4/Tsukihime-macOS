import AppKit
import Foundation

/// The text clipboard of the desktop via AppKit's NSPasteboard.
public enum Clipboard {
    /// Puts text on the general pasteboard; returns true on success.
    @discardableResult
    public static func setText(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// The text on the pasteboard, or an empty string when it holds none.
    public static func getText() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }
}
