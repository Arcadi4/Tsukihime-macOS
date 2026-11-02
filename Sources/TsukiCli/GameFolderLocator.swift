import Foundation

public enum GameFolderLocator {
    public static let environmentVariable = "TSUKI_GAME_DIR"

    public static let missingMessage =
        "game folder not found: pass --game <folder> or set the environment variable TSUKI_GAME_DIR to your extracted CUSA47999 folder (the one holding eboot.bin, image/, data/ and sce_sys/)"

    public static func resolve(_ explicitPath: String?) -> String? {
        if let explicitPath = explicitPath,
           !explicitPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitPath
        }

        if let env = ProcessInfo.processInfo.environment[environmentVariable],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env
        }

        return nil
    }
}
