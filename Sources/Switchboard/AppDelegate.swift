import AppKit
import ServiceManagement
import SwitchboardCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeyCenter()
    private let picker = PickerController()
    private let editor = EditorWindowController()
    private var config = Config()
    private var profiles: [Profile] = []
    private var hotkey = Hotkey(Config.defaultHotkey)!
    private var hotkeyOK = true
    private var sendHotkey = Hotkey(Config.defaultSendHotkey)!
    private var sendHotkeyOK = true

    func applicationWillFinishLaunching(_ note: Notification) {
        // Links arrive as "get URL" Apple events. Registering here (not in didFinish) catches the
        // link that launched the app, and the event tells us which app the link was clicked in.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        picker.onChoose = { [weak self] profile, url, mods in
            self?.chose(profile, url: url, mods: mods)
        }
        NSApp.mainMenu = Self.mainMenu()
    }

    /// Hidden for a menu bar app, but it gives text fields ⌘X ⌘C ⌘V ⌘A ⌘Z and windows ⌘W.
    private static func mainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit Switchboard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem()
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }

    /// "Always open this site here", from ⌘↩ in the picker.
    private func remember(_ url: URL, in profile: Profile) {
        guard let host = Unwrap.destination(of: url).host else { return }
        var c = (try? Config.load()) ?? config
        c.learn(host: host, open: c.name(for: profile))
        do {
            try c.save()
            config = c
            LinkLog.write("learned \(host) → \(profile.ref)")
        } catch {
            LinkLog.write("could not save rule for \(host): \(error)")
        }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch",
                                   accessibilityDescription: "Switchboard")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        reload()

        // `open -a Switchboard --args --picker` shows the picker straight away (handy for scripts).
        if CommandLine.arguments.contains("--picker") { togglePicker() }
        if CommandLine.arguments.contains("--rules") { showEditor() }
        if CommandLine.arguments.contains("--send") { sendTab() }
    }

    // MARK: data

    private func reload() {
        config = (try? Config.load()) ?? Config()
        profiles = ProfileDiscovery.all()
        Avatar.clearCache()

        hotkey = config.hotkey.flatMap(Hotkey.init) ?? Hotkey(Config.defaultHotkey)!
        hotkeyOK = hotKeys.register(hotkey, slot: 1) { [weak self] in self?.togglePicker() }
        sendHotkey = config.sendHotkey.flatMap(Hotkey.init) ?? Hotkey(Config.defaultSendHotkey)!
        sendHotkeyOK = hotKeys.register(sendHotkey, slot: 2) { [weak self] in self?.sendTab() }
        NSLog("Switchboard: %d profiles, picker %@ %@, send %@ %@", profiles.count,
              hotkey.display, hotkeyOK ? "registered" : "REFUSED",
              sendHotkey.display, sendHotkeyOK ? "registered" : "REFUSED")
    }

    private func rows() -> [PickerModel.Row] {
        profiles.map { PickerModel.Row(profile: $0, aliases: config.aliases(for: $0)) }
    }

    /// Window IDs each profile has been seen using (profile ref → IDs, most recent last).
    /// In memory only: IDs are not reused while a browser runs, and reset when it restarts.
    private var knownWindows: [String: [String]] = [:]

    /// Opens a link in `profile`, or with no link switches to it: brings its existing window to
    /// the front if one can be found, otherwise opens a new window. `newWindow` skips the search.
    private func open(_ profile: Profile, url: URL? = nil, newWindow: Bool = false) {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: profile.browser.bundleID).isEmpty
        guard url == nil, !newWindow, running else {
            launch(profile, url: url)
            return
        }
        let known = knownWindows[profile.ref] ?? []
        let siblings = profiles.filter { $0.browser == profile.browser }
        Self.scriptQueue.async {
            var raised: String?
            let owners = siblings.count > 1 ? Windows.owners(profile.browser, profiles: siblings) : [:]
            if case .success(let out) = ActiveTab.script(Windows.listScript(profile.browser), browser: profile.browser),
               let w = Windows.pick(for: profile, in: Windows.parse(out), owners: owners, known: known, siblings: siblings),
               case .success = ActiveTab.script(Windows.focusScript(profile.browser, windowID: w.id), browser: profile.browser) {
                raised = w.id
            }
            DispatchQueue.main.async {
                if let raised {
                    self.remember(windowID: raised, for: profile)
                } else {
                    self.launch(profile, url: nil)   // none found, or no permission: new window
                }
            }
        }
    }

    private func launch(_ profile: Profile, url: URL?) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? Launcher.open(profile, url: url)
            // Whatever window the browser used is now in front: note it as this profile's.
            Self.scriptQueue.asyncAfter(deadline: .now() + 1.0) {
                guard case .success(let id) = ActiveTab.script(Windows.frontIDScript(profile.browser), browser: profile.browser),
                      !id.isEmpty else { return }
                DispatchQueue.main.async { self.remember(windowID: id, for: profile) }
            }
        }
    }

    /// Records that `windowID` belongs to `profile` (and to no other profile).
    private func remember(windowID: String?, for profile: Profile) {
        guard let id = windowID else { return }
        for key in knownWindows.keys { knownWindows[key]?.removeAll { $0 == id } }
        var ids = knownWindows[profile.ref] ?? []
        ids.append(id)
        knownWindows[profile.ref] = Array(ids.suffix(10))
    }

    // MARK: links

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s) else { return }
        var source: Source?
        if let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value,
           let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            source = Source(bundleID: app.bundleIdentifier, name: app.localizedName)
        }
        handle(url, from: source)
    }

    /// .html files opened with Switchboard (double-click, or "Open With").
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url, from: nil) }
    }

    private func handle(_ url: URL, from source: Source?) {
        // Fresh every time, so edits to the config apply to the next click without Reload.
        config = (try? Config.load()) ?? config
        profiles = ProfileDiscovery.all()
        let router = Router(config: config, profiles: profiles)
        let host = url.isFileURL ? "file" : (Unwrap.destination(of: url).host ?? "?")
        let from = source.map { "  from \($0.display)" } ?? ""

        // Hold ⌥ while clicking to choose the profile yourself.
        if NSEvent.modifierFlags.contains(.option) {
            LinkLog.write("\(host)\(from)  → picker (⌥ held)")
            picker.show(rows: rows(), hotkey: hotkey.display, link: url,
                        preselect: try? router.route(url, from: source))
            return
        }
        do {
            let p = try router.route(url, from: source)
            let why = router.matchingRule(for: url, from: source).map { "rule \($0.display)" } ?? "fallback"
            LinkLog.write("\(host)\(from)  → \(p.ref) (\(why))")
            open(p, url: url)
        } catch {
            // No rule, no fallback, or a rule naming a profile that no longer exists: ask.
            LinkLog.write("\(host)\(from)  → picker (\(error))")
            picker.show(rows: rows(), hotkey: hotkey.display, link: url)
        }
    }

    // MARK: default browser

    private var isDefaultBrowser: Bool {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        else { return false }
        return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    @objc private func makeDefaultBrowser() {
        // macOS asks the user to confirm; nothing changes until they choose.
        let me = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "http") { error in
            guard error == nil else { return self.report(error) }
            NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "https") { error in
                self.report(error)
            }
        }
    }

    private func report(_ error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Switchboard is not the default browser"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can also choose it in System Settings → Desktop & Dock → Default web browser."
            alert.runModal()
        }
    }

    @objc private func showLog() {
        if !FileManager.default.fileExists(atPath: LinkLog.url.path) { LinkLog.write("log started") }
        NSWorkspace.shared.open(LinkLog.url)
    }

    // MARK: send tab

    /// ⌃⌥⇧B: read the front browser's tab and offer to open it in another profile.
    private func sendTab() {
        if picker.isVisible { picker.hide(); return }
        config = (try? Config.load()) ?? config
        profiles = ProfileDiscovery.all()

        let front = NSWorkspace.shared.frontmostApplication
        guard let browser = Browser.withBundleID(front?.bundleIdentifier) else {
            picker.show(rows: rows(), hotkey: sendHotkey.display,
                        notice: "To send a tab, press \(sendHotkey.display) while Chrome or Edge is in front. Choose a profile to open a new window instead.")
            return
        }
        // AppleScript can wait on the macOS permission prompt, so never on the main thread.
        Self.scriptQueue.async {
            let result = ActiveTab.read(browser)
            DispatchQueue.main.async { self.showSend(result) }
        }
    }

    /// One queue for all AppleScript, so scripts never run at the same time.
    static let scriptQueue = DispatchQueue(label: "switchboard.applescript")

    private func showSend(_ result: Result<ActiveTab, ActiveTab.Failure>) {
        switch result {
        case .failure(let failure):
            LinkLog.write("send: \(failure)")
            picker.show(rows: rows(), hotkey: sendHotkey.display, notice: failure.description)
        case .success(let tab):
            let router = Router(config: config, profiles: profiles)
            picker.show(rows: rows(), hotkey: sendHotkey.display, link: tab.url,
                        preselect: try? router.route(tab.url),
                        sendTab: tab, closesByDefault: config.closeAfterSend ?? false)
        }
    }

    /// What happens after a profile is chosen in the picker, in any mode.
    private func chose(_ profile: Profile, url: URL?, mods: NSEvent.ModifierFlags) {
        let tab = picker.model.sendTab
        // ⌘: remember the site for this profile (only when there is a link).
        if mods.contains(.command), let url, picker.model.link != nil { remember(url, in: profile) }
        // ⌥ when only switching: always a new window rather than the existing one.
        open(profile, url: url, newWindow: tab == nil && url == nil && mods.contains(.option))

        guard let tab else { return }
        // ⌥ flips the closeAfterSend setting for this one send.
        let close = (config.closeAfterSend ?? false) != mods.contains(.option)
        LinkLog.write("sent \(tab.url.host ?? "tab") from \(tab.browser.id) → \(profile.ref)\(close ? ", closed original" : "")")
        if close {
            // Wait until the new tab exists, so closing the last tab cannot quit-and-relaunch the browser
            // under the open command.
            Self.scriptQueue.asyncAfter(deadline: .now() + 0.8) {
                if case .failure(let f) = tab.close() { LinkLog.write("could not close original tab: \(f)") }
            }
        }
    }

    // MARK: picker

    private func togglePicker() {
        if picker.isVisible { picker.hide(); return }
        // Re-read profiles each time: they change when you add one in the browser.
        profiles = ProfileDiscovery.all()
        picker.show(rows: rows(), hotkey: hotkey.display)
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        config = (try? Config.load()) ?? config
        profiles = ProfileDiscovery.all()
        menu.removeAllItems()

        if profiles.isEmpty {
            menu.addItem(withTitle: "No Chrome or Edge profiles found", action: nil, keyEquivalent: "")
        }
        var lastBrowser: Browser?
        for (i, p) in profiles.enumerated() {
            if let last = lastBrowser, last != p.browser { menu.addItem(.separator()) }
            lastBrowser = p.browser

            let item = NSMenuItem(title: "", action: #selector(openProfile(_:)),
                                  keyEquivalent: i < 9 ? "\(i + 1)" : "")
            item.keyEquivalentModifierMask = []
            item.target = self
            item.representedObject = p.ref
            item.image = Avatar.image(p, size: 22)
            item.attributedTitle = title(for: p)
            item.toolTip = "⇧ opens the link on the clipboard · ⌥ opens a new window"
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let pick = NSMenuItem(title: "Open Picker", action: #selector(showPicker), keyEquivalent: "")
        pick.target = self
        menu.addItem(pick)
        if !hotkeyOK {
            menu.addItem(withTitle: "⚠︎ \(hotkey.display) is taken by another app — set \"hotkey\" in the config",
                         action: nil, keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "Shortcut: \(hotkey.display)", action: nil, keyEquivalent: "")
        }
        if sendHotkeyOK {
            menu.addItem(withTitle: "Send front tab to another profile: \(sendHotkey.display)", action: nil, keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "⚠︎ \(sendHotkey.display) is taken — set \"sendHotkey\" in the config",
                         action: nil, keyEquivalent: "")
        }

        menu.addItem(.separator())
        if isDefaultBrowser {
            let d = menu.addItem(withTitle: "Routing links (default browser)", action: nil, keyEquivalent: "")
            d.state = .on
            menu.addItem(withTitle: "Hold ⌥ when clicking a link to choose", action: nil, keyEquivalent: "")
        } else {
            add(menu, "Make Default Browser…", #selector(makeDefaultBrowser))
        }
        add(menu, "Edit Rules…", #selector(showEditor), key: ",")
        add(menu, "Edit Config File…", #selector(editConfig))
        add(menu, "Show Link Log", #selector(showLog))
        add(menu, "Reload", #selector(reloadAction))
        let login = add(menu, "Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        add(menu, "Quit Switchboard", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp)
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector,
                     key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        menu.addItem(item)
        return item
    }

    private func title(for p: Profile) -> NSAttributedString {
        let s = NSMutableAttributedString(string: p.name, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        var detail = "  " + p.browser.name
        if let email = p.email { detail += " · " + email }
        let aliases = config.aliases(for: p)
        if !aliases.isEmpty { detail += "  [" + aliases.joined(separator: ", ") + "]" }
        s.append(NSAttributedString(string: detail, attributes: [
            .font: NSFont.menuFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return s
    }

    // MARK: actions

    @objc private func openProfile(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? String,
              let p = profiles.first(where: { $0.ref == ref }) else { return }
        let mods = NSEvent.modifierFlags
        let url = mods.contains(.shift) ? PickerController.clipboardURL() : nil
        open(p, url: url, newWindow: mods.contains(.option))
    }

    @objc private func showPicker() { togglePicker() }

    @objc private func reloadAction() { reload() }

    @objc private func showEditor() {
        editor.show(onSaved: { [weak self] in self?.reload() },
                    openFile: { [weak self] in self?.editConfig() })
    }

    @objc private func editConfig() {
        let url = Config.defaultURL
        if !FileManager.default.fileExists(atPath: url.path) {
            // Same starter config as `sb init`.
            var c = Config()
            for p in profiles {
                let base = p.name.lowercased().replacingOccurrences(of: " ", with: "-")
                c.aliases[c.aliases[base] == nil ? base : "\(p.browser.id)-\(base)"] = p.ref
            }
            if let edge = profiles.first(where: { $0.browser == .edge }) {
                c.rules = Config.microsoft365Hosts.map { Rule(match: $0, open: edge.ref) }
            }
            c.fallback = profiles.first?.ref
            try? c.save(to: url)
        }
        // Open as plain text, whatever app owns .json.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", url.path]
        try? p.run()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Open at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMove Switchboard to Applications and try again, or add it in System Settings → General → Login Items."
            alert.runModal()
        }
    }
}
