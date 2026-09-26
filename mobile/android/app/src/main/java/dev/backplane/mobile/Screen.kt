package dev.backplane.mobile

import org.json.JSONArray
import org.json.JSONObject

// The screen src/mobile/screen.bend emits. Plain data; no decisions.

// a swipe button: the action it sends with its value, or (a snooze)
// choices whose values it sends instead
data class SwipeChoice(val label: String, val value: String)

data class Swipe(val label: String, val action: String, val value: String, val tone: String, val options: List<SwipeChoice>)

// status: what its dot says (approval, input, working, failed, queued, ready)
data class Row(
    val id: String, val title: String, val state: String, val ago: String, val pinned: Boolean,
    val lead: List<Swipe>, val trail: List<Swipe>, val status: String = "",
)

// machine: the hub it is on, named when the phone has several
data class Project(
    val id: String, val title: String, val root: String, val machine: String, val open: Boolean,
    val threads: List<Row>, val snoozedShelf: String, val snoozed: List<Row>,
    val shelf: String, val settled: List<Row>,
    // the Archived shelf: "toggle-settled" with value opens or shuts it
    val value: String = "", val archOpen: Boolean = false, val archived: List<Row> = emptyList(),
)

// a delete a row asked for, waiting for yes ("row-delete" id) or no
data class Deleting(val id: String, val title: String, val body: String, val yes: String, val no: String)

// the project search over the list: open, its query ("proj-find-q"), the hint
data class Search(val open: Boolean, val query: String, val hint: String)

// the project picker: its path field, the field's hint, an error, and the
// rows (a tap sends action with value; one with no action is only shown)
data class FolderRow(val label: String, val action: String, val value: String, val kind: String)

data class Folders(val text: String, val hint: String, val error: String, val items: List<FolderRow>)

// a toolbar or menu item: it sends action with value, or (a snooze)
// offers choices whose values it sends instead; danger asks first
data class Tool(
    val label: String, val action: String, val on: Boolean,
    val value: String = "", val danger: Boolean = false, val options: List<SwipeChoice> = emptyList(),
)

sealed interface Block {
    data class El(val tag: String, val kids: List<Block>) : Block
    data class Txt(val text: String) : Block
}

// an attachment of a user message (url: where its hub serves it)
data class Chip(val label: String, val path: String, val image: Boolean, val url: String)

// an image a reply names
data class Shot(val path: String, val url: String)

// kind: user, assistant, act (a tool line), fold (a run of tool calls:
// "fold" with value opens or shuts it), link (opens thread value)
data class Entry(
    val id: String, val kind: String, val text: String,
    val tone: String, val label: String, val blocks: List<Block>,
    val attachments: List<Chip> = emptyList(), val images: List<Shot> = emptyList(),
    val open: Boolean = false, val value: String = "",
)

// what the agent waits on the user for: an approval, a question or a
// plan; each button sends "answer" with its value
data class AskButton(val label: String, val value: String, val primary: Boolean)
data class Ask(val id: String, val kind: String, val head: String, val detail: String, val blocks: List<Block>, val buttons: List<AskButton>)

// a thread this one delegated to ("select" opens it)
data class TaskRow(val id: String, val who: String, val title: String, val state: String)

// a skill the `$` being typed may complete to ("skill" with its name)
data class Skill(val name: String, val desc: String)

// what the thread changed: k 0 context, 1 added, 2 removed, 3 meta, 4 a hunk head
data class DiffLine(val k: Int, val t: String, val o: String, val n: String)
data class DiffFile(val name: String, val status: String, val lines: List<DiffLine>)
data class Diff(val summary: String, val files: List<DiffFile>)

// the thread's shell: rows of styled runs (colours 0xRRGGBB) and the cursor
data class TermRun(val t: String, val fg: Int, val bg: Int, val b: Boolean, val u: Boolean)
data class TermCursor(val x: Int, val y: Int, val on: Boolean)
data class Term(val title: String, val fg: Int, val bg: Int, val lines: List<List<TermRun>>, val cursor: TermCursor)

