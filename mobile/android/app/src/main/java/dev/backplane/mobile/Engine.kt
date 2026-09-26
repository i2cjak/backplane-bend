package dev.backplane.mobile

import com.whl.quickjs.android.QuickJSLoader
import com.whl.quickjs.wrapper.QuickJSContext
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

// A JavaScript runtime the Bend client runs in: evaluate an expression,
// answer its value as a string.
interface Js {
    fun evaluate(expr: String): String
}

// QuickJS, in this process: an interpreter, everywhere, and slow (a tap's
// screen took ~130 ms on an emulator, several times that on a phone)
class QuickJs(private val c: QuickJSContext) : Js {
    override fun evaluate(expr: String): String = c.evaluate(expr) as String
}

// V8 from the system WebView, in its sandbox process (androidx
// javascriptengine): the same client compiled, over ten times faster.
// Calls cross IPC, whose transactions are limited in size unless the
// WebView lifts the limit: then the source goes in and long answers come
// back in slices through globals.
class V8Js(private val iso: androidx.javascriptengine.JavaScriptIsolate, private val big: Boolean) : Js {
    private fun run(code: String): String = iso.evaluateJavaScriptAsync(code).get()

    // text into the global __s, slice by slice
    private fun push(text: String) {
        run("globalThis.__s = ''")
        var i = 0
        while (i < text.length) {
            run("__s += ${JSONObject.quote(text.substring(i, minOf(i + SLICE, text.length)))}")
            i += SLICE
        }
    }

    override fun evaluate(expr: String): String {
        if (big) return run("String($expr)")
        val n = if (expr.length <= SLICE) run("globalThis.__r = String($expr); String(__r.length)").toInt()
        else { push(expr); run("globalThis.__r = String((0, eval)(__s)); __s = ''; String(__r.length)").toInt() }
        if (n <= SLICE) return run("__r")
        val sb = StringBuilder(n)
        var i = 0
        while (i < n) { sb.append(run("__r.slice($i, ${i + SLICE})")); i += SLICE }
        run("__r = ''")
        return sb.toString()
    }

    // a script too long for one transaction goes in as string slices
    fun load(source: String) {
        if (big) { run(source); return }
        push(source)
        run("(0, eval)(__s); __s = ''")
    }

    companion object {
        const val SLICE = 200_000

        // V8 when the device's WebView offers the sandbox, else null
        fun open(app: android.content.Context, source: String): V8Js? = runCatching {
            if (!androidx.javascriptengine.JavaScriptSandbox.isSupported()) return null
            val sb = androidx.javascriptengine.JavaScriptSandbox.createConnectedInstanceAsync(app).get()
            val params = androidx.javascriptengine.IsolateStartupParameters()
            if (sb.isFeatureSupported(androidx.javascriptengine.JavaScriptSandbox.JS_FEATURE_ISOLATE_MAX_HEAP_SIZE))
                params.maxHeapSizeBytes = 768L shl 20
            val iso = sb.createIsolate(params)
            val big = sb.isFeatureSupported(androidx.javascriptengine.JavaScriptSandbox.JS_FEATURE_EVALUATE_WITHOUT_TRANSACTION_LIMIT)
            V8Js(iso, big).also { it.load(source) }
        }.onFailure { android.util.Log.w("Backplane", "V8 sandbox unavailable: $it") }.getOrNull()
    }
}

// The Bend client (bridge.js) on one thread of its own: in V8 where the
// WebView offers it, else in QuickJS.
// Every call answers {"screen": ..., "cmds": [...]} as a string, except
// resume(), which answers {"since": "<n>", "origin": "<o>"}. The client is
// started with this install's id and its kept drafts before anything
// else runs.
// The bridge is compiled to QuickJS bytecode once per build and kept in
// dir: parsing and compiling 1.3 MB of JavaScript took half a second at
// every launch.
class Engine(private val app: android.content.Context, private val source: String, private val cid: String, private val drafts: String, private val dir: java.io.File) {
    private val thread = Executors.newSingleThreadExecutor { Thread(null, it, "bend", 64L shl 20) }
    private val dispatcher = thread.asCoroutineDispatcher()
    private var ctx: Js? = null

