import Foundation

/// A Chromium-family browser that keeps its profiles in a `Local State` file
/// and accepts `--profile-directory=<dir>` on launch.
public struct Browser: Hashable, Codable {
    public let id: String          // short key used in refs: "chrome", "edge"
    public let name: String        // display name
    public let appName: String     // name for `open -a`
    public let bundleID: String
    public let supportPath: String // relative to ~/Library/Application Support

    public static let chrome = Browser(
        id: "chrome", name: "Chrome", appName: "Google Chrome",
        bundleID: "com.google.Chrome", supportPath: "Google/Chrome")

    public static let edge = Browser(
        id: "edge", name: "Edge", appName: "Microsoft Edge",
        bundleID: "com.microsoft.edgemac", supportPath: "Microsoft Edge")

    /// Browsers Switchboard knows about. Others (Brave, Arc, Firefox) are planned, not built.
    public static let all: [Browser] = [.chrome, .edge]

    public static func named(_ id: String) -> Browser? {
        all.first { $0.id == id.lowercased() }
    }

    public func supportDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support")
            .appendingPathComponent(supportPath)
    }
}
