import Foundation

/// The default profile shared by settings, saves and crash logging.
public enum ProfileDirectory {
    public static func forUser() -> String {
        let home = NSHomeDirectory()
        let configDir = (home as NSString).appendingPathComponent(".config")
        let appSupport = (home as NSString).appendingPathComponent("Library/Application Support")

        let configTsuki = (configDir as NSString).appendingPathComponent("Tsuki")
        let appSupportTsuki = (appSupport as NSString).appendingPathComponent("Tsuki")

        if FileManager.default.fileExists(atPath: appSupportTsuki) && !FileManager.default.fileExists(atPath: configTsuki) {
            return appSupportTsuki
        }
        return configTsuki
    }
}