// settings: rows of a label, a note and buttons (each sends action with value)
data class SetButton(val label: String, val action: String, val value: String, val on: Boolean)
data class SetRow(val label: String, val note: String, val buttons: List<SetButton>)
data class Settings(val rows: List<SetRow>)

// thread search ("search") or the file picker ("files"): its query and rows
data class Find(val mode: String, val query: String, val rows: List<FolderRow>)

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
    // the viewer's own light ground, and each layer's colour on it (by layer)
    val light: Boolean = false, val look: IntArray = IntArray(0),
    // the schematic's sheets ("view-sheet" value), the layers the user can
    // turn off ("view-layer" layer) and those off (a bit each), and
    // whether the 3D model shows its parts ("view-parts")
    val sheets: List<Sheet> = emptyList(), val layerList: List<LayerRow> = emptyList(), val off: Int = 0, val parts: Boolean = true,
    // what the hub says about the source (parts with no 3D model)
    val note: String = "",
    // the Mechanical page, when that is what is open
    val mech: MechPage? = null,
)

// The Mechanical page (src/mobile/view.bend's Mech.json): what to say
// while there are no parts, the parts ("mech-part" value), the part on
// show (its path for "mech-3d"), its renders and what to say without any,
// and where to get FreeCAD when the hub has none
data class MechPage(
    val say: String, val note: String, val parts: List<Choice>, val name: String, val path: String,
    val shots: List<MechShot>, val empty: String,
)

data class MechShot(val view: String, val url: String)

data class Sheet(val label: String, val value: String, val on: Boolean, val loop: Boolean)

data class LayerRow(val layer: Int, val name: String, val on: Boolean)

// the composer's model chip: its label, the models ("model" sends one)
// and the efforts the current one takes ("effort")
data class ModelPicker(val label: String, val models: List<Choice>, val efforts: List<Choice>, val providers: List<Choice> = emptyList())

// a message waiting in the thread's queue and its buttons (each sends
// action with value)
data class QButton(val label: String, val action: String, val value: String)
data class QueueRow(val msg: String, val text: String, val tag: String, val buttons: List<QButton>)
// the agent's todo list: "Todo 2/5" and a line per step
data class TodoLine(val text: String, val status: String)
data class Todos(val head: String, val lines: List<TodoLine>)

data class ThreadView(
    val id: String, val title: String, val branch: String, val state: String,
    val tools: List<Tool>, val entries: List<Entry>, val live: List<Block>,
    val working: String, val draft: String, val send: String,
    // "interrupt" while a turn runs with nothing typed (the button is Stop)
    val sendAct: String,
    val sending: List<String>, val queued: String, val picker: ModelPicker, val viewer: Viewer,
    val queue: List<QueueRow> = emptyList(),
    val todos: Todos? = null,
    // how many older entries the page leaves out (the "earlier" action shows more)
    val earlier: Int = 0,
    // the menu under the toolbar's overflow, after the tools
    val menu: List<Tool> = emptyList(),
    val parent: Entry? = null,
    val tasks: List<TaskRow> = emptyList(),
    val asks: List<Ask> = emptyList(),
    val skills: List<Skill> = emptyList(),
    // a side question (/btw) and its answer, until closed
    val btw: Btw? = null,
    // what the next message attaches, and what is still uploading; files
    // go up in pieces of chunk bytes
    val attaching: List<Chip> = emptyList(),
    val uploading: String = "",
    val chunk: Int = 196_608,
    val diff: Diff? = null,
    val term: Term? = null,
)

data class Btw(val q: String, val a: String)

data class IslandLine(val thread: String, val title: String, val doing: String)

data class Island(val running: Int, val headline: String, val lines: List<IslandLine>)

// a paired hub (key: its host:port), and a machine a hub knows of that
// this phone is not paired with yet
data class HubRow(val key: String, val name: String, val online: Boolean)

