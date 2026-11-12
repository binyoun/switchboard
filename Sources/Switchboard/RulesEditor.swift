import AppKit
import SwiftUI
import SwitchboardCore

/// Editable copy of the config. Nothing touches the file until Save.
final class EditorModel: ObservableObject {
    struct ProfileRow: Identifiable {
        let profile: Profile
        var aliases: String          // comma-separated
        var id: String { profile.ref }
    }
    struct RuleRow: Identifiable {
        let id = UUID()
        var match: String
        var from: String
        var open: String             // a profile ref, or the raw text if no profile matches
    }
    struct Suggestion: Identifiable {
        let host: String
        let count: Int
        var picked: Bool
        var id: String { host }
    }

    @Published var profiles: [ProfileRow] = []
    @Published var rules: [RuleRow] = []
    @Published var fallback = ""
    @Published var hotkey = ""
    @Published var testLink = ""
    @Published var testFrom = ""
    @Published var suggestFor = ""
    @Published var suggestions: [Suggestion] = []
    @Published var suggestionsLoaded = false
    @Published var message = ""

    private var saved = Data()
    var onSaved: (() -> Void)?

    func load() {
        let config = (try? Config.load()) ?? Config()
        let found = ProfileDiscovery.all()
        let router = Router(config: config, profiles: found)
        profiles = found.map { ProfileRow(profile: $0, aliases: config.aliases(for: $0).joined(separator: ", ")) }
        rules = config.rules.map {
            RuleRow(match: $0.match ?? "", from: $0.from ?? "",
                    open: (try? router.profile(named: $0.open))?.ref ?? $0.open)
        }
        fallback = config.fallback.flatMap { try? router.profile(named: $0) }?.ref ?? (config.fallback ?? "")
        hotkey = config.hotkey ?? ""
        if suggestFor.isEmpty { suggestFor = found.first(where: { $0.browser == .edge })?.ref ?? found.first?.ref ?? "" }
        suggestions = []
        suggestionsLoaded = false
        saved = encoded(toConfig())
        message = ""
    }

    func toConfig() -> Config {
        var c = Config()
        for row in profiles {
            for a in row.aliases.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !a.isEmpty {
                c.aliases[a] = row.profile.ref
            }
        }
        func target(_ ref: String) -> String {
            guard let p = profiles.first(where: { $0.profile.ref == ref })?.profile else { return ref }
            return c.name(for: p)
        }
        c.rules = rules.map {
            let m = $0.match.trimmingCharacters(in: .whitespaces)
            let f = $0.from.trimmingCharacters(in: .whitespaces)
            return Rule(match: m.isEmpty ? nil : m, from: f.isEmpty ? nil : f, open: target($0.open))
        }
        c.fallback = fallback.isEmpty ? nil : target(fallback)
        let h = hotkey.trimmingCharacters(in: .whitespaces)
        c.hotkey = h.isEmpty ? nil : h
        return c
    }

