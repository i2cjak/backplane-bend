package dev.backplane.mobile

import android.app.Activity
import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.util.Base64
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.security.SecureRandom

// The app's one Backplane client, alive as long as the process: the Bend
// engine, the socket, the current screen and the composer. Activities
// come and go and only observe it; the live service keeps the process
// (and so this) running while agents work.
class Core(private val app: Application) : Application.ActivityLifecycleCallbacks {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val prefs = app.getSharedPreferences("backplane", Context.MODE_PRIVATE)
    private val engine = Engine(app.assets.open("bridge.js").bufferedReader().readText(), cid())
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
    // activities started: above zero, the app is in the foreground
    private var started = 0
    val foreground get() = started > 0

    init {
        app.registerActivityLifecycleCallbacks(this)
        scope.launch { apply(engine.screen()) }
        scope.launch {
            while (true) {
                delay(30_000)
                if (foreground) apply(engine.tick(System.currentTimeMillis() / 1000))
            }
        }
        connect()
    }

    // this install's client id: 8 hex digits, made once
    private fun cid(): String =
        prefs.getString("cid", null) ?: "%08x".format(SecureRandom().nextInt()).also {
            prefs.edit().putString("cid", it).apply()
        }

    fun pair(text: String) {
        link = text.trim()
        prefs.edit().putString("link", link).apply()
        connect()
    }

    private fun connect() {
        hub?.let {
            it.stop()
            scope.launch { apply(engine.online(false)) }
        }
        hub = null
        val base = Pairing.socket(link) ?: return
        hub = Hub(scope,
            url = { Pairing.resume(base, engine.resume()) },
            onOpen = { scope.launch { apply(engine.online(true)) } },
            onMessage = { b -> scope.launch { apply(engine.recv(Base64.encodeToString(b, Base64.NO_WRAP))) } },
            onClose = { scope.launch { apply(engine.online(false)) } },
        ).also { it.start() }
    }

    fun act(action: String, value: String = "") {
        scope.launch { apply(engine.act(action, value)) }
    }

    fun draft(text: String) {
        composer = text
        typing += 1
        scope.launch {
            val out = engine.quiet("draft", text)
            typing -= 1
            apply(out)
        }
    }

    private fun apply(out: Reply) {
        out.screen?.let { next ->
            if (typing == 0) composer = next.thread?.draft ?: ""
            val was = screen?.sel
            screen = next
            if (foreground && next.sel.isNotEmpty() && next.sel != was) Notes.clear(app, next.sel)
            LiveService.sync(app, next.island, foreground)
        }
        for (c in out.cmds) when (c.type) {
            "send" -> hub?.send(Base64.decode(c.data, Base64.DEFAULT))
            "copy" -> {
                val cm = app.getSystemService(ClipboardManager::class.java)
                cm.setPrimaryClip(ClipData.newPlainText("Backplane", c.text))
            }
            "scroll" -> scrolls += 1
            "notify" -> if (!(foreground && screen?.sel == c.thread)) Notes.turn(app, c)
        }
    }

    override fun onActivityStarted(activity: Activity) {
        started += 1
        screen?.sel?.let { if (it.isNotEmpty()) Notes.clear(app, it) }
    }

    // being in front is when the live service may start
    override fun onActivityResumed(activity: Activity) {
        screen?.let { LiveService.sync(app, it.island, true) }
    }

    override fun onActivityStopped(activity: Activity) {
        started = maxOf(0, started - 1)
    }

    override fun onActivityCreated(activity: Activity, state: Bundle?) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
}

class BackplaneApp : Application() {
    val core by lazy { Core(this) }

    override fun onCreate() {
        super.onCreate()
        Notes.channels(this)
        core
    }
}

val Context.core: Core get() = (applicationContext as BackplaneApp).core
