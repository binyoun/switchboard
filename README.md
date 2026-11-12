# Switchboard

Open every link in the right browser profile, and switch between profiles with a keystroke. For macOS.

If you keep a personal Chrome, a work Chrome, a project Chrome and an Edge for school or Microsoft 365, links keep opening in the wrong one. A Canvas link lands in your personal Google account; a SharePoint file asks you to sign in again. Switchboard sits between your apps and your browsers and sends each link where it belongs.

**Status:** milestone 1 of 5. The `sb` command line tool finds your profiles, opens them and routes links by rule. The menu bar switcher and the default-browser app come next — see [PLAN.md](PLAN.md).

---

## What it does

- **Finds your profiles.** Reads Chrome's and Edge's own profile lists: names, signed-in accounts, folder names. Nothing to set up by hand.
- **Opens a profile by a short name.** `sb open school`, `sb open work https://…`.
- **Routes links by rule.** `*.sharepoint.com` → Edge, `*.instructure.com` (Canvas) → Edge, everything else → your personal Chrome. First match wins.
- *Coming:* a menu bar switcher with a global hotkey, and a small app you set as your default browser so links from Mail, Slack, Teams or Notes are routed too.

Everything is local. Switchboard reads files your browsers already keep and starts them with `open`; it does not touch cookies, passwords or history.

---

## Install

You need Swift, which comes with Apple's Command Line Tools (`xcode-select --install`). Xcode is not required.

```sh
git clone https://github.com/binyoun/switchboard.git
cd switchboard
scripts/build.sh                      # builds .build/manual/sb
cp .build/manual/sb /usr/local/bin/   # or anywhere on your PATH
```

With Xcode installed, `swift build -c release` works too.

---

## Use

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
- `sb init` starts the Edge profile with the common Microsoft 365 and Canvas hosts: SharePoint and OneDrive (`*.sharepoint.com`), Outlook and Forms (`*.office.com`), Loop and Engage (`*.cloud.microsoft`), Teams, Microsoft sign-in, and Canvas (`*.instructure.com`). Add your institution's own domains.

**Tip:** your browser's bookmarks are a good list of which sites belong to which profile.

---

## How it works

Chrome and Edge are both Chromium. Each keeps a `Local State` file in `~/Library/Application Support/<browser>/` that lists every profile, and each accepts `--profile-directory="Profile 2"` on launch. When the browser is already running, the running instance receives the arguments and opens a window or tab in that profile. Switchboard is a thin layer of names and rules on top of that.

```
Sources/SwitchboardCore/   profile discovery, config, router, launcher
Sources/sb/                the command line tool
Tests/selftest.swift       checks, run with scripts/test.sh
scripts/build.sh           swiftc-only build (no Xcode or SwiftPM needed)
```

---

## Roadmap

1. ✅ Profile discovery and `sb` CLI
2. Menu bar switcher with a global hotkey
3. Default-browser router app (rules by domain, by source app, and a modifier key for "ask me")
4. Rules editor and "always open this site here"
5. Send the current tab to another profile

Other browsers (Brave, Arc, Vivaldi, Firefox containers) may follow.

Similar tools: [Finicky](https://github.com/johnste/finicky) (open source, JavaScript config), Velja, Choosy. Switchboard aims to put the switcher and the router in one small native app.

---

## Licence

MIT © Bin Youn. Chrome and Edge are trademarks of their owners; Switchboard is not affiliated with them.
