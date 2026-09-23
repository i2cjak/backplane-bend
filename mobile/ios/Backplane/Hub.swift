import Foundation

// A pairing link as the desktop shows it (http://host:3773/#token=abc)
// becomes the hub's socket address (ws://host:3773/ws?token=abc).
enum Pairing {
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
    private let url: URL
    private let onOpen: () -> Void
    private let onMessage: (String) -> Void
    private let onClose: () -> Void
    private var task: URLSessionWebSocketTask?
    private var backoff: Double = 0.25
    private var stopped = false
    private var generation = 0

    init(url: URL, onOpen: @escaping () -> Void, onMessage: @escaping (String) -> Void, onClose: @escaping () -> Void) {
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

    func send(_ text: String) {
        task?.send(.string(text)) { _ in }
    }

    private func connect() {
        guard !stopped else { return }
        generation += 1
        let gen = generation
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        // the first message proves the socket is up (the hub greets at once)
        read(t, gen, first: true)
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
                    if case .string(let s) = m { self.onMessage(s) }
                    if case .data(let d) = m, let s = String(data: d, encoding: .utf8) { self.onMessage(s) }
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
