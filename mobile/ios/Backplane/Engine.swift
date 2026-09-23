import Foundation
import JavaScriptCore

// The Bend client (bridge.js) in JavaScriptCore, on one queue of its own.
// Every call answers {"screen": ..., "cmds": [...]} as a string.
final class Engine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "bend", qos: .userInitiated)
    private var ctx: JSContext?

    private func context() -> JSContext {
        if let ctx { return ctx }
        let c = JSContext()!
        c.exceptionHandler = { _, e in NSLog("bridge.js: %@", e?.toString() ?? "?") }
        let url = Bundle.main.url(forResource: "bridge", withExtension: "js")!
        c.evaluateScript(try! String(contentsOf: url, encoding: .utf8), withSourceURL: url)
        ctx = c
        return c
    }

    private func call(_ name: String, _ args: [Any]) async -> String {
        await withCheckedContinuation { k in
            queue.async {
                let b = self.context().objectForKeyedSubscript("Backplane")!
                k.resume(returning: b.invokeMethod(name, withArguments: args)?.toString() ?? "{}")
            }
        }
    }

    func screen() async -> String { await call("screen", []) }
    func recv(_ text: String) async -> String { await call("recv", [text]) }
    func act(_ action: String, _ value: String) async -> String { await call("act", [action, value]) }
    func quiet(_ action: String, _ value: String) async -> String { await call("quiet", [action, value]) }
    func online(_ b: Bool) async -> String { await call("online", [b]) }
    func tick(_ now: Int) async -> String { await call("tick", [now]) }
}