data class Found(val name: String, val url: String)

// Bots (src/mobile/bots.bend). A cat in the list: "bot" (or, remote,
// "remote") sends its id; mood and note say how it is; cat names its rig
// ("look:mood"), which the bridge gives once (Core.cats).
data class BotRow(
    val id: String, val name: String, val mood: String, val note: String, val peer: String, val cat: String,
    val look: Int, val sel: Boolean, val remote: Boolean, val machine: String,
)

// a room in the list ("room" sends its id)
data class RoomRow(val id: String, val name: String, val members: Int, val sel: Boolean, val machine: String)

// the new bot form: its fields ("bfield" name, persona, provider),
// "bot-create" makes it, "form-close" "@bnew" drops it
data class ProviderChoice(val label: String, val provider: String, val on: Boolean)
data class NewBot(val name: String, val persona: String, val provider: String, val providers: List<ProviderChoice>)

// the new room form: "bfield" rname, "room-pick" a bot's id, "room-save"
data class RoomPick(val id: String, val name: String, val on: Boolean)
data class NewRoom(val name: String, val picks: List<RoomPick>)

data class BotTab(val id: String, val label: String)
data class BotMemory(val key: String, val kind: String, val text: String, val tags: String, val updated: String)
// schedule: the cron line described ("when")
data class BotRoutine(
    val id: String, val name: String, val cron: String, val schedule: String, val prompt: String,
    val last: String, val on: Boolean,
)
// the routine form ("routine-edit" id, or "" for a new one, opens it)
data class RoutineForm(val open: Boolean, val id: String, val name: String, val cron: String, val prompt: String)
data class BotHook(val id: String, val name: String, val path: String, val last: String, val count: Int)
data class BotPeer(val id: String, val name: String, val url: String)
// Google's sign-in state and the OAuth client's fields ("google" op)
data class BotGoogle(val status: String, val url: String, val gid: String, val gsecret: String, val gpaste: String)
data class BotSettings(
    val persona: String, val personaField: String, val invite: String, val purl: String, val join: String,
    val google: BotGoogle, val peers: List<BotPeer>,
)
// the hub's latest frame of the bot's page: n changes with every new one
data class BotBrowser(val url: String, val n: String)
data class BotPost(val id: String, val from: String, val text: String, val ago: String, val mine: Boolean)

// what the main area shows when it is not a thread: a bot (kind "bot",
// its tab's content; the chat is the screen's thread), a room, or a bot
// on a linked machine ("remote")
data class BotView(
    val kind: String, val id: String, val name: String, val mood: String, val note: String, val tab: String,
    val peer: String, val members: String, val draft: String, val secret: String, val secretFor: String,
    val cat: String, val tabs: List<BotTab>, val space: SpaceModel?, val page: SpacePageModel?, val browser: BotBrowser?,
    val memory: List<BotMemory>, val routines: List<BotRoutine>, val routine: RoutineForm?,
    val hooks: List<BotHook>, val settings: BotSettings?, val posts: List<BotPost>,
)

// hub: the one in focus (its thread is shown, its plots are drawn)
data class Screen(
    val online: Boolean, val version: String, val error: String, val note: String,
    val sel: String, val empty: String, val projects: List<Project>, val thread: ThreadView?,
    val island: Island, val deleting: Deleting?, val folders: Folders?,
    val hub: String, val hubs: List<HubRow>, val found: List<Found>,
    val bots: List<BotRow> = emptyList(), val rooms: List<RoomRow> = emptyList(),
    val newBot: NewBot? = null, val newRoom: NewRoom? = null, val bot: BotView? = null,
    val settings: Settings? = null, val find: Find? = null,
    // a project remove to confirm ("proj-remove" id, or "proj-keep")
    val removing: Deleting? = null, val search: Search? = null,
    // the hub's theme ("light", "dark"; "" follows the phone's)
    val theme: String = "",
)

