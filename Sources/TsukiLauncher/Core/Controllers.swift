import Foundation
import GameController

/// Lists the game controllers that are plugged in.
public enum Controllers {
    public static func connected() -> [String] {
        let list = GCController.controllers()
        if list.isEmpty {
            return []
        }
        return list.map { controller in
            if let name = controller.vendorName, !name.isEmpty {
                return name
            }
            return "Game Controller"
        }
    }
}
