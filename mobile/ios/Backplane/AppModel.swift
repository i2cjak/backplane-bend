import Foundation
import Observation
import UIKit

// Feeds the socket and the user's actions to the Bend client, and shows
// whatever screen it answers. Runs its commands (send, copy, scroll).
@MainActor
@Observable
final class AppModel {
    private let engine = Engine()
    @ObservationIgnored private var hub: Hub?

    private(set) var link = UserDefaults.standard.string(forKey: "link") ?? ""
    private(set) var screen: Screen?
    // the composer's text, owned here so typing never waits on Bend
    var composer = ""
    private(set) var scrolls = 0
    // drafts sent to Bend and not yet answered: until then a screen may
    // carry an older draft than the one on screen
    @ObservationIgnored private var typing = 0
    #if DEBUG
    // headless checks: SIMCTL_CHILD_BACKPLANE_SELECT=<thread id> opens it
    @ObservationIgnored private var opening = ProcessInfo.processInfo.environment["BACKPLANE_SELECT"]
    #endif

    init() {
        #if DEBUG
        if let l = ProcessInfo.processInfo.environment["BACKPLANE_LINK"] { link = l }
        #endif
        Task { apply(await engine.screen()) }
        Task {
            while true {
                try? await Task.sleep(for: .seconds(30))
                apply(await engine.tick(Int(Date().timeIntervalSince1970)))
            }
        }
        connect()
    }

    func pair(_ text: String) {
        link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(link, forKey: "link")
        connect()
    }

    private func connect() {
        hub?.stop()
        hub = nil
        guard let url = Pairing.socket(link) else { return }
        let h = Hub(url: url,
            onOpen: { [weak self] in self?.run { await $0.online(true) } },
            onMessage: { [weak self] t in self?.run { await $0.recv(t) } },
            onClose: { [weak self] in self?.run { await $0.online(false) } })
        hub = h
        h.start()
    }

    private func run(_ f: @escaping (Engine) async -> String) {
        let e = engine
        Task { apply(await f(e)) }
    }

    func act(_ action: String, _ value: String = "") {
        run { await $0.act(action, value) }
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

    private func apply(_ out: String) {
        guard let o = try? JSONDecoder().decode(Out.self, from: Data(out.utf8)) else { return }
        if let s = o.screen {
            if typing == 0 { composer = s.thread?.draft ?? "" }
            screen = s
            #if DEBUG
            if let id = opening, s.projects.contains(where: { $0.threads.contains { $0.id == id } }) {
                opening = nil
                act("select", id)
            }
            #endif
        }
        for c in o.cmds {
            switch c.type {
            case "send": hub?.send(c.text ?? "")
            case "copy": UIPasteboard.general.string = c.text ?? ""
            case "scroll": scrolls += 1
            default: break
            }
        }
    }
}
