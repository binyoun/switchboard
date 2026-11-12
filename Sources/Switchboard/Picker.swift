import AppKit
import SwiftUI
import SwitchboardCore

/// What the picker shows and which row is selected.
final class PickerModel: ObservableObject {
    struct Row: Identifiable {
        let profile: Profile
        let aliases: [String]
        var id: String { profile.ref }
    }

    @Published var query = "" { didSet { selected = 0 } }
    @Published var selected = 0
    @Published var rows: [Row] = []
    /// A link on the clipboard that ⇧↩ will open in the chosen profile.
    @Published var clipboardURL: URL?
    /// A clicked link waiting for a profile (⌥-click, or no rule matched).
    @Published var link: URL?

    var filtered: [Row] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { r in
            ([r.profile.name, r.profile.email ?? "", r.profile.browser.name] + r.aliases)
                .contains { $0.lowercased().contains(q) }
        }
    }

    func move(_ delta: Int) {
        let n = filtered.count
        guard n > 0 else { return }
        selected = (selected + delta + n) % n
    }
}

struct PickerView: View {
    @ObservedObject var model: PickerModel
    let hotkey: String
    let choose: (Profile, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let link = model.link {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open \(Unwrap.destination(of: link).host ?? "link") in…")
                        .font(.system(size: 13, weight: .semibold))
                    Text(link.absoluteString)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            TextField(model.link == nil ? "Open a profile…" : "Filter profiles…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

            Divider()

            let rows = model.filtered
            if rows.isEmpty {
                Text("No profile matches “\(model.query)”")
                    .foregroundColor(.secondary)
                    .padding(18)
            }
            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    RowView(row: row, index: i, selected: i == model.selected)
                        .contentShape(Rectangle())
                        .onTapGesture { choose(row.profile, NSEvent.modifierFlags.contains(.shift)) }
                        .onHover { if $0 { model.selected = i } }
                }
            }
            .padding(6)

            Divider()
            HStack(spacing: 14) {
                Text("↩ open")
                Text("1–9 jump")
                if model.link == nil, let url = model.clipboardURL {
                    Text("⇧↩ open \(url.host ?? "link")")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(hotkey)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 520)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RowView: View {
    let row: PickerModel.Row
    let index: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: Avatar.image(row.profile, size: 30))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.profile.name).font(.system(size: 14, weight: .semibold))
                    Text(row.profile.browser.name)
                        .font(.system(size: 11))
                        .foregroundColor(selected ? .white.opacity(0.8) : .secondary)
                }
                if let email = row.profile.email {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundColor(selected ? .white.opacity(0.85) : .secondary)
                }
            }
            Spacer()
            if !row.aliases.isEmpty {
                Text(row.aliases.joined(separator: " · "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(selected ? .white.opacity(0.85) : .secondary)
            }
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .stroke(selected ? Color.white.opacity(0.6) : Color.secondary.opacity(0.4)))
            }
        }
        .foregroundColor(selected ? .white : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(selected ? Color.accentColor : Color.clear))
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// A borderless floating panel that can take keyboard focus.
final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the panel and its keyboard handling.
final class PickerController {
    let model = PickerModel()
    private var panel: PickerPanel?
    private var keyMonitor: Any?
    private var resignObserver: Any?
    var onChoose: ((Profile, URL?) -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(rows: [PickerModel.Row], hotkey: String, link: URL? = nil, preselect: Profile? = nil) {
        model.rows = rows
        model.query = ""
        model.selected = preselect.flatMap { p in rows.firstIndex { $0.profile == p } } ?? 0
        model.link = link
        model.clipboardURL = link == nil ? Self.clipboardURL() : nil

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: PickerView(model: model, hotkey: hotkey) { [weak self] p, shift in
            self?.choose(p, shift: shift)
        })
        panel.setContentSize(panel.contentView!.fittingSize)
        position(panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeys()
    }

    func hide(returnFocus: Bool = true) {
        removeKeys()
        panel?.orderOut(nil)
        if returnFocus { NSApp.hide(nil) }
    }

    private func choose(_ p: Profile, shift: Bool) {
        let url = model.link ?? (shift ? model.clipboardURL : nil)
        hide(returnFocus: false)
        onChoose?(p, url)
    }

    private func makePanel() -> PickerPanel {
        let p = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
                            styleMask: [.borderless, .fullSizeContentView],
                            backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: p, queue: .main
        ) { [weak self] _ in self?.hide(returnFocus: false) }
        return p
    }

    /// Centred horizontally on the screen with the mouse, a third of the way down.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return }
        let s = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: f.midX - s.width / 2, y: f.maxY - f.height / 3 - s.height / 2))
    }

    private func installKeys() {
        removeKeys()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.isVisible else { return e }
            let rows = self.model.filtered
            switch e.keyCode {
            case 53: self.hide(); return nil                       // esc
            case 125: self.model.move(1); return nil               // ↓
            case 126: self.model.move(-1); return nil              // ↑
            case 36, 76:                                           // ↩, enter
                if rows.indices.contains(self.model.selected) {
                    self.choose(rows[self.model.selected].profile, shift: e.modifierFlags.contains(.shift))
                }
                return nil
            default:
                if let c = e.charactersIgnoringModifiers, let n = Int(c), (1...9).contains(n),
                   rows.indices.contains(n - 1) {
                    self.choose(rows[n - 1].profile, shift: e.modifierFlags.contains(.shift))
                    return nil
                }
                return e
            }
        }
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    static func clipboardURL() -> URL? {
        guard let s = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !s.contains(" "), !s.contains("\n"),
              let u = URL(string: s), let scheme = u.scheme?.lowercased(),
              ["http", "https"].contains(scheme), u.host != nil
        else { return nil }
        return u
    }
}
