import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// The pieces of a thread and the sheets over it. Every label, value and
// choice comes from the screen (src/mobile/screen.bend); these only draw
// them and send back the action each names.

// a thread's dot: what most needs the user (row.status), else its turn
struct StatusDot: View {
    let state: String
    let status: String?

    var body: some View {
        switch status ?? "" {
        case "approval": Image(systemName: "hand.raised.fill").foregroundStyle(.orange).font(.caption)
        case "input": Image(systemName: "questionmark.bubble.fill").foregroundStyle(.blue).font(.caption)
        case "working": ProgressView().controlSize(.mini)
        case "failed": Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case "queued": Image(systemName: "clock").foregroundStyle(.secondary).font(.caption)
        case "ready": Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.quaternary)
        default:
            switch state {
            case "run": ProgressView().controlSize(.mini)
            case "fail": Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            case "stop": Image(systemName: "stop.circle").foregroundStyle(.orange)
            default: Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.quaternary)
            }
        }
    }
}

// an image the lightbox shows
struct Shown: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// an image from the hub, as a thumbnail; a tap opens it full screen
struct Thumb: View {
    let model: AppModel
    let url: String
    let show: (Shown) -> Void

    var body: some View {
        if let u = model.web(url) {
            AsyncImage(url: u) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFit()
                case .failure: Image(systemName: "photo").foregroundStyle(.tertiary).frame(width: 80, height: 60)
                default: ProgressView().frame(width: 80, height: 60)
                }
            }
            .frame(maxWidth: 260, maxHeight: 200, alignment: .leading)
            .clipShape(.rect(cornerRadius: 6))
            .onTapGesture { show(Shown(url: u)) }
            .accessibilityAddTraits(.isButton)
        }
    }
}

// pinch to zoom, drag to pan, double-tap to zoom in or back, tap Done to close
struct Lightbox: View {
    let shown: Shown
    let close: () -> Void
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var moved: CGSize = .zero

