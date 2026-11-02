import Foundation

/// One key (or group of keys) and what it does.
public struct KeyRow: Sendable, Equatable, Identifiable {
    public var id: String { keys }
    public let keys: String
    public let action: String

    public init(_ keys: String, _ action: String) {
        self.keys = keys
        self.action = action
    }
}

/// The keyboard and mouse table.
public enum KeyTable {
    public static let rows: [KeyRow] = [
        KeyRow("Return / Space / Z / Left click", "Advance the text, decide in menus"),
        KeyRow("Esc / Right click", "System menu in the story; back in menus; on the title, asks to quit"),
        KeyRow("X", "Back in menus; hide or show the message window"),
        KeyRow("H", "Hide or show the message window"),
        KeyRow("Arrow keys", "Move the cursor; Up opens the mode panel in the story"),
        KeyRow("W / A / S / D", "Move the cursor in the menus (same as arrow keys)"),
        KeyRow("Q / E", "Previous / next tab or page in menus"),
        KeyRow("Control (held)", "Fast-forward"),
        KeyRow("Tab / Middle click", "Toggle latched skip"),
        KeyRow("A", "Toggle auto mode"),
        KeyRow("Mouse wheel up / Page Up / I", "Backlog (in the story)"),
        KeyRow("Mouse wheel / Page Up / Page Down", "Scroll lists and pages in menus"),
        KeyRow("Backspace / Delete (held)", "Rewind (back in menus)"),
        KeyRow("F5 / F9", "Quick save / quick load"),
        KeyRow("N / B", "Next / previous scene"),
        KeyRow("V", "Replay the voice"),
        KeyRow("M", "System menu; copy a slot in the save list"),
        KeyRow("Forward Delete", "Delete the slot under the cursor in the save list"),
        KeyRow("Command+Return / F11", "Fullscreen on / off (same as Config › System › Display Mode)"),
        KeyRow("F12", "Screenshot: a PNG into Pictures/Tsukihime")
    ]

    public static var essentials: [KeyRow] {
        rows.filter {
            $0.keys.contains("Return") || $0.keys.contains("Esc") || $0.keys.contains("Control") ||
            $0.keys == "A" || $0.keys.contains("F5") || $0.keys.contains("Command+Return")
        }
    }
}
