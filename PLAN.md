# Plan

## Goal

One place to (a) jump to any browser profile and (b) have every clicked link open in the right profile, without thinking about it. macOS first, Chromium browsers first (Chrome, Edge).

## Decisions

- **Native Swift.** Becoming the default browser needs a real `.app` that declares http/https handlers; opening a link has to be instant. Electron or a web page cannot do either well.
- **No Xcode required.** Builds with `swiftc` from Command Line Tools (`scripts/build.sh`); the app bundle will be assembled by script with a hand-written `Info.plist`. `Package.swift` is kept for people who have Xcode.
- **Config is a JSON file** (`~/.config/switchboard/config.json`), so it can be edited by hand, backed up and diffed. The app's editor writes the same file.
- **Read only what the browser already publishes.** `Local State` for profiles; no cookies, history or passwords.
- **Personal for now.** Unsigned app, opened once with right-click → Open. Signing and notarisation only if others ask.

## Milestones

### 1. Profile discovery and CLI ✅
- Read `Local State` for Chrome and Edge: folder, name, email, order.
- `sb profiles | open | go | route | rules | init`.
- Rules: host patterns, first match wins, fallback.
- Self-checks in `Tests/selftest.swift`.

### 2. Menu bar switcher ✅
- AppKit status item listing profiles: account picture (or theme colour and initial), browser badge, email, aliases; 1–9 while the menu is open.
- Global hotkey (default ⌃⌥B, set with `"hotkey"` in the config) via Carbon `RegisterEventHotKey`, so no Accessibility permission. ⌥Space was avoided because other assistants use it.
- Floating picker (SwiftUI in an NSPanel): type to filter, ↑↓, ↩ or 1–9 to open, ⇧ to open the clipboard link in the chosen profile, esc or click away to close.
- Pictures from each profile's cached `Google Profile Picture.png` / `Edge Profile Picture.png`; colours from `profile_color_seed`.
- Open at Login through `SMAppService`; *Edit Rules…* opens the config as text.
- `scripts/build.sh install` bundles, ad-hoc signs and installs to ~/Applications.

### 3. Default-browser router ✅
- `Info.plist` claims http/https (`CFBundleURLTypes`) and `public.html`/`public.xhtml`; the install script runs `lsregister`. *Make Default Browser…* calls `NSWorkspace.setDefaultApplication`, which shows the macOS confirmation.
- Links arrive as `kAEGetURL` Apple events (handler installed in `applicationWillFinishLaunching`, so the launching link is caught too); `.html` files through `application(_:open:)`.
- Rules gain `from`: the sender PID of the Apple event → `NSRunningApplication` → bundle ID and name. A rule with `match` and `from` needs both.
- Hold **⌥** while clicking to show the picker with the link (the routed profile preselected). No rule and no fallback, or a rule naming a missing profile, also shows the picker.
- Redirect wrappers (Outlook Safe Links, Google `/url`, Facebook, Instagram, LinkedIn, Slack) are unwrapped for matching only; the original link is opened.
- `~/Library/Logs/Switchboard.log`: one line per link with host, source app, profile and deciding rule. Hosts only, no full URLs.
- The config is re-read on every link.

### 4. Rules editor and learning
- Settings window: aliases, rules (drag to reorder), fallback, hotkey.
- When the picker is shown for a host with no rule: "Always open *host* here" writes the rule.
- Import hosts from a profile's bookmarks as suggested rules.

### 5. Handoff
- Hotkey: send the current tab to another profile (read the active tab URL via AppleScript for Chrome and Edge, then reopen it in the target profile).

## Known hard parts

- **Focusing an existing window of a given profile.** Chrome's AppleScript lists windows but not their profile. Options: match by window title (Chrome adds the profile name when several are open), or remember windows Switchboard opened. Fallback: open a new window, as Chrome's own profile menu does.
- **AppleScript permission.** Reading the active tab (milestone 5) needs Automation permission for each browser; the first call shows a macOS prompt.
- **Same Google account in two profiles.** Rules route by host, not by account; `docs.google.com` can only go to one profile unless the picker is used.

## Later

- Brave, Vivaldi, Arc, Chromium (same `Local State` format); Safari profiles; Firefox containers.
- URL-path rules (`docs.google.com/a/uni.example/*`).
- Sync config through a dotfiles repo.
