import Foundation

/// Finds the real destination inside common redirect wrappers, so rules see the
/// host you meant to visit rather than outlook.com or google.com.
/// Switchboard only uses this for matching; it still opens the original link,
/// so protections like Outlook Safe Links keep working.
public enum Unwrap {
    public static func destination(of url: URL) -> URL {
        var current = url
        for _ in 0..<3 {                 // wrappers can be nested
            guard let inner = once(current) else { break }
            current = inner
        }
        return current
    }

    static func once(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func param(_ names: String...) -> URL? {
            for n in names {
                if let v = items.first(where: { $0.name == n })?.value,
                   let u = URL(string: v), u.scheme?.hasPrefix("http") == true, u.host != nil {
                    return u
                }
            }
            return nil
        }
        let path = url.path

        if host.hasSuffix("safelinks.protection.outlook.com") { return param("url") }        // Outlook Safe Links
        if host.hasPrefix("www.google.") || host.hasPrefix("google."), path == "/url" {    // Google search, Gmail
            return param("q", "url")
        }
        if ["l.facebook.com", "lm.facebook.com", "l.messenger.com"].contains(host) { return param("u") }
        if host == "l.instagram.com" { return param("u") }
        if host == "www.linkedin.com", path.hasPrefix("/redir/redirect") { return param("url") }
        if host == "slack-redir.net" { return param("url") }
        return nil
    }
}
