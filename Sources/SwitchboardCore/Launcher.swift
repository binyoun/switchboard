import Foundation

public enum Launcher {
    /// The command that opens `url` (or a new window) in `profile`.
    /// If the browser is already running, Chromium hands the arguments to the running
    /// instance, which opens a window or tab in that profile.
    public static func arguments(for profile: Profile, url: URL?) -> [String] {
        var args = ["-na", profile.browser.appName, "--args",
                    "--profile-directory=\(profile.directory)"]
        if let url { args.append(url.absoluteString) }
        return args
    }

    @discardableResult
    public static func open(_ profile: Profile, url: URL? = nil) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = arguments(for: profile, url: url)
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
