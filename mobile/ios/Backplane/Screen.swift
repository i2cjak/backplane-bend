import Foundation

// The screen src/mobile/screen.bend emits. Plain data; no decisions.

struct Row: Decodable, Identifiable, Hashable {
    let id, title, state, ago: String
    let pinned: Bool
}

struct Project: Decodable, Identifiable {
    let id, title, root: String
    let open: Bool
    let threads: [Row]
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

struct ThreadView: Decodable {
    let id, title, branch, state: String
    let tools: [Tool]
    let entries: [Entry]
    let live: [Block]
    let working, draft, send: String
}

struct Screen: Decodable {
    let online: Bool
    let version, error, note, sel, empty: String
    let projects: [Project]
    let thread: ThreadView?
}

struct Cmd: Decodable {
    let type: String
    let text: String?
}

struct Out: Decodable {
    let screen: Screen?
    let cmds: [Cmd]
}
