package dev.backplane.mobile

import org.json.JSONArray
import org.json.JSONObject

// The screen src/mobile/screen.bend emits. Plain data; no decisions.

// a swipe button: the action it sends with its value, or (a snooze)
// choices whose values it sends instead
data class SwipeChoice(val label: String, val value: String)

data class Swipe(val label: String, val action: String, val value: String, val tone: String, val options: List<SwipeChoice>)

data class Row(
    val id: String, val title: String, val state: String, val ago: String, val pinned: Boolean,
    val lead: List<Swipe>, val trail: List<Swipe>,
)

// machine: the hub it is on, named when the phone has several
data class Project(
    val id: String, val title: String, val root: String, val machine: String, val open: Boolean,
    val threads: List<Row>, val snoozedShelf: String, val snoozed: List<Row>,
    val shelf: String, val settled: List<Row>,
)

// a delete a row asked for, waiting for yes ("row-delete" id) or no
data class Deleting(val id: String, val title: String, val body: String, val yes: String, val no: String)

// the project picker: its path field, the field's hint, an error, and the
// rows (a tap sends action with value; one with no action is only shown)
data class FolderRow(val label: String, val action: String, val value: String, val kind: String)

data class Folders(val text: String, val hint: String, val error: String, val items: List<FolderRow>)

data class Tool(val label: String, val action: String, val on: Boolean)

sealed interface Block {
    data class El(val tag: String, val kids: List<Block>) : Block
    data class Txt(val text: String) : Block
}

data class Entry(
    val id: String, val kind: String, val text: String,
    val tone: String, val label: String, val blocks: List<Block>,
)

// the board viewer (src/mobile/view.bend): the source open ("" closed),
// the key its plots carry, the choices, and how to draw
data class Choice(val label: String, val value: String, val on: Boolean)

// a tapped item's card: its kind, then key = value rows, and the info
// "Mention in chat" puts in the draft
data class Card(val info: String, val title: String, val rows: List<Pair<String, String>>)

// also: the key of the plot it draws layers from, how far a tap reaches
// (dp), the layers a 3D view lays on the board's top and bottom faces, the
// board's colour before its model arrives, the field of view, the piece
// picked ("chunk,info" of the held chunks) and its card
data class Viewer(
    val open: String, val key: String, val layers: String, val choices: List<Choice>, val bg: Int, val fade: Float,
    val margin: Float, val zmin: Float, val zmax: Float, val tap: Float, val top: IntArray, val bottom: IntArray,
    val slab: Int, val fov: Float, val picked: String, val card: Card?,
)

// the composer's model chip: its label, the models ("model" sends one)
// and the efforts the current one takes ("effort")
data class ModelPicker(val label: String, val models: List<Choice>, val efforts: List<Choice>)

// a message waiting in the thread's queue and its buttons (each sends
// action with value)
data class QButton(val label: String, val action: String, val value: String)
data class QueueRow(val msg: String, val text: String, val tag: String, val buttons: List<QButton>)

data class ThreadView(
    val id: String, val title: String, val branch: String, val state: String,
    val tools: List<Tool>, val entries: List<Entry>, val live: List<Block>,
    val working: String, val draft: String, val send: String,
    val sending: List<String>, val queued: String, val picker: ModelPicker, val viewer: Viewer,
    val queue: List<QueueRow> = emptyList(),
)

data class IslandLine(val thread: String, val title: String, val doing: String)

data class Island(val running: Int, val headline: String, val lines: List<IslandLine>)

// a paired hub (key: its host:port), and a machine a hub knows of that
// this phone is not paired with yet
data class HubRow(val key: String, val name: String, val online: Boolean)

data class Found(val name: String, val url: String)

// hub: the one in focus (its thread is shown, its plots are drawn)
data class Screen(
    val online: Boolean, val version: String, val error: String, val note: String,
    val sel: String, val empty: String, val projects: List<Project>, val thread: ThreadView?,
    val island: Island, val deleting: Deleting?, val folders: Folders?,
    val hub: String, val hubs: List<HubRow>, val found: List<Found>,
)

data class Cmd(
    val type: String, val text: String,
    // a "send": the CBOR frame, as base64, for the hub keyed hub
    val data: String = "", val hub: String = "",
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
    o.optJSONArray("options").map { SwipeChoice(it.optString("label"), it.optString("value")) },
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
    strs(o.optJSONArray("sending")), o.optString("queued"), picker(o.optJSONObject("picker") ?: JSONObject()),
    viewer(o.optJSONObject("viewer") ?: JSONObject()),
    o.optJSONArray("queue").map {
        QueueRow(it.optString("msg"), it.optString("text"), it.optString("tag"),
            it.optJSONArray("buttons").map { b -> QButton(b.optString("label"), b.optString("action"), b.optString("value")) })
    },
)

private fun choices(a: JSONArray?) = a.map { Choice(it.optString("label"), it.optString("value"), it.optBoolean("on")) }

private fun picker(o: JSONObject) =
    ModelPicker(o.optString("label"), choices(o.optJSONArray("models")), choices(o.optJSONArray("efforts")))

private fun ints(a: JSONArray?): IntArray = if (a == null) IntArray(0) else IntArray(a.length()) { a.optInt(it) }

private fun viewer(o: JSONObject) = Viewer(
    o.optString("open"), o.optString("key"), o.optString("layers"),
    o.optJSONArray("choices").map { Choice(it.optString("label"), it.optString("value"), it.optBoolean("on")) },
    o.optInt("bg"), o.optDouble("fade", 220.0).toFloat(), o.optDouble("margin", 0.9).toFloat(),
    o.optDouble("zmin", 0.5).toFloat(), o.optDouble("zmax", 0.5).toFloat(), o.optDouble("tap", 14.0).toFloat(),
    ints(o.optJSONArray("top")), ints(o.optJSONArray("bottom")), o.optInt("slab"), o.optDouble("fov", 35.0).toFloat(),
    o.optString("picked"),
    o.optJSONObject("card")?.let { c ->
        Card(c.optString("info"), c.optString("title"), c.optJSONArray("rows").map { it.optString("k") to it.optString("v") })
    },
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
        Project(it.optString("id"), it.optString("title"), it.optString("root"), it.optString("machine"), it.optBoolean("open"),
            it.optJSONArray("threads").map(::row), it.optString("snoozedShelf"), it.optJSONArray("snoozed").map(::row),
            it.optString("shelf"), it.optJSONArray("settled").map(::row))
    },
    o.optJSONObject("thread")?.let(::thread),
    island(o.optJSONObject("island")),
    o.optJSONObject("deleting")?.let {
        Deleting(it.optString("id"), it.optString("title"), it.optString("body"), it.optString("yes"), it.optString("no"))
    },
    o.optJSONObject("folders")?.let { p ->
        Folders(p.optString("text"), p.optString("hint"), p.optString("error"),
            p.optJSONArray("items").map { FolderRow(it.optString("label"), it.optString("action"), it.optString("value"), it.optString("kind")) })
    },
    o.optString("hub"),
    o.optJSONArray("hubs").map { HubRow(it.optString("key"), it.optString("name"), it.optBoolean("online")) },
    o.optJSONArray("found").map { Found(it.optString("name"), it.optString("url")) },
)

fun parseCmds(o: JSONObject): List<Cmd> =
    o.optJSONArray("cmds").map {
        Cmd(it.optString("type"), it.optString("text"), it.optString("data"), it.optString("hub"),
            it.optString("thread"), it.optString("title"), it.optString("kind"), it.optString("body"))
    }
