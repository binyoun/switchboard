import Foundation

/// A browser window as AppleScript reports it.
public struct BrowserWindow: Equatable {
    public let id: String
    public let mode: String        // "normal" or "incognito"
    public let minimized: Bool
    public let title: String

    public init(id: String, mode: String, minimized: Bool, title: String) {
        self.id = id
        self.mode = mode
        self.minimized = minimized
        self.title = title
    }
}

/// Finding and raising the window that belongs to a profile.
/// Chromium's AppleScript does not say which profile a window belongs to, so we infer it.
public enum Windows {
    public static func listScript(_ b: Browser) -> String {
        """
        tell application "\(b.appName)"
            set out to ""
            repeat with w in windows
                set out to out & (id of w as text) & tab & (mode of w as text) & tab & (minimized of w as text) & tab & (name of w) & linefeed
            end repeat
            return out
        end tell
        """
    }

    public static func frontIDScript(_ b: Browser) -> String {
        """
        tell application "\(b.appName)"
            if (count of windows) = 0 then return ""
            return id of window 1 as text
        end tell
        """
    }

    public static func focusScript(_ b: Browser, windowID: String) -> String {
        """
        tell application "\(b.appName)"
            set w to window id \(windowID)
            if minimized of w then set minimized of w to false
            set index of w to 1
            activate
        end tell
        """
    }

    /// Parses `listScript` output: one window per line, front to back.
    public static func parse(_ output: String) -> [BrowserWindow] {
        output.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3, !f[0].isEmpty else { return nil }
            return BrowserWindow(id: f[0], mode: f[1], minimized: f[2] == "true", title: f.count > 3 ? f[3] : "")
        }
    }

    /// The window to bring forward for `profile`, or nil to open a new one.
    /// - `known`: window IDs Switchboard has seen this profile use (most recent last).
    /// - `siblings`: all profiles of the same browser.
    public static func pick(for profile: Profile, in windows: [BrowserWindow],
                            known: [String], siblings: [Profile]) -> BrowserWindow? {
        let normal = windows.filter { $0.mode == "normal" }

        // 1. A window we have seen this profile use, most recently seen first.
        for id in known.reversed() {
            if let w = normal.first(where: { $0.id == id }) { return w }
        }
        // 2. The browser has only this profile: any window is its window (front-most first).
        if siblings.count <= 1 { return normal.first }

        // 3. Chromium appends " - <profile name>" to window titles when several profiles exist.
        //    Prefer the longest matching name, so "Bin" does not claim "Bin Work"'s windows.
        let names = siblings.map(\.name).sorted { $0.count > $1.count }
        for w in normal {
            let owner = names.first { n in
                [" - ", " – ", " — "].contains { w.title.hasSuffix($0 + n) }
            }
            if owner == profile.name { return w }
        }
        return nil
    }
}

extension ActiveTab {
    /// Runs any of the scripts above through the same AppleScript path (and error handling).
    public static func script(_ source: String, browser: Browser) -> Result<String, Failure> {
        run(source, browser: browser)
    }
}
