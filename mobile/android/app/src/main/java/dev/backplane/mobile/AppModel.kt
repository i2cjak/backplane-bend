package dev.backplane.mobile

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

// Feeds the socket and the user's actions to the Bend client, and shows
// whatever screen it answers. Runs its commands (send, copy, scroll).
class AppModel(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("backplane", Context.MODE_PRIVATE)
    private val engine = Engine(app.assets.open("bridge.js").bufferedReader().readText())
    private var hub: Hub? = null

    var link by mutableStateOf(prefs.getString("link", "") ?: "")
        private set
    var screen by mutableStateOf<Screen?>(null)
        private set
    // the composer's text, owned here so typing never waits on Bend
    var composer by mutableStateOf("")
        private set
    var scrolls by mutableIntStateOf(0)
        private set
    // drafts sent to Bend and not yet answered: until then a screen may
    // carry an older draft than the one on screen
    private var typing = 0

    init {
        viewModelScope.launch { apply(engine.screen()) }
        viewModelScope.launch {
            while (true) {
                delay(30_000)
                apply(engine.tick(System.currentTimeMillis() / 1000))
            }
        }
        connect()
    }

    fun pair(text: String) {
        link = text.trim()
        prefs.edit().putString("link", link).apply()
        connect()
    }

    private fun connect() {
        hub?.stop()
        hub = null
        val url = Pairing.socket(link) ?: return
        hub = Hub(url,
            onOpen = { viewModelScope.launch { apply(engine.online(true)) } },
            onMessage = { t -> viewModelScope.launch { apply(engine.recv(t)) } },
            onClose = { viewModelScope.launch { apply(engine.online(false)) } },
        ).also { it.start() }
    }

    fun act(action: String, value: String = "") {
        viewModelScope.launch { apply(engine.act(action, value)) }
    }

    fun draft(text: String) {
        composer = text
        typing += 1
        viewModelScope.launch {
            val out = engine.quiet("draft", text)
            typing -= 1
            apply(out)
        }
    }

    private fun apply(out: String) {
        val o = JSONObject(out)
        o.optJSONObject("screen")?.let { s ->
            val next = parseScreen(s)
            if (typing == 0) composer = next.thread?.draft ?: ""
            screen = next
        }
        for (c in parseCmds(o)) when (c.type) {
            "send" -> hub?.send(c.text)
            "copy" -> {
                val cm = getApplication<Application>().getSystemService(ClipboardManager::class.java)
                cm.setPrimaryClip(ClipData.newPlainText("Backplane", c.text))
            }
            "scroll" -> scrolls += 1
        }
    }

    override fun onCleared() {
        hub?.stop()
    }
}
