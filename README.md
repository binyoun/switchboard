# Switchboard

Open every link in the right browser profile, and switch between profiles with a keystroke. For macOS.

If you keep a personal Chrome, a work Chrome, a project Chrome and an Edge for school or Microsoft 365, links keep opening in the wrong one. A Canvas link lands in your personal Google account; a SharePoint file asks you to sign in again. Switchboard sits between your apps and your browsers and sends each link where it belongs.

**Status:** all five milestones are built. Set Switchboard as your default browser and every link you click is routed by rule; ⌃⌥B switches profiles; ⌃⌥⇧B sends the tab you are looking at to another profile; rules are edited in a window or learned from your clicks. See [PLAN.md](PLAN.md) for what may come later.

---

## What it does

- **Finds your profiles.** Reads Chrome's and Edge's own profile lists: names, signed-in accounts, folder names. Nothing to set up by hand.
- **Switches with a keystroke.** Press **⌃⌥B** anywhere: a picker shows every profile with its account picture. Type to filter, **1–9** or **↩** to open, **⇧↩** to open the link on your clipboard in that profile.
- **Lives in the menu bar.** The same list, one click per profile, plus *Edit Rules…* and *Open at Login*.
- **Opens a profile by a short name** from the terminal: `sb open school`, `sb open work https://…`.
- **Routes every link you click.** Make Switchboard the default browser and links from Mail, Slack, Teams, Notes or anywhere else go by rule: `*.sharepoint.com` → Edge, `*.instructure.com` (Canvas) → Edge, everything else → your personal Chrome.
- **Knows where the link came from.** A rule can say "links clicked in Teams open in Edge", on its own or together with a host.
- **Sees through redirect wrappers.** Outlook Safe Links, Google, Facebook, Instagram, LinkedIn and Slack redirects are matched by their real destination. The original link is still opened, so Safe Links scanning keeps working.
- **Lets you choose when you want to.** Hold **⌥** while clicking a link to pick the profile yourself. A link that no rule covers (and no fallback) also asks.
- **Learns.** In that picker, **⌘↩** (or ⌘1–9) opens the link *and* remembers: "always open this site here".
- **Sends a tab to another profile.** Opened in the wrong account? Press **⌃⌥⇧B** in Chrome or Edge and pick where it should be. **⌥↩** also closes the original.
- **Has a rules editor.** Aliases, rules in order, fallback, shortcut, a live "test a link" box, and suggestions from a profile's bookmarks.

Everything is local. Switchboard reads files your browsers already keep and starts them with `open`; it does not touch cookies, passwords or history.

---

## Install

You need Swift, which comes with Apple's Command Line Tools (`xcode-select --install`). Xcode is not required.

```sh
git clone https://github.com/binyoun/switchboard.git
cd switchboard
scripts/build.sh install   # builds, copies Switchboard.app to ~/Applications and starts it
```

For the command line tool, copy `.build/manual/sb` onto your PATH (for example `sudo cp .build/manual/sb /usr/local/bin/`).

The app is signed ad hoc, not by a registered developer. If macOS refuses to open it, right-click it in Finder → **Open** once. It asks for no permissions: the shortcut uses the system hotkey API, which needs no Accessibility access.

With Xcode installed, `swift build -c release` works too.

---

## Use

### Make it the default browser

Menu bar icon → **Make Default Browser…**, then confirm in the macOS dialog. Or System Settings → Desktop & Dock → Default web browser → Switchboard. To undo, pick Chrome there again.

From then on every link goes through your rules. **Show Link Log** in the menu lists recent decisions (time, host, source app, profile, and the rule that decided), so a wrong route is easy to trace. The log records hosts only, never full addresses.

### Menu bar and picker

Click the branch icon in the menu bar, or press **⌃⌥B**.

| Key | Does |
|---|---|
| type | filter by name, email, alias or browser |
| ↑ ↓ | move |
| ↩ or 1–9 | switch to that profile: bring its window to the front, or open one if it has none |
| ⌥↩ or ⌥1–9 | always open a new window in that profile |
| ⇧↩ or ⇧1–9 | open the link on your clipboard in that profile |
| ⌘↩ or ⌘1–9 | when the picker came from a clicked link: open it and always send that site to this profile |
| esc | close |

In the menu, hold ⇧ while choosing a profile to open the clipboard link there, or ⌥ for a new window.

