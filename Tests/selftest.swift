// Plain-Swift checks for SwitchboardCore. No XCTest, so it runs with Command Line Tools alone.
// Run with: scripts/test.sh
import Foundation
import SwitchboardCore

var failures = 0
func check(_ ok: @autoclosure () throws -> Bool, _ what: String, line: Int = #line) {
    let passed = (try? ok()) ?? false
    if !passed { failures += 1; print("FAIL line \(line): \(what)") }
}

let localState = """
{"profile":{"info_cache":{
  "Default":{"name":"Personal","user_name":"me@example.com"},
  "Profile 10":{"name":"Ten","user_name":""},
  "Profile 2":{"name":"Work","user_name":"me@work.example"}
}}}
""".data(using: .utf8)!

// Parsing and order
let chrome = ProfileDiscovery.parse(localState: localState, browser: .chrome)
check(chrome.map(\.directory) == ["Default", "Profile 2", "Profile 10"], "profiles sorted numerically")
check(chrome[0].email == "me@example.com", "email read")
check(chrome[2].email == nil, "empty email becomes nil")
check(chrome[1].ref == "chrome:Profile 2", "ref format")

// Host patterns
check(Router.host("uni-my.sharepoint.com", matches: "*.sharepoint.com"), "wildcard subdomain")
check(Router.host("sharepoint.com", matches: "*.sharepoint.com"), "wildcard matches bare domain")
check(!Router.host("notsharepoint.com", matches: "*.sharepoint.com"), "wildcard is not a suffix match")
check(Router.host("teams.microsoft.com", matches: "teams.microsoft.com"), "exact host")
check(!Router.host("www.microsoft.com", matches: "teams.microsoft.com"), "exact host only")

// Routing
let edge = Profile(browser: .edge, directory: "Default", name: "School", email: nil)
let config = Config(aliases: ["school": "edge:Default", "personal": "chrome:Default"],
                    rules: [Rule(match: "*.instructure.com", open: "school")],
                    fallback: "personal")
let r = Router(config: config, profiles: chrome + [edge])
check(try r.route(URL(string: "https://uni.instructure.com/courses/1")!) == edge, "rule wins")
check(try r.route(URL(string: "https://github.com")!).directory == "Default", "fallback")
check(try r.profile(named: "Work").directory == "Profile 2", "lookup by profile name")
check(try r.profile(named: "me@work.example").directory == "Profile 2", "lookup by email")
check(try r.profile(named: "SCHOOL") == edge, "alias is case-insensitive")
check((try? r.profile(named: "nobody")) == nil, "unknown profile throws")

// Launch command
let p = Profile(browser: .edge, directory: "Profile 3", name: "x", email: nil)
check(Launcher.arguments(for: p, url: URL(string: "https://a.b")) ==
      ["-na", "Microsoft Edge", "--args", "--profile-directory=Profile 3", "https://a.b"], "open arguments")

// Unwrapping redirects
let safe = URL(string: "https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Funi.instructure.com%2Fcourses%2F1&data=x")!
check(Unwrap.destination(of: safe).host == "uni.instructure.com", "Outlook Safe Links")
check(Unwrap.destination(of: URL(string: "https://www.google.com/url?q=https://github.com/x&sa=D")!).host == "github.com", "Google redirect")
check(Unwrap.destination(of: URL(string: "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.org%2F")!).host == "example.org", "Facebook redirect")
check(Unwrap.destination(of: URL(string: "https://www.google.com/search?q=https://x.y")!).host == "www.google.com", "a search is not a redirect")
check(Unwrap.destination(of: URL(string: "https://github.com")!).host == "github.com", "plain link unchanged")
check(try r.route(safe) == edge, "wrapped link routes by its real host")

// Rules by source app
let teams = Source(bundleID: "com.microsoft.teams2", name: "Microsoft Teams")
let byApp = Router(config: Config(
    aliases: ["school": "edge:Default", "personal": "chrome:Default", "work": "chrome:Profile 2"],
    rules: [Rule(match: "github.com", from: "Microsoft Teams", open: "work"),
            Rule(match: "*.google.com", open: "personal"),
            Rule(from: "com.microsoft.teams2", open: "school")],
    fallback: "personal"), profiles: chrome + [edge])
check(try byApp.route(URL(string: "https://example.org")!, from: teams) == edge, "from-only rule by bundle ID")
check(try byApp.route(URL(string: "https://example.org")!).directory == "Default", "from rule needs a source")
check(try byApp.route(URL(string: "https://github.com")!, from: teams).directory == "Profile 2", "match + from, by app name")
check(try byApp.route(URL(string: "https://github.com")!).directory == "Default", "match + from needs both")
check(try byApp.route(URL(string: "https://docs.google.com/d/1")!, from: teams).directory == "Default", "earlier rule wins")
check(Rule(from: "x", open: "y").display == "from x", "rule display")
check(byApp.matchingRule(for: URL(string: "file:///tmp/a.html")!) == nil, "file links have no host")

// Learning
var learned = Config(rules: [Rule(match: "a.com", open: "x"), Rule(from: "Teams", open: "school")])
learned.learn(host: "A.com", open: "y")
check(learned.rules.count == 2 && learned.rules[0] == Rule(match: "a.com", open: "y"), "learn replaces and goes first")
learned.addHostRules(["b.com", "a.com"], open: "z")
check(learned.rules.map(\.display) == ["a.com", "b.com", "from Teams"], "added host rules go before app-only rules, no duplicates")
check(config.name(for: edge) == "school", "rule target uses the alias")
check(Config().name(for: edge) == "edge:Default", "…or the ref")

// Bookmarks
let marks = Bookmarks.parse("""
{"roots":{"bookmark_bar":{"type":"folder","children":[
  {"type":"url","url":"https://uni.instructure.com/courses/1"},
  {"type":"folder","children":[{"type":"url","url":"https://uni.instructure.com/x"},{"type":"url","url":"javascript:void(0)"}]},
  {"type":"url","url":"https://GitHub.com/"}]},"other":{"type":"folder","children":[]}},"version":1}
""".data(using: .utf8)!)
check(marks == ["uni.instructure.com": 2, "github.com": 1], "bookmark hosts counted, non-web links skipped")

// Hotkeys
check(Hotkey("ctrl+option+b")?.keyCode == 11, "hotkey key code")
check(Hotkey("ctrl+option+b")?.display == "⌃⌥B", "hotkey display")
check(Hotkey("cmd+shift+space")?.display == "⇧⌘Space", "modifier order")
check(Hotkey("b") == nil, "a hotkey needs a modifier")
check(Hotkey("ctrl+nope") == nil, "unknown key")

// Colours and pictures
let coloured = ProfileDiscovery.parse(localState: """
{"profile":{"info_cache":{"Default":{"name":"A","profile_color_seed":-806210}}}}
""".data(using: .utf8)!, browser: .chrome)
check(coloured.first?.color == 0xFFF3_B2BE, "signed ARGB colour becomes unsigned")
check(coloured.first?.picture == nil, "no picture without a root folder")

print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
