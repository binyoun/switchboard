import Foundation
import SwitchboardCore

let usage = """
sb — open links in the right browser profile

  sb profiles              list Chrome and Edge profiles, with aliases
  sb open <profile> [url]  open a window (or url) in a profile
  sb go <url>              open url wherever the rules send it
  sb route <url>           show where url would go, without opening it
  sb rules                 list rules in order
  sb init                  write a starter config from the profiles found

<profile> is an alias (school), a ref (edge:Default), a profile name or an email.
Config: \(Config.defaultURL.path)  (override with SWITCHBOARD_CONFIG)
"""

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func url(_ s: String) -> URL {
    let full = s.contains("://") ? s : "https://" + s
    guard let u = URL(string: full), u.host != nil else { fail("Not a URL: \(s)") }
    return u
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first, !["-h", "--help", "help"].contains(cmd) else {
    print(usage); exit(0)
}

let config: Config
do { config = try Config.load() } catch { fail("Could not read config: \(error)") }
let profiles = ProfileDiscovery.all()
let router = Router(config: config, profiles: profiles)

func aliases(for p: Profile) -> [String] {
    config.aliases.filter { $0.value.lowercased() == p.ref.lowercased() }.map(\.key).sorted()
}

do {
    switch cmd {
    case "profiles", "ls":
        if profiles.isEmpty { fail("No Chrome or Edge profiles found.") }
        let w = profiles.map(\.ref.count).max() ?? 0
        for p in profiles {
            let a = aliases(for: p)
            let tag = a.isEmpty ? "" : "  [\(a.joined(separator: ", "))]"
            print(p.ref.padding(toLength: w + 2, withPad: " ", startingAt: 0) + p.label + tag)
        }

    case "open":
        guard args.count >= 2 else { fail("usage: sb open <profile> [url]") }
        let p = try router.profile(named: args[1])
        try Launcher.open(p, url: args.count > 2 ? url(args[2]) : nil)

    case "go":
        guard args.count >= 2 else { fail("usage: sb go <url>") }
        let u = url(args[1])
        try Launcher.open(try router.route(u), url: u)

    case "route":
        guard args.count >= 2 else { fail("usage: sb route <url>") }
        let u = url(args[1])
        let p = try router.route(u)
        let why = router.matchingRule(for: u).map { "rule \($0.match)" } ?? "fallback"
        print("\(p.label)  ← \(why)")

    case "rules":
        if config.rules.isEmpty { print("No rules yet. Run `sb init` or edit \(Config.defaultURL.path)") }
        for (i, r) in config.rules.enumerated() { print("\(i + 1). \(r.match) → \(r.open)") }
        print("   anything else → \(config.fallback ?? "(no fallback)")")

    case "init":
        let path = Config.defaultURL
        if FileManager.default.fileExists(atPath: path.path), !args.contains("--force") {
            fail("\(path.path) already exists. Use `sb init --force` to replace it.")
        }
        var c = Config()
        for p in profiles {
            let base = p.name.lowercased().replacingOccurrences(of: " ", with: "-")
            let key = c.aliases[base] == nil ? base : "\(p.browser.id)-\(base)"
            c.aliases[key] = p.ref
        }
        // Edge's first profile takes Microsoft 365 links; Chrome's first takes everything else.
        if let edge = profiles.first(where: { $0.browser == .edge }) {
            c.rules = Config.microsoft365Hosts.map { Rule(match: $0, open: edge.ref) }
        }
        c.fallback = profiles.first(where: { $0.browser == .chrome })?.ref ?? profiles.first?.ref
        try c.save(to: path)
        print("Wrote \(path.path) with \(c.aliases.count) aliases and \(c.rules.count) rules.")

    default:
        fail("Unknown command \"\(cmd)\".\n\n" + usage)
    }
} catch {
    fail("\(error)")
}
