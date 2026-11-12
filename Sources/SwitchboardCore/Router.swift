import Foundation

public enum RouteError: Error, CustomStringConvertible {
    case unknownProfile(String)
    case noRoute(String)

    public var description: String {
        switch self {
        case .unknownProfile(let p): return "No profile called \"\(p)\". Run `sb profiles` to see them."
        case .noRoute(let u): return "No rule matches \(u) and no fallback is set."
        }
    }
}

/// The app a link was clicked in.
public struct Source: Equatable {
    public let bundleID: String?
    public let name: String?

    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }

    /// `pattern` is a bundle ID (com.microsoft.teams2) or an app name (Microsoft Teams), any case.
    public func matches(_ pattern: String) -> Bool {
        let p = pattern.lowercased()
        return bundleID?.lowercased() == p || name?.lowercased() == p
    }

    public var display: String { name ?? bundleID ?? "unknown app" }
}

public struct Router {
    public let config: Config
    public let profiles: [Profile]

    public init(config: Config, profiles: [Profile]) {
        self.config = config
        self.profiles = profiles
    }

    /// Resolves an alias ("school"), a ref ("edge:Default"), a profile name ("circulation")
    /// or an email to a profile. Case-insensitive.
    public func profile(named key: String) throws -> Profile {
        let k = key.lowercased()
        let target = (config.aliases.first { $0.key.lowercased() == k }?.value ?? key).lowercased()
        if let p = profiles.first(where: { $0.ref.lowercased() == target }) { return p }
        if let p = profiles.first(where: { $0.name.lowercased() == target }) { return p }
        if let p = profiles.first(where: { $0.email?.lowercased() == target }) { return p }
        throw RouteError.unknownProfile(key)
    }

    /// The first rule whose every condition holds: `match` against the link's real host
    /// (after unwrapping redirects) and `from` against the app the link came from.
    public func matchingRule(for url: URL, from source: Source? = nil) -> Rule? {
        let host = Unwrap.destination(of: url).host?.lowercased()
        return config.rules.first { rule in
            if rule.match == nil && rule.from == nil { return false }
            if let m = rule.match {
                guard let host, Router.host(host, matches: m) else { return false }
            }
            if let f = rule.from {
                guard let source, source.matches(f) else { return false }
            }
            return true
        }
    }

    public func route(_ url: URL, from source: Source? = nil) throws -> Profile {
        if let rule = matchingRule(for: url, from: source) { return try profile(named: rule.open) }
        if let fb = config.fallback { return try profile(named: fb) }
        throw RouteError.noRoute(url.absoluteString)
    }

    /// `*.example.com` matches example.com and any subdomain; anything else must match exactly.
    public static func host(_ host: String, matches pattern: String) -> Bool {
        let p = pattern.lowercased()
        if p.hasPrefix("*.") {
            let base = String(p.dropFirst(2))
            return host == base || host.hasSuffix("." + base)
        }
        return host == p
    }
}
