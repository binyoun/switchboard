import Foundation

/// ~/Library/Logs/Switchboard.log — one line per routed link, so a wrong route can be traced
/// to the rule that caused it. Records the host only, never the full address.
enum LinkLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Switchboard.log")

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ line: String) {
        let text = formatter.string(from: Date()) + "  " + line + "\n"
        let fm = FileManager.default
        // Keep it small: start again past 512 KB.
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 512_000 {
            try? fm.removeItem(at: url)
        }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(text.data(using: .utf8)!)
            try? h.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
