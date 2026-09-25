import Foundation

// The event frames a hub sent, kept per hub so the next launch shows the
// log at once and asks the hub only for what is new (since/origin), as
// the web client does with localStorage. One base64 frame per line: a full
// log ("reset") starts the file over, more changes ("append") add a line.
struct LogStore {
    static let max = 48 << 20

    private var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func file(_ key: String) -> URL {
        let safe = String(key.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" ? $0 : "_" })
        return dir.appendingPathComponent(safe + ".b64")
    }

    func load(_ key: String) -> [String] {
        let f = file(key)
        guard let a = try? FileManager.default.attributesOfItem(atPath: f.path), let n = a[.size] as? Int else { return [] }
        // too big to replay quickly: start from the hub again
        if n > Self.max { try? FileManager.default.removeItem(at: f); return [] }
        guard let text = try? String(contentsOf: f, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    func keep(_ key: String, _ how: String, _ frame: String) {
        let f = file(key)
        let line = Data((frame + "\n").utf8)
        switch how {
        case "reset":
            try? line.write(to: f, options: .atomic)
        case "append":
            if let h = try? FileHandle(forWritingTo: f) {
                h.seekToEndOfFile()
                h.write(line)
                try? h.close()
            }
        default:
            break
        }
    }

    func forget(_ key: String) { try? FileManager.default.removeItem(at: file(key)) }
}
