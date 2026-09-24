import Foundation
import Observation
import UIKit

// Feeds every paired hub's socket and the user's actions to the Bend
// client, and shows whatever screen it answers. Runs its commands (send,
// copy, scroll, notify) and keeps the Live Activity in step with the
// screen's island. Each hub is keyed by its host:port (Pairing.key).
@MainActor
@Observable
final class AppModel {
    private let engine = Engine()
    @ObservationIgnored private var hubs: [String: Hub] = [:]
    // push tokens by kind, sent again to a hub paired later
    @ObservationIgnored private var tokens: [String: String] = [:]
    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private var island: IslandController?
    @ObservationIgnored private var ready = false

    // the pairing links, one per hub, in the order they were paired
    private(set) var links: [String] = UserDefaults.standard.stringArray(forKey: "links")
        ?? UserDefaults.standard.string(forKey: "link").map { [$0] } ?? []
    private(set) var screen: Screen?
    // the board viewer's plots, which come straight from the socket
    let plots = PlotStore()
    // the composer's text, owned here so typing never waits on Bend
    var composer = ""
    private(set) var scrolls = 0
    // the navigation stack's path: moved at once by a tap or a swipe back,
    // and by the screen only when its selection changes, so a screen that
    // answers an older action never pulls a thread back open
    private(set) var path: [String] = []
    @ObservationIgnored private var shownSel = ""
    // the hub whose plots are drawn: frames from any other are dropped
    @ObservationIgnored private var shownHub = ""
    var active = true
    // drafts sent to Bend and not yet answered: until then a screen may
    // carry an older draft than the one on screen
    @ObservationIgnored private var typing = 0
    #if DEBUG
    // headless checks: SIMCTL_CHILD_BACKPLANE_SELECT=<thread id> opens it
    @ObservationIgnored private var opening = ProcessInfo.processInfo.environment["BACKPLANE_SELECT"]
    // and SIMCTL_CHILD_BACKPLANE_VIEW=board (or schematic) opens its viewer
    @ObservationIgnored private var viewing = ProcessInfo.processInfo.environment["BACKPLANE_VIEW"]
    #endif

    // this install's id, part of every message id (a resend is stored once)
    private static var cid: String {
        if let c = UserDefaults.standard.string(forKey: "cid") { return c }
        let c = String(format: "%08x", UInt32.random(in: 0 ... UInt32.max))
        UserDefaults.standard.set(c, forKey: "cid")
        return c
    }

    private static var env: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    init() {
        #if DEBUG
        if let l = ProcessInfo.processInfo.environment["BACKPLANE_LINK"] { links = l.split(separator: " ").map(String.init) }
        #endif
        notifier.open = { [weak self] id in self?.act("select", id) }
        notifier.viewing = { [weak self] id in self?.active == true && self?.screen?.sel == id }
        let e = engine
        Task {
            apply(await e.start(Self.cid))
            ready = true
            island = IslandController { [weak self] kind, token in self?.register(kind, token) }
            connect()
            #if DEBUG
            // headless checks pair from the environment: no permission prompt over the screen
            if ProcessInfo.processInfo.environment["BACKPLANE_LINK"] == nil, !links.isEmpty { notifier.setUp() }
            #else
            if !links.isEmpty { notifier.setUp() }
            #endif
        }
        Task {
            while true {
                try? await Task.sleep(for: .seconds(30))
                if ready { apply(await e.tick(Int(Date().timeIntervalSince1970))) }
            }
        }
    }

    // a new hub, or a new link to one already paired (it replaces the old)
    func pair(_ text: String) {
        let l = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let k = Pairing.key(l) else { return }
        links = links.filter { Pairing.key($0) != k } + [l]
        save()
        notifier.setUp()
        connect()
    }

    func unpair(_ key: String) {
        links = links.filter { Pairing.key($0) != key }
        save()
        connect()
    }

    private func save() {
        UserDefaults.standard.set(links, forKey: "links")
        UserDefaults.standard.removeObject(forKey: "link")
    }

    // an APNs token for this device's alerts (from the app delegate)
    func registered(_ token: Data) {
        register("alert", token.map { String(format: "%02x", $0) }.joined())
    }

