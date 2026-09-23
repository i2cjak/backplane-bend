package dev.backplane.mobile

import android.Manifest
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import android.os.Build

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()
    private val ask = registerForActivityResult(ActivityResultContracts.RequestPermission()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        pairFrom(intent)
        if (savedInstanceState == null) threadFrom(intent)
        setContent {
            // once paired, ask to post alerts
            LaunchedEffect(model.link.isNotEmpty()) { if (model.link.isNotEmpty()) askNotify() }
            Theme { App(model) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        pairFrom(intent)
        threadFrom(intent)
    }

    // a tapped alert opens its thread
    private fun threadFrom(intent: Intent?) {
        val id = intent?.getStringExtra(Notes.EXTRA_THREAD) ?: return
        intent.removeExtra(Notes.EXTRA_THREAD)
        model.act("select", id)
    }

    private fun askNotify() {
        if (Build.VERSION.SDK_INT < 33 || Notes.allowed(this)) return
        val prefs = getSharedPreferences("backplane", MODE_PRIVATE)
        if (prefs.getBoolean("asked-notify", false)) return
        prefs.edit().putBoolean("asked-notify", true).apply()
        ask.launch(Manifest.permission.POST_NOTIFICATIONS)
    }

    // backplane://pair?url=... opens straight into that hub
    private fun pairFrom(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme == "backplane") model.pair(data.toString())
    }
}

@Composable
fun Theme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val ctx = LocalContext.current
    val scheme = when {
        Build.VERSION.SDK_INT >= 31 -> if (dark) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
        dark -> darkColorScheme()
        else -> lightColorScheme()
    }
    MaterialTheme(colorScheme = scheme, content = content)
}
