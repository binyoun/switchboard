import Foundation

/// The tab in front of a browser's front window, read through AppleScript.
/// The first read asks for permission (System Settings → Privacy & Security → Automation).
public struct ActiveTab: Equatable {
    public let browser: Browser
    public let url: URL
    public let title: String
    public let windowID: String
    public let tabID: String

    public enum Failure: Error, CustomStringConvertible {
        case notAllowed(Browser)
        case noWindow(Browser)
        case script(String)

        public var description: String {
            switch self {
            case .notAllowed(let b):
                return "Switchboard may not read \(b.name)'s tabs. Allow it in System Settings → Privacy & Security → Automation."
            case .noWindow(let b): return "\(b.name) has no open window."
            case .script(let s): return s
            }
        }
    }

    public static func readScript(_ b: Browser) -> String {
        """
        tell application "\(b.appName)"
            if (count of windows) = 0 then return ""
            set w to window 1
            set t to active tab of w
            return (URL of t) & linefeed & (id of w as text) & linefeed & (id of t as text) & linefeed & (title of t)
        end tell
        """
    }

    /// Parses the four lines `readScript` returns.
    public static func parse(_ output: String, browser: Browser) -> ActiveTab? {
        let lines = output.components(separatedBy: "\n")
        guard lines.count >= 3, let url = URL(string: lines[0]), url.scheme != nil else { return nil }
        return ActiveTab(browser: browser, url: url,
                         title: lines.dropFirst(3).joined(separator: "\n"),
                         windowID: lines[1], tabID: lines[2])
    }

    public static func read(_ b: Browser) -> Result<ActiveTab, Failure> {
        switch run(readScript(b), browser: b) {
        case .failure(let f): return .failure(f)
        case .success(let out):
            if out.isEmpty { return .failure(.noWindow(b)) }
            guard let tab = parse(out, browser: b) else { return .failure(.script("Could not read the tab: \(out)")) }
            return .success(tab)
        }
    }

    /// Closes exactly this tab, wherever it is now (the front window may have changed).
    @discardableResult
    public func close() -> Result<String, Failure> {
        let script = """
        tell application "\(browser.appName)"
            close (tab id \(tabID) of window id \(windowID))
        end tell
        """
        return ActiveTab.run(script, browser: browser)
    }

    static func run(_ source: String, browser: Browser) -> Result<String, Failure> {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failure(.script("Bad script")) }
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 || code == -1744 { return .failure(.notAllowed(browser)) }
            return .failure(.script(error[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(code)"))
        }
        return .success(result.stringValue ?? "")
    }
}

extension Browser {
    public static func withBundleID(_ id: String?) -> Browser? {
        guard let id else { return nil }
        return all.first { $0.bundleID.lowercased() == id.lowercased() }
    }
}
