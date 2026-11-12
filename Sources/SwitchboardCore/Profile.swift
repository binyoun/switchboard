import Foundation

/// One browser profile, e.g. Chrome "Profile 2".
public struct Profile: Hashable {
    public let browser: Browser
    public let directory: String   // "Default", "Profile 2"
    public let name: String        // the name shown in the browser
    public let email: String?      // signed-in account, if any

    public init(browser: Browser, directory: String, name: String, email: String?) {
        self.browser = browser
        self.directory = directory
        self.name = name
        self.email = email
    }

    /// Stable reference used in config: "chrome:Profile 2".
    public var ref: String { "\(browser.id):\(directory)" }

    public var label: String {
        if let email, !email.isEmpty { return "\(browser.name) · \(name) (\(email))" }
        return "\(browser.name) · \(name)"
    }
}

public enum ProfileDiscovery {
    /// Reads every known browser's `Local State` and returns its profiles,
    /// in the browser's own order. Browsers that are not installed are skipped.
    public static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Profile] {
        Browser.all.flatMap { profiles(for: $0, home: home) }
    }

    public static func profiles(for browser: Browser,
                                home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Profile] {
        let file = browser.supportDirectory(home: home).appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: file) else { return [] }
        return parse(localState: data, browser: browser)
    }

    /// Parses `profile.info_cache` (and `profile.profiles_order` when present).
    public static func parse(localState data: Data, browser: Browser) -> [Profile] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profile = root["profile"] as? [String: Any],
            let cache = profile["info_cache"] as? [String: [String: Any]]
        else { return [] }

        let order = (profile["profiles_order"] as? [String]) ?? []
        let dirs = order.filter { cache[$0] != nil }
            + cache.keys.filter { !order.contains($0) }.sorted(by: dirSort)

        return dirs.compactMap { dir in
            guard let info = cache[dir] else { return nil }
            let name = (info["name"] as? String) ?? dir
            let email = info["user_name"] as? String
            return Profile(browser: browser, directory: dir, name: name,
                           email: (email?.isEmpty ?? true) ? nil : email)
        }
    }

    /// "Default" first, then "Profile 1", "Profile 2", "Profile 10" numerically.
    static func dirSort(_ a: String, _ b: String) -> Bool {
        func key(_ s: String) -> Int {
            if s == "Default" { return -1 }
            return Int(s.split(separator: " ").last ?? "") ?? Int.max
        }
        return key(a) == key(b) ? a < b : key(a) < key(b)
    }
}
