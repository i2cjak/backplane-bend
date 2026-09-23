package dev.backplane.mobile

import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Callable
import java.util.concurrent.Executors

// Plots from the hub (src/core/plot.bend) as GPU-ready geometry. Nothing
// is decided here: which chunks, their order, colour and opacity come from
// the hub, the fade and zoom range from the screen. A plot lists each
// chunk as the index of one this app holds (the last plot applied) or the
// chunk itself; applying it is Plot.apply (law plot_delta_exact), so
// `held` always mirrors what the hub thinks this connection holds.

// One chunk, decoded once: capsules (ax ay bx by r, micrometres; a dot is
// a capsule of no length) and fill triangles (x y, three per triangle).
class PlotChunk(val layer: Int, val color: Int, val alpha: Float) {
    var caps = FloatArray(0)
    var tris = FloatArray(0)

    companion object {
        // "d": 6-bit digits (base64url), 5 bits each, low first; bit 5 set
        // while more follow. Numbers are zigzag deltas (Enc.pts)
        fun numbers(d: String): IntArray {
            val out = IntArray(d.length)
            var n = 0
            var acc = 0
            var sh = 0
            for (ch in d) {
                val c = ch.code
                val v = when (c) {
                    in 65..90 -> c - 65
                    in 97..122 -> c - 71
                    in 48..57 -> c + 4
                    45 -> 62
                    else -> 63
                }
                acc = acc or ((v and 31) shl sh)
                if (v >= 32) sh += 5 else { out[n++] = acc; acc = 0; sh = 0 }
            }
            return out.copyOf(n)
        }

        private fun unzig(z: Int) = (z ushr 1) xor -(z and 1)

        fun decode(o: JSONObject): PlotChunk {
            val c = PlotChunk(o.optInt("l"), o.optInt("c"), o.optInt("a", 255) / 255f)
            val mode = o.optInt("m", 1)
            val r = o.optInt("w") / 2f
            val ns = numbers(o.optString("d"))
            val caps = Floats()
            val tris = Floats()
            var i = 0
            var px = 0
            var py = 0
            if (mode == 2) {
                while (i + 1 < ns.size) {
                    px += unzig(ns[i]); py += unzig(ns[i + 1]); i += 2
                    caps.add(px.toFloat(), py.toFloat(), px.toFloat(), py.toFloat(), r)
                }
            } else {
                while (i < ns.size) {
                    val n = ns[i++]
                    val pts = FloatArray(n * 2)
                    var k = 0
                    while (k < n && i + 1 < ns.size) {
                        px += unzig(ns[i]); py += unzig(ns[i + 1]); i += 2
                        pts[2 * k] = px.toFloat(); pts[2 * k + 1] = py.toFloat()
                        k++
                    }
                    if (mode == 0) fan(pts, k, tris) else path(pts, k, r, caps)
                }
            }
            c.caps = caps.array()
            c.tris = tris.array()
            return c
        }

        private fun path(p: FloatArray, n: Int, r: Float, caps: Floats) {
            if (n == 1) { caps.add(p[0], p[1], p[0], p[1], r); return }
            for (k in 1 until n) caps.add(p[2 * k - 2], p[2 * k - 1], p[2 * k], p[2 * k + 1], r)
        }

        // a polygon as a triangle fan, turned counter-clockwise, so the
        // stencil's winding count fills every polygon of a layer as one union
        private fun fan(p: FloatArray, n: Int, tris: Floats) {
            if (n < 3) return
            var area = 0f
            for (k in 0 until n) {
                val j = (k + 1) % n
                area += p[2 * k] * p[2 * j + 1] - p[2 * j] * p[2 * k + 1]
            }
            for (k in 1 until n - 1) {
                val a = if (area >= 0) k else k + 1
                val b = if (area >= 0) k + 1 else k
                tris.add(p[0], p[1], p[2 * a], p[2 * a + 1], p[2 * b], p[2 * b + 1])
            }
        }
    }
}

class Floats {
    private var a = FloatArray(64)
    var size = 0
        private set

    fun add(vararg xs: Float) {
        if (size + xs.size > a.size) a = a.copyOf(maxOf(a.size * 2, size + xs.size))
        for (x in xs) a[size++] = x
    }

    fun addAll(xs: FloatArray) {
        if (size + xs.size > a.size) a = a.copyOf(maxOf(a.size * 2, size + xs.size))
        System.arraycopy(xs, 0, a, size, xs.size)
        size += xs.size
    }

    fun array(): FloatArray = a.copyOf(size)
}

// What the renderer draws: the chunks in paint order and which of them
// just arrived (they fade in), the box for the first view, or why there
// is nothing to draw.
class PlotFrame(
    val key: String, val box: FloatArray, val chunks: List<PlotChunk>, val fresh: Set<Int>,
    val none: String, val at: Long,
)

class PlotStore {
    var frame by mutableStateOf<PlotFrame?>(null)
        private set
    private var held: List<PlotChunk> = emptyList()
    private var generation = 0
    private val main = Handler(Looper.getMainLooper())
    // one plot at a time, in arrival order; its new chunks decode side by side
    private val queue = Executors.newSingleThreadExecutor()
    private val pool = Executors.newFixedThreadPool(maxOf(2, Runtime.getRuntime().availableProcessors() - 1))

    // a new connection holds nothing
    fun reset() {
        generation += 1
        held = emptyList()
        frame = null
    }

    fun receive(text: String) {
        val gen = generation
        queue.execute {
            val o = runCatching { JSONObject(text) }.getOrNull() ?: return@execute
            val key = o.optString("key")
            if (o.has("none")) {
                val why = o.optString("none")
                main.post {
                    if (gen != generation) return@post
                    held = emptyList()
                    frame = PlotFrame(key, FloatArray(0), emptyList(), emptySet(), why, System.currentTimeMillis())
                }
                return@execute
            }
            val refs: JSONArray = o.optJSONArray("cs") ?: JSONArray()
            val jobs = (0 until refs.length()).mapNotNull { i ->
                refs.optJSONObject(i)?.let { obj -> i to Callable { PlotChunk.decode(obj) } }
            }
            val done = pool.invokeAll(jobs.map { it.second })
            val decoded = HashMap<Int, PlotChunk>()
            jobs.forEachIndexed { k, (i, _) -> decoded[i] = done[k].get() }
            val b = o.optJSONArray("box")
            val box = FloatArray(b?.length() ?: 0) { b!!.optDouble(it).toFloat() }
            // the main thread keeps arrival order: each plot applies to the one before
            main.post {
                if (gen != generation) return@post
                val all = ArrayList<PlotChunk>(refs.length())
                for (i in 0 until refs.length()) {
                    val c = decoded[i] ?: refs.optInt(i, -1).let { k -> held.getOrNull(k) }
                    if (c != null) all.add(c)
                }
                held = all
                frame = PlotFrame(key, box, all, decoded.keys, "", System.currentTimeMillis())
            }
        }
    }

    companion object {
        // a plot frame: JSON text beginning so (PL.Plot.prefix); every other
        // frame is CBOR, which never begins with '{'
        private val prefix = "{\"t\":\"plot\"".toByteArray(Charsets.UTF_8)

        fun isPlot(b: ByteArray) = b.size >= prefix.size && (prefix.indices).all { b[it] == prefix[it] }
    }
}
