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

    func applicationWillFinishLaunching(_ note: Notification) {
        // Links arrive as "get URL" Apple events. Registering here (not in didFinish) catches the
        // link that launched the app, and the event tells us which app the link was clicked in.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        picker.onChoose = { [weak self] profile, url, learn in
            if learn, let url { self?.remember(url, in: profile) }
            self?.open(profile, url: url)
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
    }

    // MARK: data

    private func reload() {
        config = (try? Config.load()) ?? Config()
        profiles = ProfileDiscovery.all()
        Avatar.clearCache()

        hotkey = config.hotkey.flatMap(Hotkey.init) ?? Hotkey(Config.defaultHotkey)!
        hotkeyOK = hotKeys.register(hotkey) { [weak self] in self?.togglePicker() }
        NSLog("Switchboard: %d profiles, shortcut %@ %@", profiles.count, hotkey.display,
              hotkeyOK ? "registered" : "REFUSED (taken by another app?)")
    }

    private func rows() -> [PickerModel.Row] {
        profiles.map { PickerModel.Row(profile: $0, aliases: config.aliases(for: $0)) }
    }

    private func open(_ profile: Profile, url: URL? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? Launcher.open(profile, url: url)
        }
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
            item.toolTip = "Hold ⇧ to open the link on the clipboard"
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
        let url = NSEvent.modifierFlags.contains(.shift) ? PickerController.clipboardURL() : nil
        open(p, url: url)
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
