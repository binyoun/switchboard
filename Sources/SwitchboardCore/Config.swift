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

    public static let defaultHotkey = "ctrl+option+b"

    public init(aliases: [String: String] = [:], rules: [Rule] = [], fallback: String? = nil,
                hotkey: String? = nil) {
        self.aliases = aliases
        self.rules = rules
        self.fallback = fallback
        self.hotkey = hotkey
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