    private func encoded(_ c: Config) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(c)) ?? Data()
    }

    var isDirty: Bool { encoded(toConfig()) != saved }

    var hotkeyValid: Bool {
        hotkey.trimmingCharacters(in: .whitespaces).isEmpty || Hotkey(hotkey) != nil
    }

    func save() {
        do {
            try toConfig().save()
            saved = encoded(toConfig())
            message = "Saved."
            onSaved?()
        } catch {
            message = "Could not save: \(error.localizedDescription)"
        }
    }

    // Rules

    func addRule() {
        rules.append(RuleRow(match: "", from: "", open: fallback.isEmpty ? (profiles.first?.profile.ref ?? "") : fallback))
    }

    func move(_ id: UUID, by delta: Int) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard rules.indices.contains(j) else { return }
        rules.swapAt(i, j)
    }

    func remove(_ id: UUID) { rules.removeAll { $0.id == id } }

    /// Every profile, plus any rule target that no longer matches one (shown as missing).
    var targets: [String] {
        let refs = profiles.map(\.profile.ref)
        let unknown = Set(rules.map(\.open) + [fallback]).subtracting(refs).filter { !$0.isEmpty }
        return refs + unknown.sorted()
    }

    func label(_ ref: String) -> String {
        guard let row = profiles.first(where: { $0.profile.ref == ref }) else { return "⚠︎ missing: \(ref)" }
        let alias = row.aliases.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let name = alias.isEmpty ? row.profile.name : alias
        return "\(name) · \(row.profile.browser.name)"
    }

    // Testing

    var testResult: String {
        let s = testLink.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return "" }
        guard let url = URL(string: s.contains("://") ? s : "https://" + s), url.host != nil else { return "Not a link" }
        let from = testFrom.trimmingCharacters(in: .whitespaces)
        let source = from.isEmpty ? nil : Source(bundleID: from, name: from)
        let router = Router(config: toConfig(), profiles: profiles.map(\.profile))
        do {
            let p = try router.route(url, from: source)
            let why = router.matchingRule(for: url, from: source).map { "rule \($0.display)" } ?? "fallback"
            let real = Unwrap.destination(of: url).host ?? ""
            let via = real != url.host ? ", real destination \(real)" : ""
            return "→ \(p.name) · \(p.browser.name)   (\(why)\(via))"
        } catch {
            return "→ asks you (\(error))"
        }
    }

    // Suggestions from bookmarks

    func findSuggestions() {
        guard let p = profiles.first(where: { $0.profile.ref == suggestFor })?.profile else { return }
        let router = Router(config: toConfig(), profiles: profiles.map(\.profile))
        suggestions = Bookmarks.hosts(for: p)
            .filter { host, _ in
                guard let u = URL(string: "https://\(host)/") else { return false }
                return (try? router.route(u))?.ref != p.ref     // only sites that would go elsewhere now
            }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(60)
            .map { Suggestion(host: $0.key, count: $0.value, picked: false) }
        suggestionsLoaded = true
    }

    func addPickedSuggestions() {
        let hosts = suggestions.filter(\.picked).map(\.host)
        guard !hosts.isEmpty else { return }
        var c = toConfig()
        let p = profiles.first { $0.profile.ref == suggestFor }!.profile
        c.addHostRules(hosts, open: c.name(for: p))
        let router = Router(config: c, profiles: profiles.map(\.profile))
        rules = c.rules.map {
            RuleRow(match: $0.match ?? "", from: $0.from ?? "",
                    open: (try? router.profile(named: $0.open))?.ref ?? $0.open)
        }
        suggestions.removeAll(where: \.picked)
        message = "Added \(hosts.count) rule\(hosts.count == 1 ? "" : "s") — Save to keep them."
    }
}

