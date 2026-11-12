import Foundation

/// One browser profile, e.g. Chrome "Profile 2".
public struct Profile: Hashable {
    public let browser: Browser
    public let directory: String   // "Default", "Profile 2"
    public let name: String        // the name shown in the browser
    public let email: String?      // signed-in account, if any
    /// The profile's theme colour as 0xAARRGGBB, if the browser recorded one.
    public let color: UInt32?
    /// The account picture the browser caches, if the file exists.
    public let picture: URL?

    public init(browser: Browser, directory: String, name: String, email: String?,
                color: UInt32? = nil, picture: URL? = nil) {
        self.browser = browser
        self.directory = directory
        self.name = name
        self.email = email
        self.color = color
        self.picture = picture
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
        let root = browser.supportDirectory(home: home)
        guard let data = try? Data(contentsOf: root.appendingPathComponent("Local State")) else { return [] }
        return parse(localState: data, browser: browser, root: root)
    }

    /// Parses `profile.info_cache` (and `profile.profiles_order` when present).
    /// With `root`, also looks for each profile's cached account picture.
    public static func parse(localState data: Data, browser: Browser, root: URL? = nil) -> [Profile] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profile = json["profile"] as? [String: Any],
            let cache = profile["info_cache"] as? [String: [String: Any]]
        else { return [] }

        let order = (profile["profiles_order"] as? [String]) ?? []
        let dirs = order.filter { cache[$0] != nil }
            + cache.keys.filter { !order.contains($0) }.sorted(by: dirSort)

        return dirs.compactMap { dir in
            guard let info = cache[dir] else { return nil }
            let name = (info["name"] as? String) ?? dir
            let email = info["user_name"] as? String

            // Colours are stored as signed 32-bit ARGB integers.
            let rawColor = (info["profile_color_seed"] as? Int) ?? (info["profile_highlight_color"] as? Int)
            let color = rawColor.map { UInt32(bitPattern: Int32(truncatingIfNeeded: $0)) }

            var picture: URL?
            if let root, let file = info["gaia_picture_file_name"] as? String, !file.isEmpty {
                let url = root.appendingPathComponent(dir).appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: url.path) { picture = url }
            }

            return Profile(browser: browser, directory: dir, name: name,
                           email: (email?.isEmpty ?? true) ? nil : email,
                           color: color, picture: picture)
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
