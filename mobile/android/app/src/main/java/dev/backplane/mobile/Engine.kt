package dev.backplane.mobile

import com.whl.quickjs.android.QuickJSLoader
import com.whl.quickjs.wrapper.QuickJSContext
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.concurrent.Executors

// The Bend client (bridge.js) in QuickJS, on one thread of its own.
// Every call answers {"screen": ..., "cmds": [...]} as a string, except
// resume(), which answers {"since": "<n>", "origin": "<o>"}. The client is
// started with this install's id before anything else runs.
class Engine(private val source: String, private val cid: String) {
    private val thread = Executors.newSingleThreadExecutor { Thread(null, it, "bend", 64L shl 20) }
    private val dispatcher = thread.asCoroutineDispatcher()
    private var ctx: QuickJSContext? = null

    private fun context(): QuickJSContext =
        ctx ?: run {
            QuickJSLoader.init()
            QuickJSContext.create().also {
                it.setMaxStackSize(48 shl 20)
                it.evaluate(source, "bridge.js")
                it.evaluate("Backplane.start(${q(cid)})")
                ctx = it
            }
        }

    private suspend fun call(expr: String): String =
        withContext(dispatcher) { context().evaluate(expr) as String }

    private fun q(s: String) = JSONObject.quote(s)

    suspend fun resume() = call("Backplane.resume()")
    suspend fun screen() = call("Backplane.screen()")
    suspend fun recv(text: String) = call("Backplane.recv(${q(text)})")
    suspend fun act(action: String, value: String) = call("Backplane.act(${q(action)}, ${q(value)})")
    suspend fun quiet(action: String, value: String) = call("Backplane.quiet(${q(action)}, ${q(value)})")
    suspend fun online(b: Boolean) = call("Backplane.online($b)")
    suspend fun tick(now: Long) = call("Backplane.tick($now)")
}
