import Foundation
import Observation
import UIKit

// Feeds the socket and the user's actions to the Bend client, and shows
// whatever screen it answers. Runs its commands (send, copy, scroll,
// notify) and keeps the Live Activity in step with the screen's island.
@MainActor
@Observable
final class AppModel {
    private let engine = Engine()
    @ObservationIgnored private var hub: Hub?
    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private var island: IslandController?
    @ObservationIgnored private var ready = false

    private(set) var link = UserDefaults.standard.string(forKey: "link") ?? ""
    private(set) var screen: Screen?
    // the composer's text, owned here so typing never waits on Bend
    var composer = ""
    private(set) var scrolls = 0
    // the navigation stack's path: moved at once by a tap or a swipe back,
    // and by the screen only when its selection changes, so a screen that
    // answers an older action never pulls a thread back open
    private(set) var path: [String] = []
    @ObservationIgnored private var shownSel = ""
    var active = true
    // drafts sent to Bend and not yet answered: until then a screen may
    // carry an older draft than the one on screen
    @ObservationIgnored private var typing = 0
    #if DEBUG
    // headless checks: SIMCTL_CHILD_BACKPLANE_SELECT=<thread id> opens it
    @ObservationIgnored private var opening = ProcessInfo.processInfo.environment["BACKPLANE_SELECT"]
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
        if let l = ProcessInfo.processInfo.environment["BACKPLANE_LINK"] { link = l }
        #endif
        notifier.open = { [weak self] id in self?.act("select", id) }
        notifier.viewing = { [weak self] id in self?.active == true && self?.screen?.sel == id }
        let e = engine
        Task {
            apply(await e.start(Self.cid))
            ready = true
            island = IslandController { [weak self] kind, token in self?.register(kind, token) }
            connect()
            if !link.isEmpty { notifier.setUp() }
        }
        Task {
            while true {
                try? await Task.sleep(for: .seconds(30))
                if ready { apply(await e.tick(Int(Date().timeIntervalSince1970))) }
            }
        }
    }

    func pair(_ text: String) {
        link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(link, forKey: "link")
        notifier.setUp()
        connect()
    }

    // an APNs token for this device's alerts (from the app delegate)
    func registered(_ token: Data) {
        register("alert", token.map { String(format: "%02x", $0) }.joined())
    }

    private func register(_ kind: String, _ token: String) {
        let bundle = Bundle.main.bundleIdentifier ?? ""
        run { await $0.register(kind, token, env: Self.env, bundle: bundle) }
    }

    private func connect() {
        hub?.stop()
        hub = nil
        guard ready, Pairing.socket(link) != nil else { return }
        let e = engine
        let l = link
        let h = Hub(url: {
                let r = try? JSONDecoder().decode(Resume.self, from: Data(await e.resume().utf8))
                return Pairing.socket(l, since: r?.since ?? "0", origin: r?.origin ?? "")
            },
            onOpen: { [weak self] in self?.run { await $0.online(true) } },
            onMessage: { [weak self] d in self?.run { await $0.recv(d.base64EncodedString()) } },
            onClose: { [weak self] in self?.run { await $0.online(false) } })
        hub = h
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
            if s.sel != shownSel {
                shownSel = s.sel
                path = s.sel.isEmpty ? [] : [s.sel]
            }
            island?.show(s.island, foreground: active)
            #if DEBUG
            if let id = opening, s.projects.contains(where: { $0.threads.contains { $0.id == id } }) {
                opening = nil
                act("select", id)
            }
            #endif
        }
        for c in o.cmds {
            switch c.type {
            case "send": if let d = Data(base64Encoded: c.data ?? "") { hub?.send(d) }
            case "copy": UIPasteboard.general.string = c.text ?? ""
            case "scroll": scrolls += 1
            // while asleep the hub's push carries the alert instead
            case "notify": if active { notifier.post(thread: c.thread ?? "", title: c.title ?? "", body: c.body ?? "") }
            default: break
            }
        }
    }
}