    private fun context(): Js =
        ctx ?: run {
            val t0 = android.os.SystemClock.elapsedRealtime()
            val js: Js = V8Js.open(app, source) ?: run {
                QuickJSLoader.init()
                QuickJSContext.create().let {
                    it.setMaxStackSize(48 shl 20)
                    load(it)
                    QuickJs(it)
                }
            }
            android.util.Log.i("Backplane", "engine ${js.javaClass.simpleName} in ${android.os.SystemClock.elapsedRealtime() - t0} ms")
            js.evaluate("Backplane.start(${q(cid)}, ${q(drafts)})")
            ctx = js
            js
        }

    // the bridge from its kept bytecode, else compiled now and kept (a
    // bytecode file of another build, or one that fails, is dropped)
    private fun load(c: QuickJSContext) {
        val name = "bridge-%08x-%d.qjs".format(source.hashCode(), source.length)
        dir.listFiles { f -> f.name.startsWith("bridge-") && f.name != name }?.forEach { it.delete() }
        val kept = java.io.File(dir, name)
        if (kept.exists() && runCatching { c.execute(kept.readBytes()) }.isSuccess) return
        kept.delete()
        val code = runCatching { c.compile(source, "bridge.js") }.getOrNull()
        if (code == null) { c.evaluate(source, "bridge.js"); return }
        c.execute(code)
        runCatching { java.io.File(dir, "$name.tmp").also { it.writeBytes(code) }.renameTo(kept) }
    }

    // calls queued whose answer carries a screen: while one is, the screen
    // before it is out of date before it could be drawn, so it is skipped
    private val ahead = AtomicInteger(0)

    private suspend fun call(expr: String): String =
        withContext(dispatcher) { context().evaluate(expr) }

    // parsed here, off the main thread: a thread's screen is large.
    // behind: the call to make instead when newer calls wait behind this
    // one (its screen would be dropped anyway)
    private suspend fun out(expr: String, screen: Boolean = true, behind: String? = null): Reply {
        if (screen) ahead.incrementAndGet()
        return withContext(dispatcher) {
            val e = if (behind != null && ahead.get() > 1) behind else expr
            val t0 = android.os.SystemClock.elapsedRealtime()
            val text = context().evaluate(e)
            val ms = android.os.SystemClock.elapsedRealtime() - t0
            // a slow step of the Bend client, for finding what to make faster
            if (ms > 100) android.util.Log.i("Backplane", "slow ${e.substringBefore('(')}: $ms ms")
            val o = JSONObject(text)
            val stale = screen && ahead.decrementAndGet() > 0
            Reply(if (stale) null else o.optJSONObject("screen")?.let(::parseScreen), parseCmds(o))
        }
    }

    private fun q(s: String) = JSONObject.quote(s)

    // the paired hubs' keys, in order
    suspend fun hubs(keys: List<String>) = out("Backplane.hubs(${org.json.JSONArray(keys)})")
    suspend fun resume(key: String) = call("Backplane.resume(${q(key)})")
    suspend fun screen() = out("Backplane.screen()")
    // a binary frame from hub key, as base64
    suspend fun recv(key: String, data: String) =
        out("Backplane.recv(${q(key)}, ${q(data)})", behind = "Backplane.recv(${q(key)}, ${q(data)}, true)")
    // the whole client state as text (StateStore), and the state loaded back
    suspend fun save() = call("Backplane.save()")
    suspend fun load(text: String) = out("Backplane.load(${q(text)})")
    suspend fun act(action: String, value: String) = out("Backplane.act(${q(action)}, ${q(value)})")
    suspend fun quiet(action: String, value: String) = out("Backplane.quiet(${q(action)}, ${q(value)})", screen = false)
    suspend fun online(key: String, b: Boolean) = out("Backplane.online(${q(key)}, $b)")
    // a hub marked offline with no screen of its own (after load())
    suspend fun offline(key: String) = out("Backplane.online(${q(key)}, false, true)", screen = false)
    suspend fun tick(now: Long) = out("Backplane.tick($now)")
    // a cat's rig (JSON text) for its key ("look:mood")
    suspend fun cat(key: String) = call("Backplane.cat(${q(key)})")
}
