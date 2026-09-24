import SwiftUI

// A bot's space: the JSON src/mobile/space.bend emits (MSpace.json). Plain
// data; Bend has already kept what it understands and capped every size.
// A button calls act("space", send); an input calls
// act("space-input", send + "\u{1f}" + text).

struct SpaceModel: Decodable {
    let bot: String?
    let title: String
    let blocks: [SpaceBlock]
}

struct SpaceBlock: Decodable {
    let type: String
    let text, label, value, hint, action, placeholder, tone, pct, send: String?
    let permille: Int?
    let items, head: [String]?
    let rows: [[String]]?
    let blocks: [SpaceBlock]?

    private enum Key: String, CodingKey {
        case type, text, label, value, hint, action, placeholder, tone, pct, send, permille, items, head, rows, blocks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        type = try c.decode(String.self, forKey: .type)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        // a stat's value is text; a progress bar's is a number (read permille instead)
        value = try? c.decodeIfPresent(String.self, forKey: .value)
        hint = try c.decodeIfPresent(String.self, forKey: .hint)
        action = try c.decodeIfPresent(String.self, forKey: .action)
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        tone = try c.decodeIfPresent(String.self, forKey: .tone)
        pct = try c.decodeIfPresent(String.self, forKey: .pct)
        send = try c.decodeIfPresent(String.self, forKey: .send)
        permille = try c.decodeIfPresent(Int.self, forKey: .permille)
        items = try c.decodeIfPresent([String].self, forKey: .items)
        head = try c.decodeIfPresent([String].self, forKey: .head)
        rows = try c.decodeIfPresent([[String]].self, forKey: .rows)
        blocks = try c.decodeIfPresent([SpaceBlock].self, forKey: .blocks)
    }

    // what a button or input sends: the bot's value, or the bare action
    var key: String { send ?? action ?? "" }
}

struct SpaceView: View {
    let space: SpaceModel
    let act: (String, String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !space.title.isEmpty {
                    Text(space.title).font(.title3.weight(.semibold))
                }
                ForEach(Array(space.blocks.enumerated()), id: \.offset) { _, b in
                    SpaceBlockView(block: b, act: act)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct SpaceBlockView: View {
    let block: SpaceBlock
    let act: (String, String) -> Void

    var body: some View {
        switch block.type {
        case "row":
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array((block.blocks ?? []).enumerated()), id: \.offset) { _, b in
                        SpaceBlockView(block: b, act: act)
                    }
                }
            }
        default:
            SpaceLeaf(block: block, act: act)
        }
    }
}

private struct SpaceLeaf: View {
    let block: SpaceBlock
    let act: (String, String) -> Void

    var body: some View {
        switch block.type {
        case "heading":
            Text(block.text ?? "").font(.headline).padding(.top, 4)
        case "text":
            Text(LocalizedStringKey(block.text ?? "")).fixedSize(horizontal: false, vertical: true)
        case "stat":
            VStack(alignment: .leading, spacing: 2) {
                Text(block.label ?? "").font(.caption).foregroundStyle(.secondary)
                Text(block.value ?? "").font(.title2.weight(.semibold).monospacedDigit())
                if let h = block.hint, !h.isEmpty {
                    Text(h).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(minWidth: 110, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        case "progress":
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(block.label ?? "")
                    Spacer()
                    Text(block.pct ?? "").monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.subheadline)
                ProgressView(value: Double(block.permille ?? 0), total: 1000)
            }
        case "list":
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array((block.items ?? []).enumerated()), id: \.offset) { _, s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(s)
                    }
                }
            }
        case "kv":
            VStack(spacing: 6) {
                ForEach(Array((block.rows ?? []).enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.first ?? "").foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(r.count > 1 ? r[1] : "").multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                }
            }
        case "table":
            SpaceTable(head: block.head ?? [], rows: block.rows ?? [])
        case "button":
            Button(block.label ?? "") { act("space", block.key) }
                .buttonStyle(.bordered)
        case "input":
            SpaceInput(block: block, act: act)
        case "divider":
            Divider()
        case "badge":
            Text(block.text ?? "")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .foregroundStyle(tint)
                .background(tint.opacity(0.15), in: .capsule)
        case "code":
            ScrollView(.horizontal) {
                Text(block.text ?? "").font(.caption.monospaced()).textSelection(.enabled).padding(10)
            }
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 8))
        default:
            EmptyView()
        }
    }

    private var tint: Color {
        switch block.tone {
        case "ok": .green
        case "warn": .orange
        case "bad": .red
        default: .secondary
        }
    }
}

private struct SpaceTable: View {
    let head: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                if !head.isEmpty {
                    GridRow { ForEach(Array(head.enumerated()), id: \.offset) { _, h in Text(h).foregroundStyle(.secondary) } }
                        .font(.caption.weight(.semibold))
                    Divider()
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    GridRow { ForEach(Array(r.enumerated()), id: \.offset) { _, c in Text(c) } }
                        .font(.subheadline)
                }
            }
        }
    }
}

private struct SpaceInput: View {
    let block: SpaceBlock
    let act: (String, String) -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let l = block.label, !l.isEmpty {
                Text(l).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField(block.placeholder ?? "", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit(send)
                Button("Send", action: send)
                    .buttonStyle(.bordered)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        act("space-input", block.key + "\u{1f}" + t)
        text = ""
    }
}