    private func register(_ kind: String, _ token: String) {
        tokens[kind] = token
        let bundle = Bundle.main.bundleIdentifier ?? ""
        run { await $0.register(kind, token, env: Self.env, bundle: bundle) }
    }

    // one socket per paired hub: new hubs connect, unpaired ones hang up
    private func connect() {
        guard ready else { return }
        var keyed: [String: String] = [:]
        var keys: [String] = []
        for l in links {
            if let k = Pairing.key(l), keyed[k] == nil { keyed[k] = l; keys.append(k) }
        }
        for (k, h) in hubs where keyed[k] == nil {
            h.stop()
            hubs[k] = nil
        }
        let e = engine
        let fresh = keys.contains { hubs[$0] == nil }
        Task {
            apply(await e.hubs(keys))
            for (k, l) in keyed where hubs[k] == nil { open(k, l) }
            // a hub paired later learns this phone's push tokens too
            if fresh { for (kind, token) in tokens { register(kind, token) } }
        }
    }

    private func open(_ key: String, _ link: String) {
        let e = engine
        let h = Hub(url: {
                let r = try? JSONDecoder().decode(Resume.self, from: Data(await e.resume(key).utf8))
                return Pairing.socket(link, since: r?.since ?? "0", origin: r?.origin ?? "")
            },
            onOpen: { [weak self] in
                if self?.shownHub == key { self?.plots.reset() }
                self?.run { await $0.online(key, true) }
            },
            // plots go straight to the viewer, never through the Bend client,
            // and only the hub in focus draws
            onMessage: { [weak self] d in
                if PlotStore.isPlot(d) {
                    if self?.shownHub == key { self?.plots.receive(d) }
                } else {
                    self?.run { await $0.recv(key, d.base64EncodedString()) }
                }
            },
            onClose: { [weak self] in self?.run { await $0.online(key, false) } })
        hubs[key] = h
        h.start()
    }

    private func run(_ f: @escaping (Engine) async -> Out?) {
        let e = engine
        Task { apply(await f(e)) }
    }

    func act(_ action: String, _ value: String = "") {
        run { await $0.act(action, value) }
    }

    func navigate(_ p: [String]) {
        path = p
        act("select", p.last ?? "")
    }

    func draft(_ text: String) {
        composer = text
        typing += 1
        let e = engine
        Task {
            let out = await e.quiet("draft", text)
            typing -= 1
            apply(out)
        }
    }

    // a URL the app was opened with: a pairing link, or a thread to show
    func open(_ url: URL) {
        guard url.scheme == "backplane" else { return }
        if url.host == "open" {
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "thread" }?.value ?? ""
            if !id.isEmpty { act("select", id) }
        } else {
            pair(url.absoluteString)
        }
    }

    func foreground(_ yes: Bool) {
        active = yes
        if yes, let s = screen { island?.show(s.island, foreground: true) }
    }

    private func apply(_ out: Out?) {
        guard let o = out else { return }
        if let s = o.screen {
            if typing == 0 { composer = s.thread?.draft ?? "" }
            screen = s
            if s.hub != shownHub {
                shownHub = s.hub
                plots.reset()
            }
            if s.sel != shownSel {
                shownSel = s.sel
                path = s.sel.isEmpty ? [] : [s.sel]
            }
            island?.show(s.island, foreground: active)
            #if DEBUG
            if let id = opening, let row = s.projects.lazy.flatMap(\.threads).first(where: { $0.id == id || $0.id.hasSuffix("|" + id) }) {
                opening = nil
                act("select", row.id)
            }
            if opening == nil, let v = viewing, let t = s.thread, !t.viewer.choices.isEmpty {
                viewing = nil
                act("view", v)
            }
            #endif
        }
        for c in o.cmds {
            switch c.type {
            case "send": if let d = Data(base64Encoded: c.data ?? "") { hubs[c.hub ?? ""]?.send(d) }
            case "copy": UIPasteboard.general.string = c.text ?? ""
            case "scroll": scrolls += 1
            // while asleep the hub's push carries the alert instead
            case "notify": if active { notifier.post(thread: c.thread ?? "", title: c.title ?? "", body: c.body ?? "") }
            default: break
            }
        }
    }
}