    var body: some View {
        NavigationStack {
            AsyncImage(url: shown.url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFit()
                } else if phase.error != nil {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .gesture(MagnifyGesture()
                .onChanged { scale = min(max(base * $0.magnification, 1), 8) }
                .onEnded { _ in base = scale; if scale == 1 { offset = .zero; moved = .zero } })
            .simultaneousGesture(DragGesture()
                .onChanged { offset = CGSize(width: moved.width + $0.translation.width, height: moved.height + $0.translation.height) }
                .onEnded { _ in moved = offset })
            .onTapGesture(count: 2) {
                withAnimation {
                    scale = scale > 1 ? 1 : 2.5
                    base = scale
                    if scale == 1 { offset = .zero; moved = .zero }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) }
                ToolbarItem(placement: .topBarLeading) { ShareLink(item: shown.url) }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// an attachment chip; an image shows as a thumbnail
struct ChipView: View {
    let model: AppModel
    let chip: Chip
    let show: (Shown) -> Void

    var body: some View {
        if chip.image {
            Thumb(model: model, url: chip.url, show: show)
        } else {
            Label(chip.label, systemImage: "doc")
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 6))
        }
    }
}

struct EntryRow: View {
    let model: AppModel
    let entry: Entry
    let show: (Shown) -> Void

    var body: some View {
        switch entry.kind {
        case "user":
            VStack(alignment: .trailing, spacing: 6) {
                if !entry.text.isEmpty {
                    Text(entry.text)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 18))
                        .contextMenu { Button("Copy", systemImage: "doc.on.doc") { model.act("copy", entry.text) } }
                }
                ForEach(entry.attachments ?? [], id: \.self) { ChipView(model: model, chip: $0, show: show) }
            }
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .trailing)
        case "assistant":
            VStack(alignment: .leading, spacing: 8) {
                MarkdownView(blocks: entry.blocks ?? [])
                ForEach(entry.images ?? [], id: \.self) { Thumb(model: model, url: $0.url, show: show) }
            }
            .contextMenu { Button("Copy", systemImage: "doc.on.doc") { model.act("copy", entry.text) } }
        case "fold":
            Button { model.act("fold", entry.value ?? "") } label: {
                HStack(spacing: 6) {
                    Image(systemName: entry.open == true ? "chevron.down" : "chevron.right").font(.caption2)
                    Text(entry.text).lineLimit(1)
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel((entry.open == true ? "Hide " : "Show ") + entry.text)
        case "link":
            Button { model.act("select", entry.value ?? "") } label: {
                Text(entry.text).lineLimit(1).font(.callout)
            }
            .buttonStyle(.borderless)
        default:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.label ?? "").foregroundStyle(.tertiary)
                Text(entry.text).lineLimit(2)
            }
            .font(.caption.monospaced())
            .foregroundStyle(entry.tone == "error" ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// the threads this one delegated to
struct TasksView: View {
    let model: AppModel
    let tasks: [TaskRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subagents").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(tasks) { t in
                Button { model.act("select", t.id) } label: {
                    HStack(spacing: 8) {
                        StatusDot(state: t.state == "running" ? "run" : t.state == "failed" ? "fail" : "", status: nil).frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).lineLimit(1)
                            Text(t.who + " · " + t.state).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
    }
}

// an approval, question or plan waiting on the user
struct AskCard: View {
    let model: AppModel
    let ask: Ask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(ask.head, systemImage: ask.kind == "plan" ? "list.bullet.clipboard" : ask.kind == "input" ? "questionmark.bubble" : "hand.raised")
                .font(.subheadline.bold())
            if !ask.blocks.isEmpty {
                ScrollView { MarkdownView(blocks: ask.blocks).font(.callout) }.frame(maxHeight: 220)
            } else if !ask.detail.isEmpty {
                Text(ask.detail).font(.caption.monospaced()).lineLimit(8).textSelection(.enabled)
            }
            FlowButtons(buttons: ask.buttons) { model.act("answer", $0.value) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
    }
}

// buttons that wrap onto more lines when they do not fit
struct FlowButtons: View {
    let buttons: [AskButton]
    let tap: (AskButton) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { items }
            VStack(alignment: .leading, spacing: 6) { items }
        }
    }

    @ViewBuilder private var items: some View {
        ForEach(buttons, id: \.self) { b in
            if b.primary {
                Button(b.label) { tap(b) }.buttonStyle(.borderedProminent)
            } else {
                Button(b.label) { tap(b) }.buttonStyle(.bordered)
            }
        }
    }
}

// what the next message attaches (× takes one off), what is uploading,
// and the skills a `$` being typed completes to
struct ComposerExtras: View {
    let model: AppModel
    let thread: ThreadView

    var body: some View {
        let atts = thread.attaching ?? []
        let up = thread.uploading ?? ""
        let skills = thread.skills ?? []
        if let b = thread.btw {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("btw · " + b.q).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { model.act("btw-close") } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                ScrollView { Text(b.a).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 200)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .padding(.horizontal).padding(.top, 8)
        }
        if !skills.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(skills, id: \.self) { k in
                        Button { model.act("skill", k.name) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("$" + k.name).font(.caption.bold())
                                Text(k.desc).font(.caption2).lineLimit(1).frame(maxWidth: 200, alignment: .leading)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 8)
        }
        if !atts.isEmpty || !up.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(atts, id: \.self) { c in
                        Button { model.act("detach", c.path) } label: {
                            Label(c.label, systemImage: c.image ? "photo" : "doc").lineLimit(1)
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Remove " + c.label)
                    }
                    if !up.isEmpty {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text(up).lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .padding(.horizontal)
            }
            .padding(.top, 8)
        }
    }
}

// the paperclip: photos or files, each sent up in pieces
struct AttachButton: View {
    let model: AppModel
    @State private var photos: [PhotosPickerItem] = []
    @State private var picking = false
    @State private var importing = false

    var body: some View {
        Menu {
            Button("Photos", systemImage: "photo.on.rectangle") { picking = true }
            Button("Files", systemImage: "folder") { importing = true }
        } label: {
            Image(systemName: "paperclip").font(.system(size: 20)).padding(.bottom, 6)
        }
        .accessibilityLabel("Attach")
        .photosPicker(isPresented: $picking, selection: $photos, maxSelectionCount: 10, matching: .images)
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            photos = []
            Task {
                for (i, it) in items.enumerated() {
                    guard let data = try? await it.loadTransferable(type: Data.self) else { continue }
                    let ext = it.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    // HEIC becomes JPEG, which every agent reads
                    if ext == "heic", let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.85) {
                        model.attach(jpg, name: "photo-\(i + 1).jpg")
                    } else {
                        model.attach(data, name: "photo-\(i + 1).\(ext)")
                    }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r else { return }
            for u in urls {
                let ok = u.startAccessingSecurityScopedResource()
                defer { if ok { u.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: u) { model.attach(data, name: u.lastPathComponent) }
            }
        }
    }
}

// what the thread changed, with the git actions
struct DiffSheet: View {
    let model: AppModel
    let diff: Diff
    @State private var reverting = false

    var body: some View {
        NavigationStack {
            List {
                Section { Text(diff.summary).font(.footnote).foregroundStyle(.secondary) }
                ForEach(diff.files) { f in
                    Section {
                        ForEach(Array(f.lines.enumerated()), id: \.offset) { _, l in line(l) }
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    } header: {
                        HStack {
                            Text(f.name).textCase(nil).lineLimit(1).truncationMode(.head)
                            Spacer()
                            Text(f.status).textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 14)
            .navigationTitle("Diff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { model.act("panel") } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Commit & push", systemImage: "arrow.up.circle") { model.act("git", "commit_push") }
                        Button("Open PR", systemImage: "arrow.triangle.pull") { model.act("git", "commit_push_pr") }
                        Button("Revert thread", systemImage: "arrow.uturn.backward", role: .destructive) { reverting = true }
                    } label: {
                        Text("Git")
                    }
                }
            }
            .confirmationDialog("Put the files back as they were when this thread began?", isPresented: $reverting, titleVisibility: .visible) {
                Button("Revert thread", role: .destructive) { model.act("revert", "0") }
            }
        }
    }

    private func line(_ l: DiffLine) -> some View {
        let sign = l.k == 1 ? "+" : l.k == 2 ? "-" : " "
        let bg: Color = l.k == 1 ? .green.opacity(0.14) : l.k == 2 ? .red.opacity(0.14) : .clear
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            if l.k == 4 {
                Text(l.t).foregroundStyle(.blue)
            } else {
                Text(l.k == 2 ? l.o : l.n).foregroundStyle(.tertiary).frame(width: 30, alignment: .trailing)
                Text(sign + l.t).foregroundStyle(l.k == 3 ? .secondary : .primary)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 1)
        .listRowBackground(bg)
        .listRowSeparator(.hidden)
    }
}

// the thread's shell: the screen the hub's emulator keeps, keys typed in a
// hidden field, and a row of keys a phone keyboard lacks
struct TermSheet: View {
    let model: AppModel
    let term: Term
    @State private var buf = " "
    @FocusState private var typing: Bool

    static let font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let cw = ("M" as NSString).size(withAttributes: [.font: font]).width
    static let lh = ceil(font.lineHeight)

    // the size a terminal has room for on this phone, as "<cols>x<rows>"
    static func size() -> String {
        let b = UIScreen.main.bounds
        return "\(max(Int((b.width - 16) / cw), 20))x\(max(Int((b.height * 0.5) / lh), 8))"
    }

    private static func color(_ c: UInt32) -> Color {
        Color(red: Double((c >> 16) & 255) / 255, green: Double((c >> 8) & 255) / 255, blue: Double(c & 255) / 255)
    }

    private func row(_ runs: [TermRun]) -> AttributedString {
        var out = AttributedString()
        for r in runs {
            var a = AttributedString(r.t)
            a.foregroundColor = Self.color(r.fg)
            if r.bg != term.bg { a.backgroundColor = Self.color(r.bg) }
            if r.b { a.font = .system(size: 11, weight: .bold, design: .monospaced) }
            if r.u { a.underlineStyle = .single }
            out += a
        }
        return out
    }

    private func key(_ k: String, _ mods: Int = 0) { model.act("term-key", "\(k)\t\(mods)") }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(term.lines.enumerated()), id: \.offset) { _, l in
                                Text(row(l)).frame(height: Self.lh, alignment: .leading).fixedSize()
                            }
                        }
                        if term.cursor.on {
                            Rectangle().fill(Self.color(term.fg).opacity(0.6))
                                .frame(width: Self.cw, height: Self.lh)
                                .offset(x: CGFloat(term.cursor.x) * Self.cw, y: CGFloat(term.cursor.y) * Self.lh)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Self.color(term.fg))
                    .padding(8)
                }
                .defaultScrollAnchor(.bottomLeading)
                .background(Self.color(term.bg))
                .onTapGesture { typing = true }
                TextField("", text: $buf)
                    .focused($typing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .onChange(of: buf) { old, new in
                        // the field keeps one space, so a backspace always has something to take
                        if new == " " { return }
                        if new.count < old.count || new.isEmpty {
                            key("Backspace")
                        } else if new.hasPrefix(" ") {
                            let typed = String(new.dropFirst())
                            if !typed.isEmpty { model.act("term-paste", typed) }
                        }
                        if buf != " " { buf = " " }
                    }
                    .onSubmit { key("Enter"); typing = true }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button("esc") { key("Escape") }
                        Button("tab") { key("Tab") }
                        Button("^C") { key("c", 4) }
                        Button("^D") { key("d", 4) }
                        Button("^Z") { key("z", 4) }
                        Button("^L") { key("l", 4) }
                        Button { key("ArrowLeft") } label: { Image(systemName: "arrow.left") }
                        Button { key("ArrowUp") } label: { Image(systemName: "arrow.up") }
                        Button { key("ArrowDown") } label: { Image(systemName: "arrow.down") }
                        Button { key("ArrowRight") } label: { Image(systemName: "arrow.right") }
                        Button { typing.toggle() } label: { Image(systemName: typing ? "keyboard.chevron.compact.down" : "keyboard") }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.monospaced())
                    .padding(.horizontal).padding(.vertical, 6)
                }
                .background(.bar)
            }
            .navigationTitle(term.title.isEmpty ? "Terminal" : term.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Self.color(term.bg), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { model.act("term-toggle") } }
            }
            .onAppear { typing = true }
        }
    }
}

