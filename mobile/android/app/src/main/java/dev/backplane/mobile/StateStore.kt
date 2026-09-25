package dev.backplane.mobile

import java.io.File

// The Bend client's whole state (Backplane.save()), kept between launches:
// loading it shows every hub's log at once, where folding the log again in
// QuickJS took seconds, and each hub then sends only what came since. The
// file is named for the Bend types the state is made of (bridge.js ends
// with their hash, scripts/state-key.py): a new build with the same types
// keeps it, one with other types starts afresh rather than load a state it
// may not read. A bridge.js without the key names it by its whole text.
class StateStore(root: File, bridge: String) {
    private val file = File(root, Regex("BackplaneStateKey = \"([0-9a-f]+)\"").find(bridge)?.let { "state-${it.groupValues[1]}.json" }
        ?: "state-%08x-%d.json".format(bridge.hashCode(), bridge.length))

    init {
        // states kept by earlier builds, and the frame logs of an older one
        root.listFiles { f -> f.name.startsWith("state-") && f.name != file.name }?.forEach { it.delete() }
        File(root, "logs").deleteRecursively()
    }

    fun load(): String? = if (file.exists()) file.readText().takeIf { it.isNotEmpty() } else null

    fun save(text: String) {
        if (text.isEmpty()) return
        val tmp = File(file.path + ".tmp")
        tmp.writeText(text)
        tmp.renameTo(file)
    }
}