data class Cmd(
    val type: String, val text: String,
    // a "send": the CBOR frame, as base64, for the hub keyed hub
    val data: String = "", val hub: String = "",
    // a "notify": the thread whose turn ended, its title, "done"/"fail", what to say, and the
    // key alerts about the same item share
    val thread: String = "", val title: String = "", val kind: String = "", val body: String = "",
    val key: String = "",
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
    o.optJSONArray("lead").map(::swipe), o.optJSONArray("trail").map(::swipe), o.optString("status"),
)

private fun chips(a: JSONArray?) =
    a.map { Chip(it.optString("label"), it.optString("path"), it.optBoolean("image"), it.optString("url")) }

private fun entry(o: JSONObject) = Entry(
    o.optString("id"), o.optString("kind"), o.optString("text"), o.optString("tone"),
    o.optString("label"), blocks(o.optJSONArray("blocks")),
    chips(o.optJSONArray("attachments")),
    o.optJSONArray("images").map { Shot(it.optString("path"), it.optString("url")) },
    o.optBoolean("open"), o.optString("value"),
)

private fun tool(o: JSONObject) = Tool(
    o.optString("label"), o.optString("action"), o.optBoolean("on"), o.optString("value"), o.optBoolean("danger"),
    o.optJSONArray("options").map { SwipeChoice(it.optString("label"), it.optString("value")) },
)

private fun term(o: JSONObject) = Term(
    o.optString("title"), o.optInt("fg"), o.optInt("bg"),
    o.optJSONArray("lines").let { a ->
        if (a == null) emptyList() else (0 until a.length()).map { i ->
            a.optJSONArray(i).map { TermRun(it.optString("t"), it.optInt("fg"), it.optInt("bg"), it.optBoolean("b"), it.optBoolean("u")) }
        }
    },
    (o.optJSONObject("cursor") ?: JSONObject()).let { TermCursor(it.optInt("x"), it.optInt("y"), it.optBoolean("on")) },
)

private fun folderRows(a: JSONArray?) =
    a.map { FolderRow(it.optString("label"), it.optString("action"), it.optString("value"), it.optString("kind")) }

private fun thread(o: JSONObject) = threadOf(o).copy(
    earlier = o.optInt("earlier", 0),
    menu = o.optJSONArray("menu").map(::tool),
    parent = o.optJSONObject("parent")?.let(::entry),
    tasks = o.optJSONArray("tasks").map { TaskRow(it.optString("id"), it.optString("who"), it.optString("title"), it.optString("state")) },
    asks = o.optJSONArray("asks").map { a ->
        Ask(a.optString("id"), a.optString("kind"), a.optString("head"), a.optString("detail"), blocks(a.optJSONArray("blocks")),
            a.optJSONArray("buttons").map { AskButton(it.optString("label"), it.optString("value"), it.optBoolean("primary")) })
    },
    skills = o.optJSONArray("skills").map { Skill(it.optString("name"), it.optString("desc")) },
    btw = o.optJSONObject("btw")?.let { Btw(it.optString("q"), it.optString("a")) },
    attaching = chips(o.optJSONArray("attaching")),
    uploading = o.optString("uploading"),
    chunk = o.optInt("chunk", 196_608),
    diff = o.optJSONObject("diff")?.let { d ->
        Diff(d.optString("summary"), d.optJSONArray("files").map { f ->
            DiffFile(f.optString("name"), f.optString("status"),
                f.optJSONArray("lines").map { DiffLine(it.optInt("k"), it.optString("t"), it.optString("o"), it.optString("n")) })
        })
    },
    term = o.optJSONObject("term")?.let(::term),
)

