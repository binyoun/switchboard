import Foundation

/// A browser window as AppleScript reports it.
public struct BrowserWindow: Equatable {
    public let id: String
    public let mode: String        // "normal" or "incognito"
    public let minimized: Bool
    public let title: String
    /// The address of the window's active tab.
    public let url: URL?

    public init(id: String, mode: String, minimized: Bool, title: String, url: URL? = nil) {
        self.id = id
        self.mode = mode
        self.minimized = minimized
        self.title = title
        self.url = url
    }
}

/// Finding and raising the window that belongs to a profile.
/// Chromium's AppleScript does not say which profile a window belongs to (and window names
/// are just the tab title), so we look the window up in each profile's session file.
public enum Windows {
    public static func listScript(_ b: Browser) -> String {
        """
        set T to character id 9 -- outside the tell: inside it, `tab` means a browser tab
        tell application "\(b.appName)"
            set out to ""
            repeat with w in windows
                set out to out & (id of w as text) & T & (mode of w as text) & T & (minimized of w as text) & T & (URL of active tab of w) & T & (name of w) & linefeed
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

    /// Parses `listScript` output: one window per line, front to back
    /// (id, mode, minimized, active tab address, name).
    public static func parse(_ output: String) -> [BrowserWindow] {
        output.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3, !f[0].isEmpty else { return nil }
            return BrowserWindow(id: f[0], mode: f[1], minimized: f[2] == "true",
                                 title: f.count > 4 ? f[4] : "", url: f.count > 3 ? URL(string: f[3]) : nil)
        }
    }

    /// The window to bring forward for web app `app` of `profile`, or nil to open it:
    /// an app window showing the app's address, in that profile (or not yet in any session file).
    public static func pickApp(_ app: WebApp, of profile: Profile, in windows: [BrowserWindow],
                               owners: [String: String], apps: Set<String>, siblings: [Profile]) -> BrowserWindow? {
        windows.filter { w in
            w.mode == "normal" && apps.contains(w.id) && w.url.map(app.owns) == true
                && (siblings.count <= 1 || owners[w.id] == nil || owners[w.id] == profile.directory)
        }.first
    }

    /// The window to bring forward for `profile`, or nil to open a new one.
    /// - `owners`: window ID → profile directory, read from each profile's session files.
    /// - `apps`: IDs of installed web-app windows (preferred less than browser windows).
    /// - `known`: window IDs Switchboard has seen this profile use (most recent last).
    /// - `siblings`: all profiles of the same browser.
    public static func pick(for profile: Profile, in windows: [BrowserWindow], owners: [String: String],
                            apps: Set<String> = [], known: [String], siblings: [Profile]) -> BrowserWindow? {
        let normal = windows.filter { $0.mode == "normal" }
        let browserWindows = normal.filter { !apps.contains($0.id) }
        let mine: (BrowserWindow) -> Bool = { owners[$0.id] == profile.directory }

        // 1. The browser has only this profile: any window is its window (front-most first).
        if siblings.count <= 1 { return browserWindows.first ?? normal.first }

        // 2. A browser window the profile's session file lists (front-most first).
        if let w = browserWindows.first(where: mine) { return w }

        // 3. A window we have seen this profile use, unless the session files say it is another's.
        //    Covers windows opened in the last few seconds, before Chromium writes its session file.
        for id in known.reversed() {
            if let w = browserWindows.first(where: { $0.id == id }), owners[id] == nil || owners[id] == profile.directory {
                return w
            }
        }
        // 4. Only an installed web app of this profile is open: bring that forward.
        return normal.first(where: mine)
    }

    /// IDs of installed web-app windows (from each profile's newest `Sessions/Apps_*` file).
    public static func appWindows(_ browser: Browser, profiles: [Profile],
                                  home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Set<String> {
        var out = Set<String>()
        for p in profiles where p.browser == browser {
            guard let data = newestSessionFile(browser, p, prefix: "Apps_", home: home) else { continue }
            out.formUnion(sessionIDs(in: data).map(String.init))
        }
        return out
    }

    static func newestSessionFile(_ browser: Browser, _ p: Profile, prefix: String, home: URL) -> Data? {
        let dir = browser.supportDirectory(home: home).appendingPathComponent(p.directory).appendingPathComponent("Sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let date: (URL) -> Date = { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        guard let newest = files.filter({ $0.lastPathComponent.hasPrefix(prefix) }).max(by: { date($0) < date($1) }) else { return nil }
        return try? Data(contentsOf: newest)
    }

    /// Window ID → profile directory for every profile of `browser`.
    /// The AppleScript window ID is Chromium's session ID, which the profile's newest
    /// `Sessions/Session_*` file records (and `Apps_*`, for installed web apps).
    public static func owners(_ browser: Browser, profiles: [Profile],
                              home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String: String] {
        var out: [String: String] = [:]
        for p in profiles where p.browser == browser {
            for prefix in ["Apps_", "Session_"] {   // browser windows win if an ID were in both
                guard let data = newestSessionFile(browser, p, prefix: prefix, home: home) else { continue }
                for id in sessionIDs(in: data) { out[String(id)] = p.directory }
            }
        }
        return out
    }

    /// The IDs a Chromium session file (SNSS) mentions: the first 32-bit field of each command,
    /// which is a window or tab ID. Both come from one counter, so a tab ID never matches a window.
    public static func sessionIDs(in data: Data) -> Set<Int32> {
        let b = [UInt8](data)
        guard b.count >= 8, b[0...3] == [0x53, 0x4E, 0x53, 0x53] else { return [] }   // "SNSS"
        var ids = Set<Int32>()
        var i = 8
        while i + 2 <= b.count {
            let size = Int(b[i]) | Int(b[i + 1]) << 8   // command id byte + payload
            i += 2
            guard size >= 1, i + size <= b.count else { break }
            if size >= 5 {
                let v = UInt32(b[i + 1]) | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3]) << 16 | UInt32(b[i + 4]) << 24
                ids.insert(Int32(bitPattern: v))
            }
            i += size
        }
        return ids
    }
}

extension ActiveTab {
    /// Runs any of the scripts above through the same AppleScript path (and error handling).
    public static func script(_ source: String, browser: Browser) -> Result<String, Failure> {
        run(source, browser: browser)
    }
}
