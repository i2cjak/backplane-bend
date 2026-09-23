package dev.backplane.mobile

import org.json.JSONArray
import org.json.JSONObject

// The screen src/mobile/screen.bend emits. Plain data; no decisions.

// a swipe button: the action it sends with its value, or (a snooze)
// choices whose values it sends instead
data class Choice(val label: String, val value: String)

data class Swipe(val label: String, val action: String, val value: String, val tone: String, val options: List<Choice>)

data class Row(
    val id: String, val title: String, val state: String, val ago: String, val pinned: Boolean,
    val lead: List<Swipe>, val trail: List<Swipe>,
)

data class Project(
    val id: String, val title: String, val root: String, val open: Boolean,
    val threads: List<Row>, val snoozedShelf: String, val snoozed: List<Row>,
    val shelf: String, val settled: List<Row>,
)

// a delete a row asked for, waiting for yes ("row-delete" id) or no
data class Deleting(val id: String, val title: String, val body: String, val yes: String, val no: String)

data class Tool(val label: String, val action: String, val on: Boolean)

sealed interface Block {
    data class El(val tag: String, val kids: List<Block>) : Block
    data class Txt(val text: String) : Block
}

data class Entry(
    val id: String, val kind: String, val text: String,
    val tone: String, val label: String, val blocks: List<Block>,
)

data class ThreadView(
    val id: String, val title: String, val branch: String, val state: String,
    val tools: List<Tool>, val entries: List<Entry>, val live: List<Block>,
    val working: String, val draft: String, val send: String,
    val sending: List<String>, val queued: String,
)

data class IslandLine(val thread: String, val title: String, val doing: String)

data class Island(val running: Int, val headline: String, val lines: List<IslandLine>)

data class Screen(
    val online: Boolean, val version: String, val error: String, val note: String,
    val sel: String, val empty: String, val projects: List<Project>, val thread: ThreadView?,
    val island: Island, val deleting: Deleting?,
)

data class Cmd(
    val type: String, val text: String,
    // a "notify": the thread whose turn ended, its title, "done"/"fail", and what to say
    val thread: String = "", val title: String = "", val kind: String = "", val body: String = "",
)

// an answer from the engine: its screen (none from a quiet call, or when a
// newer one follows) and its commands
data class Reply(val screen: Screen?, val cmds: List<Cmd>)

private fun <T> JSONArray?.map(f: (JSONObject) -> T): List<T> =
    if (this == null) emptyList() else (0 until length()).map { f(getJSONObject(it)) }

private fun blocks(a: JSONArray?): List<Block> = a.map { o ->
    if (o.has("tag")) Block.El(o.getString("tag"), blocks(o.optJSONArray("kids"))) else Block.Txt(o.optString("text"))
}

private fun swipe(o: JSONObject) = Swipe(
    o.optString("label"), o.optString("action"), o.optString("value"), o.optString("tone"),
    o.optJSONArray("options").map { Choice(it.optString("label"), it.optString("value")) },
)

private fun row(o: JSONObject) = Row(
    o.optString("id"), o.optString("title"), o.optString("state"), o.optString("ago"), o.optBoolean("pinned"),
    o.optJSONArray("lead").map(::swipe), o.optJSONArray("trail").map(::swipe),
)

private fun thread(o: JSONObject) = ThreadView(
    o.optString("id"), o.optString("title"), o.optString("branch"), o.optString("state"),
    o.optJSONArray("tools").map { Tool(it.optString("label"), it.optString("action"), it.optBoolean("on")) },
    o.optJSONArray("entries").map {
        Entry(it.optString("id"), it.optString("kind"), it.optString("text"), it.optString("tone"),
            it.optString("label"), blocks(it.optJSONArray("blocks")))
    },
    blocks(o.optJSONArray("live")), o.optString("working"), o.optString("draft"), o.optString("send"),
    strs(o.optJSONArray("sending")), o.optString("queued"),
)

private fun strs(a: JSONArray?): List<String> =
    if (a == null) emptyList() else (0 until a.length()).map { a.optString(it) }

private fun island(o: JSONObject?) = Island(
    o?.optInt("running") ?: 0, o?.optString("headline") ?: "",
    o?.optJSONArray("lines").map { IslandLine(it.optString("thread"), it.optString("title"), it.optString("doing")) },
)

fun parseScreen(o: JSONObject) = Screen(
    o.optBoolean("online"), o.optString("version"), o.optString("error"), o.optString("note"),
    o.optString("sel"), o.optString("empty"),
    o.optJSONArray("projects").map {
        Project(it.optString("id"), it.optString("title"), it.optString("root"), it.optBoolean("open"),
            it.optJSONArray("threads").map(::row), it.optString("snoozedShelf"), it.optJSONArray("snoozed").map(::row),
            it.optString("shelf"), it.optJSONArray("settled").map(::row))
    },
    o.optJSONObject("thread")?.let(::thread),
    island(o.optJSONObject("island")),
    o.optJSONObject("deleting")?.let {
        Deleting(it.optString("id"), it.optString("title"), it.optString("body"), it.optString("yes"), it.optString("no"))
    },
)

fun parseCmds(o: JSONObject): List<Cmd> =
    o.optJSONArray("cmds").map {
        Cmd(it.optString("type"), it.optString("text"),
            it.optString("thread"), it.optString("title"), it.optString("kind"), it.optString("body"))
    }
