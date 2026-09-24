import Foundation

// The screen src/mobile/screen.bend emits. Plain data; no decisions.

// a swipe button: the action it sends with its value, or (a snooze)
// choices whose values it sends instead
struct Swipe: Decodable, Hashable {
    let label, action, value, tone: String
    let options: [SwipeChoice]
}

struct SwipeChoice: Decodable, Hashable {
    let label, value: String
}

struct Row: Decodable, Identifiable, Hashable {
    let id, title, state, ago: String
    // what its dot says: approval, input, working, failed, queued, ready
    let status: String?
    let pinned: Bool
    let lead, trail: [Swipe]
}

struct Project: Decodable, Identifiable {
    // machine: the hub it is on, named when the phone has several
    let id, title, root, machine: String
    let open: Bool
    let threads: [Row]
    let snoozedShelf: String
    let snoozed: [Row]
    let shelf: String
    let settled: [Row]
    // the Archived shelf: "toggle-settled" with value opens or shuts it
    let value: String?
    let archOpen: Bool?
    let archived: [Row]?
}

// a toolbar or menu item: it sends action with value, or (a snooze)
// offers choices whose values it sends instead; danger asks first
struct Tool: Decodable, Hashable {
    let label, action: String
    let on: Bool
    let value: String?
    let danger: Bool?
    let options: [SwipeChoice]?
}

// a markdown node from Md.render: an element with kids, or text
struct Block: Decodable, Hashable {
    let tag: String?
    let kids: [Block]?
    let text: String?
    // a link's target
    let href: String?

    var plain: String { text ?? (kids ?? []).map(\.plain).joined() }
}

// an attachment of a user message (url: where its hub serves it)
struct Chip: Decodable, Hashable {
    let label, path: String
    let image: Bool
    let url: String
}

// an image a reply names
struct Shot: Decodable, Hashable {
    let path, url: String
}

// kind: user, assistant, act (a tool line), fold (a run of tool calls:
// "fold" with value opens or shuts it), link (opens thread value)
struct Entry: Decodable, Identifiable {
    let id, kind, text: String
    let tone, label: String?
    let blocks: [Block]?
    let attachments: [Chip]?
    let images: [Shot]?
    let open: Bool?
    let value: String?
}

// what the agent waits on the user for: an approval, a question or a
// plan; each button sends "answer" with its value
struct AskButton: Decodable, Hashable {
    let label, value: String
    let primary: Bool
}

struct Ask: Decodable, Identifiable {
    let id, kind, head, detail: String
    let blocks: [Block]
    let buttons: [AskButton]
}

// a thread this one delegated to ("select" opens it)
struct TaskRow: Decodable, Identifiable {
    let id, who, title, state: String
}

// a skill the `$` being typed may complete to ("skill" with its name)
struct Skill: Decodable, Hashable {
    let name, desc: String
}

// what the thread changed: k 0 context, 1 added, 2 removed, 3 meta, 4 a hunk head
struct DiffLine: Decodable, Hashable {
    let k: Int
    let t, o, n: String
}

struct DiffFile: Decodable, Identifiable {
    let name, status: String
    let lines: [DiffLine]
    var id: String { name }
}

struct Diff: Decodable {
    let summary: String
    let files: [DiffFile]
}

// the thread's shell: rows of styled runs (colours 0xRRGGBB) and the cursor
struct TermRun: Decodable, Hashable {
    let t: String
    let fg, bg: UInt32
    let b, u: Bool
}

struct TermCursor: Decodable {
    let x, y: Int
    let on: Bool
}

struct Term: Decodable {
    let title: String
    let fg, bg: UInt32
    let lines: [[TermRun]]
    let cursor: TermCursor
}

// the board viewer (src/mobile/view.bend): the source open ("" closed),
// the key its plots carry, the choices, and how to draw
struct Choice: Decodable, Hashable {
    let label, value: String
    let on: Bool
}

// a tapped item's card: its kind, then key = value rows, and the info
// "Mention in chat" puts in the draft
struct CardRow: Decodable, Hashable {
    let k, v: String
}

struct Card: Decodable {
    let info, title: String
    let rows: [CardRow]
}

