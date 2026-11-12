import AppKit
import ServiceManagement
import SwitchboardCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeyCenter()
    private let picker = PickerController()
    private var config = Config()
    private var profiles: [Profile] = []
    private var hotkey = Hotkey(Config.defaultHotkey)!
    private var hotkeyOK = true

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

        picker.onChoose = { [weak self] profile, url in self?.open(profile, url: url) }
        reload()

        // `open -a Switchboard --args --picker` shows the picker straight away (handy for scripts).
        if CommandLine.arguments.contains("--picker") { togglePicker() }
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
        add(menu, "Edit Rules…", #selector(editConfig))
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
