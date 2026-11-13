import Foundation

/// A routing rule. Links open in profile `open` (an alias or ref) when every given condition holds:
/// `match` — the link's host pattern; `from` — the app it was clicked in (bundle ID or name).
public struct Rule: Codable, Hashable {
    public var match: String?
    public var from: String?
    public var open: String

    public init(match: String? = nil, from: String? = nil, open: String) {
        self.match = match
        self.from = from
        self.open = open
    }

    public var display: String {
        [match, from.map { "from \($0)" }].compactMap { $0 }.joined(separator: " ")
    }
}

/// An installed web app (or any site) to show as its own entry in the picker:
/// it opens in an app window of `profile`, or that window comes to the front.
public struct WebApp: Codable, Hashable {
    public var name: String
    /// Alias or ref of the profile the app belongs to.
    public var profile: String
    /// The app's start address. Windows showing an address under it count as the app.
    public var url: String

    public init(name: String, profile: String, url: String) {
        self.name = name
        self.profile = profile
        self.url = url
    }

    /// True when `address` is this app's start address or a page under it.
    public func owns(_ address: URL) -> Bool {
        guard let start = URL(string: url), let host = start.host?.lowercased(),
              address.host?.lowercased() == host, address.port == start.port,
              address.scheme?.lowercased() == start.scheme?.lowercased() else { return false }
        let base = start.path.hasSuffix("/") ? start.path : start.path + "/"
        return start.path.isEmpty || start.path == "/" || address.path == start.path || address.path.hasPrefix(base)
    }
}

/// ~/.config/switchboard/config.json
public struct Config: Codable {
    /// Short names for profiles: "personal" → "chrome:Default".
    public var aliases: [String: String]
    /// Checked top to bottom; first match wins.
    public var rules: [Rule]
    /// Where links with no matching rule go (alias or ref).
    public var fallback: String?
    /// Global shortcut for the picker, e.g. "ctrl+option+b". Nil means the default.
    public var hotkey: String?
    /// Global shortcut for "send this tab to another profile". Nil means the default.
    public var sendHotkey: String?
    /// When sending a tab, close the original. Off by default: the copy is safer.
    public var closeAfterSend: Bool?
    /// Show the picker for every clicked link, with the rules' choice preselected.
    /// Off: the rules open links directly (hold ⌥ while clicking to choose).
    public var askEveryLink: Bool?
    /// Web apps listed in the picker after the profiles.
    public var apps: [WebApp]?

    public static let defaultHotkey = "ctrl+option+b"
    public static let defaultSendHotkey = "ctrl+option+shift+b"

    public init(aliases: [String: String] = [:], rules: [Rule] = [], fallback: String? = nil,
                hotkey: String? = nil, sendHotkey: String? = nil, closeAfterSend: Bool? = nil,
                apps: [WebApp]? = nil) {
        self.aliases = aliases
        self.rules = rules
        self.fallback = fallback
        self.hotkey = hotkey
        self.sendHotkey = sendHotkey
        self.closeAfterSend = closeAfterSend
        self.apps = apps
    }

    /// Aliases that point at `profile`, sorted.
    public func aliases(for profile: Profile) -> [String] {
        aliases.filter { $0.value.lowercased() == profile.ref.lowercased() }.map(\.key).sorted()
    }

    public static var defaultURL: URL {
        if let custom = ProcessInfo.processInfo.environment["SWITCHBOARD_CONFIG"] {
            return URL(fileURLWithPath: custom)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/switchboard/config.json")
    }

    public static func load(from url: URL = defaultURL) throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    /// Microsoft 365 and Canvas hosts that belong in a work or school profile.
    /// Generic on purpose: add your own institution's domains in your config.
    public static let microsoft365Hosts = [
        "*.sharepoint.com",        // SharePoint and OneDrive for work or school
        "*.office.com",            // Outlook on the web, Forms, Office apps
        "*.cloud.microsoft",       // Loop, Engage, the new M365 domain
        "teams.microsoft.com",
        "*.teams.microsoft.com",
        "myaccount.microsoft.com",
        "login.microsoftonline.com",
        "*.instructure.com",       // Canvas
    ]
}