private fun threadOf(o: JSONObject) = ThreadView(
    o.optString("id"), o.optString("title"), o.optString("branch"), o.optString("state"),
    o.optJSONArray("tools").map(::tool),
    o.optJSONArray("entries").map(::entry),
    blocks(o.optJSONArray("live")), o.optString("working"), o.optString("draft"), o.optString("send"),
    o.optString("sendAct", "send"), strs(o.optJSONArray("sending")), o.optString("queued"), picker(o.optJSONObject("picker") ?: JSONObject()),
    viewer(o.optJSONObject("viewer") ?: JSONObject()),
    o.optJSONArray("queue").map {
        QueueRow(it.optString("msg"), it.optString("text"), it.optString("tag"),
            it.optJSONArray("buttons").map { b -> QButton(b.optString("label"), b.optString("action"), b.optString("value")) })
    },
    o.optJSONObject("todos")?.let { td -> Todos(td.optString("head"), td.optJSONArray("lines").map { TodoLine(it.optString("text"), it.optString("status")) }) },
)

private fun choices(a: JSONArray?) = a.map { Choice(it.optString("label"), it.optString("value"), it.optBoolean("on")) }

private fun picker(o: JSONObject) =
    ModelPicker(o.optString("label"), choices(o.optJSONArray("models")), choices(o.optJSONArray("efforts")), choices(o.optJSONArray("providers")))

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
    o.optBoolean("light"), ints(o.optJSONArray("look")),
    o.optJSONArray("sheets").map { Sheet(it.optString("label"), it.optString("value"), it.optBoolean("on"), it.optBoolean("loop")) },
    o.optJSONArray("layerList").map { LayerRow(it.optInt("layer"), it.optString("name"), it.optBoolean("on")) },
    o.optInt("off"), o.optBoolean("parts", true), o.optString("note"),
    o.optJSONObject("mech")?.let { p ->
        MechPage(p.optString("say"), p.optString("note"), choices(p.optJSONArray("parts")), p.optString("name"), p.optString("path"),
            p.optJSONArray("shots").map { MechShot(it.optString("view"), it.optString("url")) }, p.optString("empty"))
    },
)

private fun strs(a: JSONArray?): List<String> =
    if (a == null) emptyList() else (0 until a.length()).map { a.optString(it) }

private fun island(o: JSONObject?) = Island(
    o?.optInt("running") ?: 0, o?.optString("headline") ?: "",
    o?.optJSONArray("lines").map { IslandLine(it.optString("thread"), it.optString("title"), it.optString("doing")) },
)

private fun botView(o: JSONObject) = BotView(
    o.optString("kind"), o.optString("id"), o.optString("name"), o.optString("mood"), o.optString("note"),
    o.optString("tab", "chat"), o.optString("peer"), o.optString("members"), o.optString("draft"),
    o.optString("secret"), o.optString("secretFor"), o.optString("cat"),
    o.optJSONArray("tabs").map { BotTab(it.optString("id"), it.optString("label")) },
    o.optJSONObject("space")?.let(::spaceModel),
    o.optJSONObject("page")?.let { SpacePageModel(it.optString("bot"), it.optString("url"), it.optString("n")) },
    o.optJSONObject("browser")?.let { BotBrowser(it.optString("url"), it.optString("n")) },
    o.optJSONArray("memory").map {
        BotMemory(it.optString("key"), it.optString("kind"), it.optString("text"), it.optString("tags"), it.optString("updated"))
    },
    o.optJSONArray("routines").map {
        BotRoutine(it.optString("id"), it.optString("name"), it.optString("cron"), it.optString("when"), it.optString("prompt"),
            it.optString("last"), it.optBoolean("on"))
    },
    o.optJSONObject("routine")?.let {
        RoutineForm(it.optBoolean("open"), it.optString("id"), it.optString("name"), it.optString("cron"), it.optString("prompt"))
    },
    o.optJSONArray("hooks").map {
        BotHook(it.optString("id"), it.optString("name"), it.optString("path"), it.optString("last"), it.optInt("count"))
    },
    o.optJSONObject("settings")?.let { st ->
        val g = st.optJSONObject("google") ?: JSONObject()
        BotSettings(st.optString("persona"), st.optString("personaField"), st.optString("invite"), st.optString("purl"),
            st.optString("join"),
            BotGoogle(g.optString("status"), g.optString("url"), g.optString("gid"), g.optString("gsecret"), g.optString("gpaste")),
            st.optJSONArray("peers").map { BotPeer(it.optString("id"), it.optString("name"), it.optString("url")) })
    },
    o.optJSONArray("posts").map {
        BotPost(it.optString("id"), it.optString("from"), it.optString("text"), it.optString("ago"), it.optBoolean("mine"))
    },
)

