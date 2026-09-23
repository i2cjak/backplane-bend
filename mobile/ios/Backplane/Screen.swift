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
    let pinned: Bool
    let lead, trail: [Swipe]
}

struct Project: Decodable, Identifiable {
    let id, title, root: String
    let open: Bool
    let threads: [Row]
    let snoozedShelf: String
    let snoozed: [Row]
    let shelf: String
    let settled: [Row]
}

struct Tool: Decodable, Hashable {
    let label, action: String
    let on: Bool
}

// a markdown node from Md.render: an element with kids, or text
struct Block: Decodable, Hashable {
    let tag: String?
    let kids: [Block]?
    let text: String?

    var plain: String { text ?? (kids ?? []).map(\.plain).joined() }
}

struct Entry: Decodable, Identifiable {
    let id, kind, text: String
    let tone, label: String?
    let blocks: [Block]?
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

struct ThreadView: Decodable {
    let id, title, branch, state: String
    let tools: [Tool]
    let entries: [Entry]
    // sent, not yet stored by the hub; and a message waiting for this turn
    let sending: [String]
    let queued: String
    let live: [Block]
    let working, draft, send: String
    let viewer: Viewer
}

// a delete a row asked for, waiting for yes ("row-delete" id) or no
struct Deleting: Decodable, Equatable {
    let id, title, body, yes, no: String
}

struct Screen: Decodable {
    let online: Bool
    let version, error, note, sel, empty: String
    let projects: [Project]
    let deleting: Deleting?
    let island: IslandAttributes.ContentState
    let thread: ThreadView?
}

struct Cmd: Decodable {
    let type: String
    let text: String?
    // send: the CBOR frame, as base64
    let data: String?
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
