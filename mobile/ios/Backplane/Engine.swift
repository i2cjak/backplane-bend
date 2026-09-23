import Foundation
import JavaScriptCore

// One thread with a deep stack: the hub's log arrives as one message and
// Bend walks it recursively. A dispatch queue's 512 KB overflows on a real
// log, the call throws, and the app keeps its empty first screen.
private final class Worker: Thread, @unchecked Sendable {
    private let cond = NSCondition()
    private var jobs: [() -> Void] = []

    override init() {
        super.init()
        name = "bend"
        stackSize = 64 << 20
        qualityOfService = .userInitiated
        start()
    }

    func async(_ f: @escaping () -> Void) {
        cond.lock()
        jobs.append(f)
        cond.signal()
        cond.unlock()
    }

    override func main() {
        while true {
            cond.lock()
            while jobs.isEmpty { cond.wait() }
            let f = jobs.removeFirst()
            cond.unlock()
            f()
        }
    }
}

// The Bend client (bridge.js) in JavaScriptCore, on one thread of its own.
// Every call answers {"screen": ..., "cmds": [...]} as a string.
final class Engine: @unchecked Sendable {
    private let queue = Worker()
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

    func start(_ cid: String) async -> String { await call("start", [cid]) }
    func resume() async -> String { await call("resume", []) }
    func register(_ kind: String, _ token: String, env: String, bundle: String) async -> String {
        await call("register", ["ios", token, kind, "", env, bundle])
    }
    func screen() async -> String { await call("screen", []) }
    func recv(_ text: String) async -> String { await call("recv", [text]) }
    func act(_ action: String, _ value: String) async -> String { await call("act", [action, value]) }
    func quiet(_ action: String, _ value: String) async -> String { await call("quiet", [action, value]) }
    func online(_ b: Bool) async -> String { await call("online", [b]) }
    func tick(_ now: Int) async -> String { await call("tick", [now]) }
}