// thread search or the file picker: a field over the rows; a row sends its
// action with its value, then the sheet closes
struct FindSheet: View {
    let model: AppModel
    let find: Find
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(find.rows, id: \.self) { r in
                    Button {
                        model.act(r.action, r.value)
                        model.act("find-close")
                    } label: {
                        Label(r.label, systemImage: r.kind == "file" ? "doc" : r.kind == "thread" ? "bubble.left" : "bolt")
                            .lineLimit(2)
                    }
                    .tint(.primary)
                }
            }
            .overlay {
                if find.rows.isEmpty {
                    ContentUnavailableView(find.query.isEmpty ? (find.mode == "files" ? "Type to find a file" : "Type to search threads") : "Nothing found",
                                           systemImage: "magnifyingglass")
                }
            }
            .safeAreaInset(edge: .top) {
                TextField(find.mode == "files" ? "File name" : "Titles and messages", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
                    .padding(.horizontal).padding(.vertical, 8)
                    .background(.bar)
                    .onChange(of: text) { _, t in model.act("find-q", t) }
            }
            .navigationTitle(find.mode == "files" ? "Find file" : "Search threads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.act("find-close") } }
            }
            .onAppear { text = find.query; focused = true }
        }
    }
}

// the hub's settings, as the desktop has them
struct SettingsSheet: View {
    let model: AppModel
    let settings: Settings
    let version: String

    var body: some View {
        NavigationStack {
            Form {
                ForEach(settings.rows, id: \.self) { r in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(r.label)
                            if !r.note.isEmpty { Text(r.note).font(.footnote).foregroundStyle(.secondary) }
                            if !r.buttons.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(r.buttons, id: \.self) { b in
                                            if b.on {
                                                Button(b.label) { model.act(b.action, b.value) }.buttonStyle(.borderedProminent)
                                            } else {
                                                Button(b.label) { model.act(b.action, b.value) }.buttonStyle(.bordered)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { model.act("flag", "settings") } }
            }
        }
    }
}
