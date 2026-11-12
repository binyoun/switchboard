import Foundation
import SwitchboardCore

let usage = """
sb — open links in the right browser profile

  sb profiles              list Chrome and Edge profiles, with aliases
  sb open <profile> [url]  open a window (or url) in a profile
  sb go <url>              open url wherever the rules send it
  sb route <url> [--from <app>]
                           show where url would go, without opening it
                           (--from: bundle ID or app name the link was clicked in)
  sb rules                 list rules in order
  sb suggest <profile>     sites bookmarked in a profile that open elsewhere
                           (--add host,host… adds rules for them)
  sb windows               which profile each open browser window belongs to
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

func aliases(for p: Profile) -> [String] { config.aliases(for: p) }

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

    case "windows":
        for b in Browser.all where !profiles.filter({ $0.browser == b }).isEmpty {
            let out: String
            switch ActiveTab.script(Windows.listScript(b), browser: b) {
            case .success(let s): out = s
            case .failure(let f): print("\(b.id): \(f)"); continue
            }
            let siblings = profiles.filter { $0.browser == b }
            let owners = Windows.owners(b, profiles: siblings)
            for w in Windows.parse(out) {
                let owner = siblings.count == 1 ? siblings[0]
                    : siblings.first { $0.directory == owners[w.id] }
                let who = owner.map { aliases(for: $0).first ?? $0.ref } ?? "?"
                print("\(b.id) \(w.id)  \(w.mode)\(w.minimized ? ", minimised" : "")  → \(who)  \(w.title)")
            }
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
        guard args.count >= 2 else { fail("usage: sb route <url> [--from <app>]") }
        let u = url(args[1])
        var source: Source?
        if let i = args.firstIndex(of: "--from"), args.count > i + 1 {
            source = Source(bundleID: args[i + 1], name: args[i + 1])
        }
        let p = try router.route(u, from: source)
        let why = router.matchingRule(for: u, from: source).map { "rule \($0.display)" } ?? "fallback"
        let real = Unwrap.destination(of: u)
        let via = real.host != u.host ? "  (real destination: \(real.host ?? ""))" : ""
        print("\(p.label)  ← \(why)\(via)")

    case "rules":
        if config.rules.isEmpty { print("No rules yet. Run `sb init` or edit \(Config.defaultURL.path)") }
        for (i, r) in config.rules.enumerated() { print("\(i + 1). \(r.display) → \(r.open)") }
        print("   anything else → \(config.fallback ?? "(no fallback)")")

    case "suggest":
        guard args.count >= 2 else { fail("usage: sb suggest <profile> [--add host,host…]") }
        let p = try router.profile(named: args[1])
        if let i = args.firstIndex(of: "--add"), args.count > i + 1 {
            var c = config
            let hosts = args[i + 1].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            c.addHostRules(hosts, open: c.name(for: p))
            try c.save()
            print("Added \(c.rules.count - config.rules.count) rule(s) → \(c.name(for: p))")
            break
        }
        let found = Bookmarks.hosts(for: p)
            .filter { host, _ in (try? router.route(url(host)))?.ref != p.ref }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        if found.isEmpty { print("Every site bookmarked in \(p.name) already opens there.") }
        for (host, n) in found.prefix(40) {
            let now = (try? router.route(url(host)))?.name ?? "?"
            print("\(String(n).padding(toLength: 4, withPad: " ", startingAt: 0))\(host.padding(toLength: 40, withPad: " ", startingAt: 0))now → \(now)")
        }
        if found.count > 40 { print("… and \(found.count - 40) more") }
        if !found.isEmpty { print("\nAdd some: sb suggest \(args[1]) --add host1,host2") }

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
