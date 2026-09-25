import Foundation

// The Bend client's whole state (Backplane.save()), kept between launches:
// loading it shows every hub's log at once instead of folding it again,
// and each hub then sends only what came since. The file is named for the
// Bend types the state is made of (bridge.js ends with their hash,
// scripts/state-key.py): a new build with the same types keeps it, one
// with other types starts afresh rather than load a state it may not read.
// A bridge.js without the key names it by its whole text.
struct StateStore {
    private let dir: URL
    private let name: String

    init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let src = (try? Data(contentsOf: Bundle.main.url(forResource: "bridge", withExtension: "js")!)) ?? Data()
        if let key = StateStore.key(src) {
            name = "state-\(key).json"
        } else {
            var h: UInt64 = 1469598103934665603
            for b in src { h = (h ^ UInt64(b)) &* 1099511628211 }
            name = String(format: "state-%016llx.json", h)
        }
        // states kept by earlier builds, and the frame logs of an older one
        let fm = FileManager.default
        for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasPrefix("state-") && f != name {
            try? fm.removeItem(at: dir.appendingPathComponent(f))
        }
        try? fm.removeItem(at: dir.appendingPathComponent("logs"))
    }

    // the key bridge.js ends with (globalThis.BackplaneStateKey = "…")
    private static func key(_ src: Data) -> String? {
        let tail = String(decoding: src.suffix(200), as: UTF8.self)
        guard let r = tail.range(of: "BackplaneStateKey = \"") else { return nil }
        let key = tail[r.upperBound...].prefix { $0.isHexDigit }
        return key.isEmpty ? nil : String(key)
    }

    func load() -> String? {
        guard let t = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8), !t.isEmpty else { return nil }
        return t
    }

    func save(_ text: String) {
        guard !text.isEmpty else { return }
        try? Data(text.utf8).write(to: dir.appendingPathComponent(name), options: .atomic)
    }
}
