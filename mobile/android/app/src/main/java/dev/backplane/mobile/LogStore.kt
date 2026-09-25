package dev.backplane.mobile

import java.io.File

// The event frames a hub sent, kept per hub so the next launch shows the
// log at once and asks the hub only for what is new (since/origin), as
// the web client does with localStorage. One base64 frame per line: a full
// log ("reset") starts the file over, more changes ("append") add a line.
class LogStore(root: File) {
    private val dir = File(root, "logs").apply { mkdirs() }

    private fun file(key: String) = File(dir, key.replace(Regex("[^A-Za-z0-9._-]"), "_") + ".b64")

    fun load(key: String): List<String> {
        val f = file(key)
        if (!f.exists()) return emptyList()
        // too big to replay quickly: start from the hub again
        if (f.length() > MAX) { f.delete(); return emptyList() }
        return f.readLines().filter { it.isNotBlank() }
    }

    fun keep(key: String, how: String, frame: String) {
        val f = file(key)
        when (how) {
            "reset" -> f.writeText(frame + "\n")
            "append" -> if (f.exists()) f.appendText(frame + "\n")
        }
    }

    fun forget(key: String) { file(key).delete() }

    companion object { const val MAX = 48L shl 20 }
}
