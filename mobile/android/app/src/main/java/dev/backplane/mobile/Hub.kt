package dev.backplane.mobile

import android.net.Uri
import android.os.Handler
import android.os.Looper
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit

// A pairing link as the desktop shows it (http://host:3773/#token=abc)
// becomes the hub's socket address (ws://host:3773/ws?token=abc).
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
}

// The socket to the hub, reconnecting with backoff like host.js.
class Hub(
    private val url: String,
    private val onOpen: () -> Unit,
    private val onMessage: (String) -> Unit,
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

    fun send(text: String) {
        socket?.send(text)
    }

    private fun connect() {
        if (stopped) return
        client.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                main.post {
                    socket = ws
                    backoff = 250
                    onOpen()
                }
            }

            override fun onMessage(ws: WebSocket, text: String) {
                main.post { onMessage(text) }
            }

            override fun onClosed(ws: WebSocket, code: Int, reason: String) = lost(ws)
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) = lost(ws)
        })
    }

    private fun lost(ws: WebSocket) {
        main.post {
            if (socket === ws || socket == null) {
                socket = null
                onClose()
                if (!stopped) main.postDelayed({ connect() }, backoff)
                backoff = minOf(backoff * 2, 5000)
            }
        }
    }
}