struct EditorView: View {
    @ObservedObject var m: EditorModel
    let openFile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    profilesSection
                    rulesSection
                    testSection
                    suggestSection
                }
                .padding(22)
            }
            Divider()
            HStack {
                Text(m.message).foregroundColor(.secondary)
                Spacer()
                Button("Open Config File", action: openFile)
                Button("Revert") { m.load() }.disabled(!m.isDirty)
                Button("Save") { m.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!m.isDirty || !m.hotkeyValid)
            }
            .padding(12)
        }
        .frame(minWidth: 780, minHeight: 620)
    }

    private func header(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(note).font(.system(size: 12)).foregroundColor(.secondary)
        }
    }

    // MARK: profiles

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Profiles", "Short names for rules, the picker and `sb`. Separate several with commas.")
            ForEach($m.profiles) { $row in
                HStack(spacing: 12) {
                    Image(nsImage: Avatar.image(row.profile, size: 26))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(row.profile.name) · \(row.profile.browser.name)").font(.system(size: 13, weight: .medium))
                        Text(row.profile.email ?? row.profile.ref).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    .frame(width: 280, alignment: .leading)
                    TextField("alias", text: $row.aliases).frame(width: 200)
                    Spacer()
                }
            }
            HStack(spacing: 18) {
                HStack {
                    Text("Anything else opens in")
                    Picker("", selection: $m.fallback) {
                        Text("Ask me").tag("")
                        ForEach(m.targets, id: \.self) { Text(m.label($0)).tag($0) }
                    }
                    .labelsHidden().frame(width: 200)
                }
                HStack {
                    Text("Picker shortcut")
                    TextField(Config.defaultHotkey, text: $m.hotkey).frame(width: 150)
                    if !m.hotkeyValid {
                        Text("e.g. ctrl+option+b").foregroundColor(.red).font(.system(size: 11))
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Rules", "Checked top to bottom; the first rule whose conditions all hold decides. Site: example.com, or *.example.com for every subdomain. App: bundle ID or name.")
            HStack(spacing: 8) {
                Text("#").frame(width: 24, alignment: .trailing)
                Text("Site").frame(width: 230, alignment: .leading)
                Text("Clicked in app").frame(width: 190, alignment: .leading)
                Text("Opens in").frame(width: 180, alignment: .leading)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)

            ForEach(Array(m.rules.enumerated()), id: \.element.id) { i, rule in
                RuleRowView(m: m, index: i, id: rule.id)
            }
            Button("Add Rule") { m.addRule() }
        }
    }

    // MARK: test

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Test a link", "Uses the rules above, saved or not.")
            HStack {
                TextField("Paste a link", text: $m.testLink).frame(width: 420)
                TextField("clicked in app (optional)", text: $m.testFrom).frame(width: 220)
            }
            Text(m.testResult).font(.system(size: 13, design: .monospaced))
        }
    }

    // MARK: suggestions

    private var suggestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Suggest rules from bookmarks", "Sites bookmarked in a profile that currently open somewhere else. Tick the ones that belong there.")
            HStack {
                Picker("", selection: $m.suggestFor) {
                    ForEach(m.profiles) { Text("\($0.profile.name) · \($0.profile.browser.name)").tag($0.profile.ref) }
                }
                .labelsHidden().frame(width: 220)
                Button("Find Sites") { m.findSuggestions() }
                if m.suggestions.contains(where: \.picked) {
                    Button("Add \(m.suggestions.filter(\.picked).count) Rules") { m.addPickedSuggestions() }
                }
            }
            if m.suggestionsLoaded && m.suggestions.isEmpty {
                Text("Every bookmarked site already opens in this profile.").foregroundColor(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach($m.suggestions) { $s in
                    Toggle(isOn: $s.picked) {
                        Text(s.host) + Text("  \(s.count)").foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

/// One rule, looked up by id so edits and moves never touch a stale index.
private struct RuleRowView: View {
    @ObservedObject var m: EditorModel
    let index: Int
    let id: UUID

    private var binding: Binding<EditorModel.RuleRow> {
        Binding(
            get: { m.rules.first { $0.id == id } ?? EditorModel.RuleRow(match: "", from: "", open: "") },
            set: { new in if let i = m.rules.firstIndex(where: { $0.id == id }) { m.rules[i] = new } })
    }

    var body: some View {
        let rule = binding.wrappedValue
        let empty = rule.match.trimmingCharacters(in: .whitespaces).isEmpty
            && rule.from.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(spacing: 8) {
            Text("\(index + 1)").foregroundColor(.secondary).frame(width: 24, alignment: .trailing)
            TextField("any site", text: binding.match).frame(width: 230)
            TextField("any app", text: binding.from).frame(width: 190)
            Picker("", selection: binding.open) {
                ForEach(m.targets, id: \.self) { Text(m.label($0)).tag($0) }
            }
            .labelsHidden().frame(width: 180)
            Button { m.move(id, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(index == 0)
            Button { m.move(id, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(index == m.rules.count - 1)
            Button { m.remove(id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
            if empty {
                Text("never matches").font(.system(size: 11)).foregroundColor(.orange)
            }
        }
    }
}

final class EditorWindowController {
    private var window: NSWindow?
    let model = EditorModel()

    func show(onSaved: @escaping () -> Void, openFile: @escaping () -> Void) {
        model.onSaved = onSaved
        if window == nil || !(window?.isVisible ?? false) { model.load() }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 720),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "Switchboard Rules"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: EditorView(m: model, openFile: openFile))
            w.center()
            w.setFrameAutosaveName("SwitchboardRules")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
