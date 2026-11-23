import Foundation

enum AppIdentity {
    static let name = "cosmNotes"
    static let bundleIdentifier = "com.cosmofang.cosmnotes"
    static let releaseRepository = "Cosmofang/cosmNotes-app"
    static let urlScheme = "cosmnotes"
    private static let dataDirectoryOverride = ProcessInfo.processInfo.environment["COSMNOTES_DATA_DIR"]
    static let preferences: UserDefaults = {
        let domain = dataDirectoryOverride?.isEmpty == false ? bundleIdentifier + ".verification" : bundleIdentifier
        return UserDefaults(suiteName: domain) ?? .standard
    }()

    static let dataDirectory: URL = {
        if let path = dataDirectoryOverride, !path.isEmpty {
            let expandedPath = (path as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL
        }

        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
    }()
}
