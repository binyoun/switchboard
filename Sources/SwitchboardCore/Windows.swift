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
/// Chromium's AppleScript does not say which profile a window belongs to (and window names
/// are just the tab title), so we look the window up in each profile's session file.
public enum Windows {
    public static func listScript(_ b: Browser) -> String {
        """
        set T to character id 9 -- outside the tell: inside it, `tab` means a browser tab
        tell application "\(b.appName)"
            set out to ""
            repeat with w in windows
                set out to out & (id of w as text) & T & (mode of w as text) & T & (minimized of w as text) & T & (name of w) & linefeed
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
    /// - `owners`: window ID → profile directory, read from each profile's session file.
    /// - `known`: window IDs Switchboard has seen this profile use (most recent last).
    /// - `siblings`: all profiles of the same browser.
    public static func pick(for profile: Profile, in windows: [BrowserWindow], owners: [String: String],
                            known: [String], siblings: [Profile]) -> BrowserWindow? {
        let normal = windows.filter { $0.mode == "normal" }

        // 1. The browser has only this profile: any window is its window (front-most first).
        if siblings.count <= 1 { return normal.first }

        // 2. A window the profile's session file lists (front-most first).
        if let w = normal.first(where: { owners[$0.id] == profile.directory }) { return w }

        // 3. A window we have seen this profile use, unless the session files say it is another's.
        //    Covers windows opened in the last few seconds, before Chromium writes its session file.
        for id in known.reversed() {
            if let w = normal.first(where: { $0.id == id }), owners[id] == nil || owners[id] == profile.directory {
                return w
            }
        }
        return nil
    }

    /// Window ID → profile directory for every profile of `browser`.
    /// The AppleScript window ID is Chromium's session ID, which the profile's newest
    /// `Sessions/Session_*` file records.
    public static func owners(_ browser: Browser, profiles: [Profile],
                              home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String: String] {
        let fm = FileManager.default
        var out: [String: String] = [:]
        for p in profiles where p.browser == browser {
            let dir = browser.supportDirectory(home: home).appendingPathComponent(p.directory).appendingPathComponent("Sessions")
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            let newest = files.filter { $0.lastPathComponent.hasPrefix("Session_") }.max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
            guard let newest, let data = try? Data(contentsOf: newest) else { continue }
            for id in sessionIDs(in: data) { out[String(id)] = p.directory }
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
