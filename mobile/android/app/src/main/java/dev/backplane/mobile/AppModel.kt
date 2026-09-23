package dev.backplane.mobile

import android.app.Application
import androidx.lifecycle.AndroidViewModel

// The screen's view of the app's one client (Core): reads its state and
// passes the user's actions through. Holds nothing of its own.
class AppModel(app: Application) : AndroidViewModel(app) {
    private val core = app.core

    val link get() = core.link
    val screen get() = core.screen
    val composer get() = core.composer
    val scrolls get() = core.scrolls

    fun pair(text: String) = core.pair(text)
    fun act(action: String, value: String = "") = core.act(action, value)
    fun draft(text: String) = core.draft(text)
}
