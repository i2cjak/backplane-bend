import Foundation

// A pairing link as the desktop shows it (http://host:3787/#token=abc)
// becomes the hub's socket address (ws://host:3787/ws?token=abc).
enum Pairing {
    // the socket address, resuming from since/origin
    static func socket(_ link: String, since: String, origin: String) -> URL? {
        guard let u = socket(link), var c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return nil }
        // enc=cbor: a hub from before CBOR-only still needs asking
        c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "since", value: since), URLQueryItem(name: "origin", value: origin),
                                               URLQueryItem(name: "enc", value: "cbor")]
        return c.url
    }

    // the hub's key: host:port, the same for every link to it
    static func key(_ link: String) -> String? {
        guard let u = socket(link), let host = u.host() else { return nil }
        return u.port.map { "\(host):\($0)" } ?? host
    }

    static func socket(_ link: String) -> URL? {
        var s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if s.hasPrefix("backplane://") {
            guard let q = URLComponents(string: s)?.queryItems?.first(where: { $0.name == "url" })?.value else { return nil }
            s = q
        }
        if !s.contains("://") { s = "http://" + s }
        guard let u = URLComponents(string: s), let host = u.host else { return nil }
        let rest = (u.fragment ?? "") + "&" + (u.query ?? "")
        let token = rest.range(of: "token=[0-9a-f]+", options: .regularExpression).map { String(rest[$0].dropFirst(6)) }
        var w = URLComponents()
        w.scheme = u.scheme == "https" ? "wss" : "ws"
        w.host = host
        w.port = u.port
        w.path = "/ws"
        if let token { w.queryItems = [URLQueryItem(name: "token", value: token)] }
        return w.url
    }
}

// The socket to the hub, reconnecting with backoff like host.js.
@MainActor
final class Hub {
    // the address for each (re)connect: it carries since/origin, so the
    // hub sends only what this app has not seen
    private let url: () async -> URL?
    private let onOpen: () -> Void
    private let onMessage: (Data) -> Void
    private let onClose: () -> Void
    private var task: URLSessionWebSocketTask?
    private var backoff: Double = 0.25
    private var stopped = false
    private var generation = 0

    init(url: @escaping () async -> URL?, onOpen: @escaping () -> Void, onMessage: @escaping (Data) -> Void, onClose: @escaping () -> Void) {
        self.url = url
        self.onOpen = onOpen
        self.onMessage = onMessage
        self.onClose = onClose
    }

    func start() {
        stopped = false
        connect()
    }

    func stop() {
        stopped = true
        generation += 1
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    // every frame is binary CBOR, both ways
    func send(_ data: Data) {
        task?.send(.data(data)) { _ in }
    }

    private func connect() {
        guard !stopped else { return }
        generation += 1
        let gen = generation
        Task {
            guard let u = await url(), gen == generation, !stopped else { return }
            let t = URLSession.shared.webSocketTask(with: u)
            task = t
            t.resume()
            // the first message proves the socket is up (the hub greets at once)
            read(t, gen, first: true)
        }
    }

    private func read(_ t: URLSessionWebSocketTask, _ gen: Int, first: Bool) {
        t.receive { [weak self] r in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                switch r {
                case .success(let m):
                    if first {
                        self.backoff = 0.25
                        self.onOpen()
                    }
                    if case .data(let d) = m { self.onMessage(d) }
                    self.read(t, gen, first: false)
                case .failure:
                    self.lost()
                }
            }
        }
    }

    private func lost() {
        task = nil
        generation += 1
        onClose()
        guard !stopped else { return }
        let wait = backoff
        backoff = min(backoff * 2, 5)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.connect() }
    }
}
