package dev.backplane.mobile

import com.whl.quickjs.android.QuickJSLoader
import com.whl.quickjs.wrapper.QuickJSContext
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

// The Bend client (bridge.js) in QuickJS, on one thread of its own.
// Every call answers {"screen": ..., "cmds": [...]} as a string, except
// resume(), which answers {"since": "<n>", "origin": "<o>"}. The client is
// started with this install's id and its kept drafts before anything
// else runs.
class Engine(private val source: String, private val cid: String, private val drafts: String) {
    private val thread = Executors.newSingleThreadExecutor { Thread(null, it, "bend", 64L shl 20) }
    private val dispatcher = thread.asCoroutineDispatcher()
    private var ctx: QuickJSContext? = null

    private fun context(): QuickJSContext =
        ctx ?: run {
            QuickJSLoader.init()
            QuickJSContext.create().also {
                it.setMaxStackSize(48 shl 20)
                it.evaluate(source, "bridge.js")
                it.evaluate("Backplane.start(${q(cid)}, ${q(drafts)})")
                ctx = it
            }
        }

    // calls queued whose answer carries a screen: while one is, the screen
    // before it is out of date before it could be drawn, so it is skipped
    private val ahead = AtomicInteger(0)

    private suspend fun call(expr: String): String =
        withContext(dispatcher) { context().evaluate(expr) as String }

    // parsed here, off the main thread: a thread's screen is large
    private suspend fun out(expr: String, screen: Boolean = true): Reply {
        if (screen) ahead.incrementAndGet()
        return withContext(dispatcher) {
            val o = JSONObject(context().evaluate(expr) as String)
            val stale = screen && ahead.decrementAndGet() > 0
            Reply(if (stale) null else o.optJSONObject("screen")?.let(::parseScreen), parseCmds(o), o.optString("keep", ""))
        }
    }

    private fun q(s: String) = JSONObject.quote(s)

    // the paired hubs' keys, in order
    suspend fun hubs(keys: List<String>) = out("Backplane.hubs(${org.json.JSONArray(keys)})")
    suspend fun resume(key: String) = call("Backplane.resume(${q(key)})")
    suspend fun screen() = out("Backplane.screen()")
    // a binary frame from hub key, as base64
    suspend fun recv(key: String, data: String) = out("Backplane.recv(${q(key)}, ${q(data)})")
    // hub key's kept frames (base64), replayed at launch before its socket
    suspend fun replay(key: String, frames: List<String>) = out("Backplane.replay(${q(key)}, ${org.json.JSONArray(frames)})")
    suspend fun act(action: String, value: String) = out("Backplane.act(${q(action)}, ${q(value)})")
    suspend fun quiet(action: String, value: String) = out("Backplane.quiet(${q(action)}, ${q(value)})", screen = false)
    suspend fun online(key: String, b: Boolean) = out("Backplane.online(${q(key)}, $b)")
    suspend fun tick(now: Long) = out("Backplane.tick($now)")
    // a cat's rig (JSON text) for its key ("look:mood")
    suspend fun cat(key: String) = call("Backplane.cat(${q(key)})")
}