// the key of the plot it draws layers from, how far a tap reaches
// (points), the layers a 3D view lays on the board's top and bottom faces,
// the board's colour before its model arrives, the field of view, the
// piece picked ("chunk,info" of the held chunks) and its card
struct Viewer: Decodable {
    let open, key, layers: String
    let choices: [Choice]
    let bg: UInt32
    let fade: Int
    let margin, zmin, zmax, tap: Float
    let top, bottom: [Int]
    let slab: UInt32
    let fov: Float
    let picked: String
    let card: Card?
}

// the composer's model chip: its label, the models ("model" sends one)
// and the efforts the current one takes ("effort")
struct ModelPicker: Decodable {
    let label: String
    let models, efforts: [Choice]
    // another provider takes the thread up from its next turn
    let providers: [Choice]?
}

// a message waiting in the thread's queue and its buttons (each sends
// action with value)
struct QButton: Decodable {
    let label, action, value: String
}

// the agent's todo list: "Todo 2/5" and a line per step
struct TodoLine: Decodable {
    let text, status: String
}

struct Todos: Decodable {
    let head: String
    let lines: [TodoLine]
}

struct QueueRow: Decodable {
    let msg, text, tag: String
    let buttons: [QButton]
}

struct ThreadView: Decodable {
    let id, title, branch, state: String
    let tools: [Tool]
    let entries: [Entry]
    // sent, not yet stored by the hub; and a message waiting for this turn
    let sending: [String]
    let queued: String
    let queue: [QueueRow]?
    let todos: Todos?
    let live: [Block]
    let working, draft, send: String
    let picker: ModelPicker
    let viewer: Viewer
    // the menu under the toolbar's ellipsis, after the tools
    let menu: [Tool]?
    let parent: Entry?
    let tasks: [TaskRow]?
    let asks: [Ask]?
    let skills: [Skill]?
    // what the next message attaches, and what is still uploading; files
    // go up in pieces of chunk bytes
    let attaching: [Chip]?
    let uploading: String?
    let chunk: Int?
    let diff: Diff?
    let term: Term?
}

// a delete a row asked for, waiting for yes ("row-delete" id) or no
struct Deleting: Decodable, Equatable {
    let id, title, body, yes, no: String
}

// the project picker: its path field, the field's hint, an error, and the
// rows (a tap sends action with value; one with no action is only shown)
struct FolderRow: Decodable, Hashable {
    let label, action, value, kind: String
}

// settings: rows of a label, a note and buttons (each sends action with value)
struct SetButton: Decodable, Hashable {
    let label, action, value: String
    let on: Bool
}

struct SetRow: Decodable, Hashable {
    let label, note: String
    let buttons: [SetButton]
}

struct Settings: Decodable {
    let rows: [SetRow]
}

// thread search ("search") or the file picker ("files"): its query and rows
struct Find: Decodable {
    let mode, query: String
    let rows: [FolderRow]
}

struct Folders: Decodable {
    let text, hint, error: String
    let items: [FolderRow]
}

// a paired hub (key: its host:port), and a machine a hub knows of that
// this phone is not paired with yet
struct HubRow: Decodable, Hashable {
    let key, name: String
    let online: Bool
}

struct Found: Decodable, Hashable {
    let name, url: String
}

struct Screen: Decodable {
    let online: Bool
    // hub: the one in focus (its thread is shown, its plots are drawn)
    let version, error, note, sel, empty, hub: String
    let hubs: [HubRow]
    let found: [Found]
    let projects: [Project]
    let deleting: Deleting?
    let folders: Folders?
    let settings: Settings?
    let find: Find?
    let island: IslandAttributes.ContentState
    let thread: ThreadView?
}

struct Cmd: Decodable {
    let type: String
    let text: String?
    // send: the CBOR frame, as base64, for the hub keyed hub
    let data, hub: String?
    // notify
    let thread, title, kind, body: String?
}

struct Resume: Decodable {
    let since, origin: String
}

struct Out: Decodable, @unchecked Sendable {
    let screen: Screen?
    let cmds: [Cmd]

    private struct Cmds: Decodable {
        let cmds: [Cmd]
    }

    // an answer; with screen false only its commands (a newer screen follows)
    static func decode(_ text: String, screen: Bool) -> Out? {
        let d = Data(text.utf8)
        if screen { return try? JSONDecoder().decode(Out.self, from: d) }
        return (try? JSONDecoder().decode(Cmds.self, from: d)).map { Out(screen: nil, cmds: $0.cmds) }
    }
}
