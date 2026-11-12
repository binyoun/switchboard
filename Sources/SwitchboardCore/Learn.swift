import Foundation

extension Config {
    /// The name to write in a rule for `profile`: its first alias, or its ref.
    public func name(for profile: Profile) -> String {
        aliases(for: profile).first ?? profile.ref
    }

    /// "Always open this site here": puts an exact-host rule at the top, replacing any
    /// existing host-only rule for the same host. Exact hosts are the most specific rules,
    /// so first place is safe.
    public mutating func learn(host: String, open target: String) {
        let h = host.lowercased()
        rules.removeAll { $0.from == nil && $0.match?.lowercased() == h }
        rules.insert(Rule(match: h, open: target), at: 0)
    }

    /// Adds host rules after the existing host rules but before the first rule that matches
    /// only by app, so a broad "everything from Teams" rule cannot hide them.
    public mutating func addHostRules(_ hosts: [String], open target: String) {
        let existing = Set(rules.compactMap { $0.from == nil ? $0.match?.lowercased() : nil })
        let new = hosts.map { $0.lowercased() }.filter { !existing.contains($0) }
            .map { Rule(match: $0, open: target) }
        let at = rules.firstIndex { $0.match == nil && $0.from != nil } ?? rules.count
        rules.insert(contentsOf: new, at: at)
    }
}

/// Reads a Chromium profile's `Bookmarks` file and counts bookmarks per host.
public enum Bookmarks {
    public static func hosts(for profile: Profile,
                             home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String: Int] {
        let file = profile.browser.supportDirectory(home: home)
            .appendingPathComponent(profile.directory).appendingPathComponent("Bookmarks")
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return parse(data)
    }

    public static func parse(_ data: Data) -> [String: Int] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else { return [:] }
        var counts: [String: Int] = [:]
        func walk(_ node: [String: Any]) {
            if node["type"] as? String == "url",
               let s = node["url"] as? String, let u = URL(string: s),
               let scheme = u.scheme, scheme.hasPrefix("http"), let host = u.host?.lowercased() {
                counts[host, default: 0] += 1
            }
            for child in (node["children"] as? [[String: Any]]) ?? [] { walk(child) }
        }
        for case let root as [String: Any] in roots.values { walk(root) }
        return counts
    }
}
