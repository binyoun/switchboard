# Switchboard

Open every link in the right browser profile, and switch between profiles with a keystroke. For macOS.

If you keep a personal Chrome, a work Chrome, a project Chrome and an Edge for school or Microsoft 365, links keep opening in the wrong one. A Canvas link lands in your personal Google account; a SharePoint file asks you to sign in again. Switchboard sits between your apps and your browsers and sends each link where it belongs.

**Status:** milestone 2 of 5. The menu bar app and its ⌃⌥B picker switch profiles; the `sb` command line tool opens and routes links by rule. Setting Switchboard as your default browser comes next — see [PLAN.md](PLAN.md).

---

## What it does

- **Finds your profiles.** Reads Chrome's and Edge's own profile lists: names, signed-in accounts, folder names. Nothing to set up by hand.
- **Switches with a keystroke.** Press **⌃⌥B** anywhere: a picker shows every profile with its account picture. Type to filter, **1–9** or **↩** to open, **⇧↩** to open the link on your clipboard in that profile.
- **Lives in the menu bar.** The same list, one click per profile, plus *Edit Rules…* and *Open at Login*.
- **Opens a profile by a short name** from the terminal: `sb open school`, `sb open work https://…`.
- **Routes links by rule.** `*.sharepoint.com` → Edge, `*.instructure.com` (Canvas) → Edge, everything else → your personal Chrome. First match wins.
- *Coming:* set Switchboard as your default browser, so links from Mail, Slack, Teams or Notes are routed too.

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

### Menu bar and picker

Click the branch icon in the menu bar, or press **⌃⌥B**.

| Key | Does |
|---|---|
| type | filter by name, email, alias or browser |
| ↑ ↓ | move |
| ↩ or 1–9 | open a new window in that profile |
| ⇧↩ or ⇧1–9 | open the link on your clipboard in that profile |
| esc | close |

In the menu, hold ⇧ while choosing a profile to open the clipboard link there. If the menu bar icon is hidden behind the camera notch, the shortcut still works; ⌘-drag menu bar icons to make room.

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
sb open work                     # new window in that profile
sb open school canvas.uni.edu    # open a link in a profile
sb route https://uni-my.sharepoint.com/…   # where would this go? (does not open)
sb go https://uni-my.sharepoint.com/…      # open it there
sb rules                         # list rules in order
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
    { "match": "github.com",        "open": "work" }
  ],
  "fallback": "personal"
}
```

- `*.example.com` matches `example.com` and every subdomain. Anything without `*.` must match the host exactly.
- Rules are checked top to bottom; put specific ones first.
- `"hotkey": "cmd+shift+space"` changes the picker shortcut (modifiers: `ctrl`, `option`, `shift`, `cmd`; keys: letters, digits, `space`, `return`, `tab`). Choose *Reload* in the menu afterwards. If another app already holds the shortcut, the menu says so.
- `sb init` starts the Edge profile with the common Microsoft 365 and Canvas hosts: SharePoint and OneDrive (`*.sharepoint.com`), Outlook and Forms (`*.office.com`), Loop and Engage (`*.cloud.microsoft`), Teams, Microsoft sign-in, and Canvas (`*.instructure.com`). Add your institution's own domains.

**Tip:** your browser's bookmarks are a good list of which sites belong to which profile.

---

## How it works

Chrome and Edge are both Chromium. Each keeps a `Local State` file in `~/Library/Application Support/<browser>/` that lists every profile, and each accepts `--profile-directory="Profile 2"` on launch. When the browser is already running, the running instance receives the arguments and opens a window or tab in that profile. Switchboard is a thin layer of names and rules on top of that.

```
Sources/SwitchboardCore/   profile discovery, config, router, launcher
Sources/sb/                the command line tool
Sources/Switchboard/       menu bar app: status menu, picker panel, global hotkey
App/Info.plist             app bundle metadata (menu bar only, no Dock icon)
Tests/selftest.swift       checks, run with scripts/test.sh
scripts/build.sh           swiftc-only build of sb and Switchboard.app (no Xcode needed)
```

---

## Roadmap

1. ✅ Profile discovery and `sb` CLI
2. ✅ Menu bar switcher with a global hotkey
3. Default-browser router app (rules by domain, by source app, and a modifier key for "ask me")
4. Rules editor and "always open this site here"
5. Send the current tab to another profile

Other browsers (Brave, Arc, Vivaldi, Firefox containers) may follow.

Similar tools: [Finicky](https://github.com/johnste/finicky) (open source, JavaScript config), Velja, Choosy. Switchboard aims to put the switcher and the router in one small native app.

---

## Licence

MIT © Bin Youn. Chrome and Edge are trademarks of their owners; Switchboard is not affiliated with them.
