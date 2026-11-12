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

    /// The rule that decides `url`, or nil when the fallback applies.
    public func matchingRule(for url: URL) -> Rule? {
        guard let host = url.host?.lowercased() else { return nil }
        return config.rules.first { Router.host(host, matches: $0.match) }
    }

    public func route(_ url: URL) throws -> Profile {
        if let rule = matchingRule(for: url) { return try profile(named: rule.open) }
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
