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

### 4. Rules editor and learning ✅
- SwiftUI window (Edit Rules…): aliases per profile, fallback ("Ask me" = no fallback), hotkey with validation, rules with site / app / profile, ↑↓ to reorder, rules that can never match flagged. Edits stay in memory until Save; Revert reloads.
- Live "Test a link" using the unsaved rules, with optional source app.
- Picker learning: ⌘↩ / ⌘1–9 on a clicked link writes an exact-host rule at the top (replacing any host-only rule for that host) and opens the link.
- Bookmark suggestions: hosts bookmarked in a profile that currently route elsewhere; picked ones are inserted after host rules, before app-only rules. Also `sb suggest`.
- A hidden main menu gives text fields ⌘C/⌘V/⌘A/⌘Z and windows ⌘W in a menu-bar-only app.

### 5. Send tab ✅
- Second global shortcut (default ⌃⌥⇧B, `sendHotkey`); HotKeyCenter now holds several shortcuts by id.
- Reads the frontmost Chrome/Edge window's active tab (URL, title, window id, tab id) with NSAppleScript on a background queue, so a pending permission prompt never freezes the app. `NSAppleEventsUsageDescription` explains the prompt.
- Picker in send mode: tab title in the header, routed profile preselected. ↩ copies, ⌥↩ also closes the original by `tab id … of window id …` (after a short delay, once the new tab exists). `closeAfterSend` flips the default.
- Not a browser in front, no window, or permission refused: the picker explains and still works as a switcher.
- Fixed: ⇧/⌥ + digit in the picker now matched by key code (⇧1 arrives as "!").

## Known hard parts

- **Focusing an existing window of a given profile.** Chrome's AppleScript lists windows (id, mode, minimised, name) but not their profile, and the name is only the tab title. The AppleScript window ID is Chromium's session ID, which the profile's newest `Sessions/Session_*` (SNSS) file records as the first int32 of its window commands. `Windows.pick`: (1) any normal window if the browser has one profile; (2) a window the profile's session file lists; (3) a window Switchboard saw the profile use (learned 1 s after a launch), unless a session file gives it to another profile. (4) the profile's installed web-app window (`Apps_*` file) if nothing else is open. Otherwise a new window. Note: inside `tell application "Google Chrome"`, `tab` is the tab class, not a tab character.
- **AppleScript permission.** Reading the active tab (milestone 5) needs Automation permission for each browser; the first call shows a macOS prompt.
- **Same Google account in two profiles.** Rules route by host, not by account; `docs.google.com` can only go to one profile unless the picker is used.

## Later

- Brave, Vivaldi, Arc, Chromium (same `Local State` format); Safari profiles; Firefox containers.
- URL-path rules (`docs.google.com/a/uni.example/*`).
- Sync config through a dotfiles repo.
