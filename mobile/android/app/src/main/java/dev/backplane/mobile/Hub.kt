package dev.backplane.mobile

import android.net.Uri
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import org.json.JSONObject
import java.util.concurrent.TimeUnit

// A pairing link as the desktop shows it (http://host:3787/#token=abc)
// becomes the hub's socket address (ws://host:3787/ws?token=abc).
object Pairing {
    fun socket(link: String): String? {
        var s = link.trim()
        if (s.isEmpty()) return null
        if (s.startsWith("backplane://")) s = Uri.parse(s).getQueryParameter("url") ?: return null
        if (!s.contains("://")) s = "http://$s"
        val u = Uri.parse(s)
        val host = u.host ?: return null
        val token = Regex("token=([0-9a-f]+)").find(u.fragment ?: u.query ?: "")?.groupValues?.get(1)
        val scheme = if (u.scheme == "https") "wss" else "ws"
        val port = if (u.port > 0) ":${u.port}" else ""
        return "$scheme://$host$port/ws" + (token?.let { "?token=$it" } ?: "")
    }

    // the socket address for a (re)connect: the client's resume point
    // ({"since", "origin"} from Backplane.resume()) as query parameters
    fun resume(socket: String, resume: String): String {
        val r = JSONObject(resume)
        return Uri.parse(socket).buildUpon()
            .appendQueryParameter("since", r.optString("since", "0"))
            .appendQueryParameter("origin", r.optString("origin", ""))
            // a hub from before CBOR-only still needs asking
            .appendQueryParameter("enc", "cbor")
            .build().toString()
    }
}

// The socket to the hub, reconnecting with backoff like host.js. The
// address is asked for afresh on every attempt, so each reconnect resumes
// from what the client already holds.
class Hub(
    private val scope: CoroutineScope,
    private val url: suspend () -> String?,
    private val onOpen: () -> Unit,
    private val onMessage: (ByteArray) -> Unit,
    private val onClose: () -> Unit,
) {
    private val client = OkHttpClient.Builder().pingInterval(20, TimeUnit.SECONDS).build()
    private val main = Handler(Looper.getMainLooper())
    private var socket: WebSocket? = null
    private var backoff = 250L
    private var stopped = false

    fun start() {
        stopped = false
        connect()
    }

    fun stop() {
        stopped = true
        socket?.close(1000, null)
        socket = null
    }

    fun send(bytes: ByteArray) {
        socket?.send(bytes.toByteString())
    }

    private fun connect() {
        if (stopped) return
        scope.launch {
            val u = url()
            if (!stopped && u != null) open(u)
        }
    }

    private fun open(u: String) {
        client.newWebSocket(Request.Builder().url(u).build(), object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                main.post {
                    if (stopped) {
                        ws.close(1000, null)
                    } else {
                        socket = ws
                        backoff = 250
                        onOpen()
                    }
                }
            }

            // every frame is binary CBOR, both ways
            override fun onMessage(ws: WebSocket, bytes: ByteString) {
                val b = bytes.toByteArray()
                main.post { if (!stopped && socket === ws) onMessage(b) }
            }

            override fun onClosed(ws: WebSocket, code: Int, reason: String) = lost(ws)
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) = lost(ws)
        })
    }

    private fun lost(ws: WebSocket) {
        main.post {
            if (stopped) {
                if (socket === ws) socket = null
            } else if (socket === ws || socket == null) {
                socket = null
                onClose()
                main.postDelayed({ connect() }, backoff)
                backoff = minOf(backoff * 2, 5000)
            }
        }
    }
}
