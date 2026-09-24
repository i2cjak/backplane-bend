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

    // calls queued whose answer carries a screen: while one is, the screen
    // before it is out of date before it could be drawn, so it is skipped
    private let lock = NSLock()
    private var ahead = 0

    private func call<T>(_ name: String, _ args: [Any], _ finish: @escaping (String) -> T) async -> T {
        await withCheckedContinuation { k in
            queue.async {
                let b = self.context().objectForKeyedSubscript("Backplane")!
                k.resume(returning: finish(b.invokeMethod(name, withArguments: args)?.toString() ?? "{}"))
            }
        }
    }

    // decoded here, off the main thread: a thread's screen is large
    private func out(_ name: String, _ args: [Any], screen: Bool = true) async -> Out? {
        if screen { lock.withLock { ahead += 1 } }
        return await call(name, args) { text in
            let stale = screen && self.lock.withLock { self.ahead -= 1; return self.ahead > 0 }
            return Out.decode(text, screen: !stale)
        }
    }

    func start(_ cid: String, _ drafts: String) async -> Out? { await out("start", [cid, drafts]) }
    func hubs(_ keys: [String]) async -> Out? { await out("hubs", [keys]) }
    func resume(_ key: String) async -> String { await call("resume", [key]) { $0 } }
    func register(_ kind: String, _ token: String, env: String, bundle: String) async -> Out? {
        await out("register", ["ios", token, kind, "", env, bundle], screen: false)
    }
    func screen() async -> Out? { await out("screen", []) }
    func recv(_ key: String, _ text: String) async -> Out? { await out("recv", [key, text]) }
    func act(_ action: String, _ value: String) async -> Out? { await out("act", [action, value]) }
    func quiet(_ action: String, _ value: String) async -> Out? { await out("quiet", [action, value], screen: false) }
    func online(_ key: String, _ b: Bool) async -> Out? { await out("online", [key, b]) }
    func tick(_ now: Int) async -> Out? { await out("tick", [now]) }
    // a cat's rig for its key ("look:mood")
    func cat(_ key: String) async -> String { await call("cat", [key]) { $0 } }
}
