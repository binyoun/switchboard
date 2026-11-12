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

print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