fun parseScreen(o: JSONObject) = Screen(
    o.optBoolean("online"), o.optString("version"), o.optString("error"), o.optString("note"),
    o.optString("sel"), o.optString("empty"),
    o.optJSONArray("projects").map {
        Project(it.optString("id"), it.optString("title"), it.optString("root"), it.optString("machine"), it.optBoolean("open"),
            it.optJSONArray("threads").map(::row), it.optString("snoozedShelf"), it.optJSONArray("snoozed").map(::row),
            it.optString("shelf"), it.optJSONArray("settled").map(::row),
            it.optString("value"), it.optBoolean("archOpen"), it.optJSONArray("archived").map(::row))
    },
    o.optJSONObject("thread")?.let(::thread),
    island(o.optJSONObject("island")),
    o.optJSONObject("deleting")?.let {
        Deleting(it.optString("id"), it.optString("title"), it.optString("body"), it.optString("yes"), it.optString("no"))
    },
    o.optJSONObject("folders")?.let { p ->
        Folders(p.optString("text"), p.optString("hint"), p.optString("error"),
            folderRows(p.optJSONArray("items")))
    },
    o.optString("hub"),
    o.optJSONArray("hubs").map { HubRow(it.optString("key"), it.optString("name"), it.optBoolean("online")) },
    o.optJSONArray("found").map { Found(it.optString("name"), it.optString("url")) },
    o.optJSONArray("bots").map {
        BotRow(it.optString("id"), it.optString("name"), it.optString("mood"), it.optString("note"), it.optString("peer"),
            it.optString("cat"), it.optInt("look"), it.optBoolean("sel"), it.optBoolean("remote"), it.optString("machine"))
    },
    o.optJSONArray("rooms").map {
        RoomRow(it.optString("id"), it.optString("name"), it.optInt("members"), it.optBoolean("sel"), it.optString("machine"))
    },
    o.optJSONObject("newBot")?.let { f ->
        NewBot(f.optString("name"), f.optString("persona"), f.optString("provider"),
            f.optJSONArray("providers").map { ProviderChoice(it.optString("label"), it.optString("provider"), it.optBoolean("on")) })
    },
    o.optJSONObject("newRoom")?.let { f ->
        NewRoom(f.optString("name"), f.optJSONArray("picks").map { RoomPick(it.optString("id"), it.optString("name"), it.optBoolean("on")) })
    },
    o.optJSONObject("bot")?.let(::botView),
    o.optJSONObject("settings")?.let { st ->
        Settings(st.optJSONArray("rows").map { r ->
            SetRow(r.optString("label"), r.optString("note"),
                r.optJSONArray("buttons").map { SetButton(it.optString("label"), it.optString("action"), it.optString("value"), it.optBoolean("on")) })
        })
    },
    o.optJSONObject("find")?.let { Find(it.optString("mode"), it.optString("query"), folderRows(it.optJSONArray("rows"))) },
    o.optJSONObject("removing")?.let {
        Deleting(it.optString("id"), it.optString("title"), it.optString("body"), it.optString("yes"), it.optString("no"))
    },
    o.optJSONObject("search")?.let { Search(it.optBoolean("open"), it.optString("query"), it.optString("hint")) },
    o.optString("theme"),
)

fun parseCmds(o: JSONObject): List<Cmd> =
    o.optJSONArray("cmds").map {
        Cmd(it.optString("type"), it.optString("text"), it.optString("data"), it.optString("hub"),
            it.optString("thread"), it.optString("title"), it.optString("kind"), it.optString("body"), it.optString("key"))
    }