**How Switchboard finds a profile's window.** Chrome and Edge do not tell other apps which profile a window belongs to, so Switchboard looks each open window up in the profiles' session files (`<profile>/Sessions/Session_*`), where the browser records its windows (installed web apps, like a garden app, count too: switching brings a profile's browser window forward first, and its web app only if no browser window is open). A window opened in the last few seconds may not be written there yet, so Switchboard also remembers windows it opened itself. With only one profile (Edge, here), any window counts. If none is found, you get a new window. `sb windows` lists each open window with the profile it belongs to. This uses the same Automation permission as sending a tab; without it, switching opens a new window. Links always open as a tab in the profile's existing window. If the menu bar icon is hidden behind the camera notch, the shortcut still works; ⌘-drag menu bar icons to make room.

### Send a tab to another profile

With Chrome or Edge in front, press **⌃⌥⇧B**. The picker shows the tab's title, with the profile your rules would choose already selected.

| Key | Does |
|---|---|
| ↩ or 1–9 | open the tab's address in that profile; the original stays open |
| ⌥↩ or ⌥1–9 | the same, and close the original tab |
| ⌘↩ | also remember: this site always opens in that profile |

Turn on *Close the tab after sending* in the rules editor (or `"closeAfterSend": true`) to make closing the default; ⌥ then keeps the original instead. The shortcut is `"sendHotkey"` in the config.

The first time, macOS asks whether Switchboard may control Chrome (and, separately, Edge). Switchboard uses this only to read the address and title of the front tab and to close that tab when you ask. To change your answer: System Settings → Privacy & Security → Automation → Switchboard. Because the app is signed ad hoc, macOS may ask again after you rebuild it.

Only the address moves to the other profile: the page reloads there, so anything typed into a form but not saved stays in the original tab. Keep it open (the default) if that matters.

### Rules editor

Menu bar icon → **Edit Rules…** (⌘, while the menu is open).

- **Profiles:** set short names (aliases), the profile for anything no rule covers, the picker and send-tab shortcuts, and whether sending closes the original.
- **Rules:** site and/or app, and the profile it opens in. Reorder with the arrows; the first rule that fits wins. A rule with neither a site nor an app is flagged, as it never matches.
- **Test a link:** paste any link (and optionally an app) to see where it would go with the rules on screen, saved or not.
- **Suggest rules from bookmarks:** pick a profile and *Find Sites*. You get the sites bookmarked there that currently open somewhere else; tick the ones that belong and *Add Rules*. New rules go after your other site rules and before app-only rules.

Nothing is written until **Save** (⌘S). *Open Config File* opens the JSON in a text editor.

### Command line

```sh
sb profiles
```
```
chrome:Default    Chrome · Personal (you@example.com)  [personal]
chrome:Profile 2  Chrome · Work (you@company.example)  [work]
edge:Default      Edge · School (you@uni.example)      [school]
```

```sh
sb init                          # write a starter config from the profiles found
sb windows                       # which profile each open browser window belongs to
sb open work                     # new window in that profile
sb open school canvas.uni.edu    # open a link in a profile
sb route https://uni-my.sharepoint.com/…   # where would this go? (does not open)
sb route github.com --from com.microsoft.teams2   # …if clicked in Teams
sb go https://uni-my.sharepoint.com/…      # open it there
sb rules                         # list rules in order
sb suggest school                # bookmarked sites in that profile that open elsewhere
sb suggest school --add canvas.uni.edu,library.uni.edu   # add rules for some
```

A profile can be named by alias (`school`), ref (`edge:Default`), the name shown in the browser, or the signed-in email.

---

## Config

`~/.config/switchboard/config.json` (or set `SWITCHBOARD_CONFIG`). `sb init` writes one for you; see [config.example.json](config.example.json).

```json
{
  "aliases": {
    "personal": "chrome:Default",
    "work": "chrome:Profile 2",
    "school": "edge:Default"
  },
  "rules": [
    { "match": "*.sharepoint.com",  "open": "school" },
    { "match": "*.instructure.com", "open": "school" },
    { "match": "*.uni.example",     "open": "school" },
    { "match": "github.com",        "open": "work" },
    { "from": "com.microsoft.teams2", "open": "school" }
  ],
  "fallback": "personal"
}
```

- `match` is a host pattern. `*.example.com` matches `example.com` and every subdomain; anything without `*.` must match the host exactly.
- `from` is the app the link was clicked in, by bundle ID (`com.microsoft.teams2`) or name (`Microsoft Teams`). A rule with both needs both. Find an app's bundle ID with `osascript -e 'id of app "Microsoft Teams"'`.
- Rules are checked top to bottom; put specific ones first. A `from` rule catches everything from that app, so put host rules you always want (like `*.google.com` → personal) above it.
- The config is read on every click: edits apply straight away.
- `"hotkey": "cmd+shift+space"` changes the picker shortcut (modifiers: `ctrl`, `option`, `shift`, `cmd`; keys: letters, digits, `space`, `return`, `tab`). Choose *Reload* in the menu afterwards. If another app already holds the shortcut, the menu says so.
- `sb init` starts the Edge profile with the common Microsoft 365 and Canvas hosts: SharePoint and OneDrive (`*.sharepoint.com`), Outlook and Forms (`*.office.com`), Loop and Engage (`*.cloud.microsoft`), Teams, Microsoft sign-in, and Canvas (`*.instructure.com`). Add your institution's own domains.

**Tip:** your browser's bookmarks are a good list of which sites belong to which profile.

---

## How it works

Chrome and Edge are both Chromium. Each keeps a `Local State` file in `~/Library/Application Support/<browser>/` that lists every profile, and each accepts `--profile-directory="Profile 2"` on launch. When the browser is already running, the running instance receives the arguments and opens a window or tab in that profile. Switchboard is a thin layer of names and rules on top of that.

```
Sources/SwitchboardCore/   profile discovery, config, router, launcher
Sources/sb/                the command line tool
Sources/Switchboard/       menu bar app: status menu, picker, global hotkeys, link handling, send tab, rules editor
App/Info.plist             app bundle metadata (menu bar only, no Dock icon)
Tests/selftest.swift       checks, run with scripts/test.sh
scripts/build.sh           swiftc-only build of sb and Switchboard.app (no Xcode needed)
```

---

## Roadmap

1. ✅ Profile discovery and `sb` CLI
2. ✅ Menu bar switcher with a global hotkey
3. ✅ Default-browser router app (rules by domain, by source app, and a modifier key for "ask me")
4. ✅ Rules editor and "always open this site here"
5. ✅ Send the current tab to another profile

Other browsers (Brave, Arc, Vivaldi, Firefox containers) may follow.

Similar tools: [Finicky](https://github.com/johnste/finicky) (open source, JavaScript config), Velja, Choosy. Switchboard aims to put the switcher and the router in one small native app.

---

## Licence

MIT © Bin Youn. Chrome and Edge are trademarks of their owners; Switchboard is not affiliated with them.
