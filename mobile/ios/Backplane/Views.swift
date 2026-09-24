import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @State private var pairing = false

    var body: some View {
        if model.links.isEmpty {
            NavigationStack { PairView(link: "") { model.pair($0) } }
        } else if let s = model.screen {
            NavigationStack(path: Binding(get: { model.path }, set: { model.navigate($0) })) {
                ProjectsView(model: model, screen: s, pairing: $pairing)
                    .navigationDestination(for: String.self) { _ in
                        if let t = model.screen?.thread { ThreadScreen(model: model, thread: t) }
                    }
            }
            .alert(s.error, isPresented: Binding(get: { !s.error.isEmpty }, set: { if !$0 { model.act("dismiss") } })) {
                Button("OK") { model.act("dismiss") }
            }
            .sheet(isPresented: $pairing) {
                NavigationStack {
                    HubsView(model: model, screen: model.screen ?? s)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { pairing = false } } }
                }
            }
        } else {
            ProgressView()
        }
    }
}

struct PairView: View {
    @State var link: String
    let done: (String) -> Void

    var body: some View {
        Form {
            Section {
                TextField("Pairing link", text: $link, prompt: Text(verbatim: "http://host:3787/#token=…"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("Pairing link")
            } footer: {
                Text("Paste the tailnet link Backplane shows under Settings, Remote access.")
            }
            Button("Connect") { done(link) }.disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .navigationTitle("Pair with a hub")
    }
}

// the hubs this phone is paired with (swipe to unpair), the owner's other
// machines they know of (one tap pairs), and a field for a new link
struct HubsView: View {
    let model: AppModel
    let screen: Screen
    @State private var link = ""

    var body: some View {
        Form {
            Section("Paired") {
                ForEach(screen.hubs, id: \.key) { h in
                    HStack {
                        Image(systemName: h.online ? "circle.fill" : "circle.dotted")
                            .font(.caption).foregroundStyle(h.online ? .green : .secondary)
                        Text(h.name)
                        Spacer()
                        Text(h.key).font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions { Button("Unpair", role: .destructive) { model.unpair(h.key) } }
                }
            }
            if !screen.found.isEmpty {
                Section("On your tailnet") {
                    ForEach(screen.found, id: \.url) { f in
                        Button { model.pair(f.url) } label: {
                            HStack {
                                Text(f.name)
                                Spacer()
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                }
            }
            Section {
                TextField("Pairing link", text: $link, prompt: Text(verbatim: "http://host:3787/#token=…"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Add hub") { model.pair(link); link = "" }.disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Pair another")
            } footer: {
                Text("Paste the tailnet link Backplane shows under Settings, Remote access.")
            }
        }
        .navigationTitle("Hubs")
    }
}

private struct Status: View {
    let state: String

    var body: some View {
        switch state {
        case "run": ProgressView().controlSize(.mini)
        case "fail": Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case "stop": Image(systemName: "stop.circle").foregroundStyle(.orange)
        default: Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.quaternary)
        }
    }
}

private struct SwipeButton: View {
    let model: AppModel
    let swipe: Swipe
    let choose: (Swipe) -> Void

    private var icon: String {
        switch swipe.action {
        case "row-delete": "trash"
        case "row-settle": "checkmark.circle"
        case "row-unsettle": "arrow.uturn.backward"
        default: swipe.options.isEmpty ? "sun.max" : "moon.zzz"
        }
    }

    private var tint: Color {
        switch swipe.tone {
        case "danger": .red
        case "settle": .green
        default: .indigo
        }
    }

    var body: some View {
        Button {
            if swipe.options.isEmpty { model.act(swipe.action, swipe.value) } else { choose(swipe) }
        } label: {
            Label(swipe.label, systemImage: icon)
        }
        .tint(tint)
    }
}

private struct ThreadRow: View {
    let model: AppModel
    let row: Row
    let choose: (Swipe) -> Void

    var body: some View {
        NavigationLink(value: row.id) {
            HStack(spacing: 10) {
                Status(state: row.state).frame(width: 18)
                Text(row.title).lineLimit(1)
                Spacer()
                if row.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                Text(row.ago).font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .leading) {
            ForEach(row.lead, id: \.self) { SwipeButton(model: model, swipe: $0, choose: choose) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            ForEach(row.trail, id: \.self) { SwipeButton(model: model, swipe: $0, choose: choose) }
        }
    }
}

struct ProjectsView: View {
    let model: AppModel
    let screen: Screen
    @Binding var pairing: Bool
    // a swipe whose choices are up (a snooze)
    @State private var choosing: Swipe?
    // the delete just answered: its dialog stays down until the screen drops it
    @State private var answered = ""

    var body: some View {
        List {
            ForEach(screen.projects) { p in
                Section {
                    ForEach(p.threads) { ThreadRow(model: model, row: $0) { choosing = $0 } }
                    if !p.snoozed.isEmpty {
                        Text(p.snoozedShelf).font(.subheadline).foregroundStyle(.secondary)
                        ForEach(p.snoozed) { ThreadRow(model: model, row: $0) { choosing = $0 } }
                    }
                    if !p.settled.isEmpty {
                        Button { model.act("toggle-settled", p.id) } label: {
                            HStack {
                                Text(p.shelf).font(.subheadline)
                                Spacer()
                                Image(systemName: p.open ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.secondary)
                        if p.open { ForEach(p.settled) { ThreadRow(model: model, row: $0) { choosing = $0 } } }
                    }
                } header: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.title)
                            Text(p.machine.isEmpty ? p.root : p.machine + ": " + p.root)
                                .font(.caption2).textCase(nil).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Button { model.act("new-thread", p.id) } label: { Image(systemName: "square.and.pencil") }
                            .accessibilityLabel("New thread")
                    }
                }
            }
        }
        .overlay {
            if screen.projects.isEmpty { ContentUnavailableView(screen.empty, systemImage: "folder") }
        }
        .navigationTitle("Backplane")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Label(screen.online ? "Connected" : "Connecting", systemImage: screen.online ? "circle.fill" : "circle.dotted")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(screen.online ? .green : .secondary)
                    .font(.caption)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                // with several hubs, the picker opens on the one chosen
                if screen.hubs.count > 1 {
                    Menu {
                        ForEach(screen.hubs, id: \.key) { h in Button(h.name) { model.act("picker-open", h.key + "|") } }
                    } label: { Image(systemName: "folder.badge.plus") }
                    .accessibilityLabel("Add project")
                } else {
                    Button { model.act("picker-open") } label: { Image(systemName: "folder.badge.plus") }.accessibilityLabel("Add project")
                }
                Button { pairing = true } label: { Image(systemName: "link") }.accessibilityLabel("Hubs")
            }
        }
        .confirmationDialog(choosing?.label ?? "", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }),
                            titleVisibility: .visible, presenting: choosing) { s in
            ForEach(s.options, id: \.self) { o in Button(o.label) { model.act(s.action, o.value) } }
        }
        .alert(screen.deleting?.title ?? "", isPresented: Binding(get: { screen.deleting.map { $0.id != answered } ?? false }, set: { _ in }),
               presenting: screen.deleting) { d in
            Button(d.yes, role: .destructive) { answered = d.id; model.act("row-delete", d.id) }
            Button(d.no, role: .cancel) { answered = d.id; model.act("delete-no") }
        } message: { d in
            Text(d.body)
        }
        .onChange(of: screen.deleting?.id) { answered = "" }
        .sheet(isPresented: Binding(get: { screen.folders != nil }, set: { if !$0 { model.act("proj-close") } })) {
            if let f = screen.folders { FoldersSheet(model: model, folders: f) }
        }
    }
}

// the project picker: a path field over the listed folder's rows
private struct FoldersSheet: View {
    let model: AppModel
    let folders: Folders
    @State private var text = ""
    // what was typed here: a screen still echoing it never overwrites the field
    @State private var typed: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(folders.hint, text: $text)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: text) { _, t in
                            guard t != folders.text else { return }
                            typed.insert(t)
                            model.act("picker-type", t)
                        }
                    if !folders.error.isEmpty { Text(folders.error).font(.footnote).foregroundStyle(.red) }
                }
                Section {
                    ForEach(folders.items, id: \.self) { r in
                        Button { model.act(r.action, r.value) } label: {
                            Label(r.label, systemImage: Self.icon(r.kind)).lineLimit(1).truncationMode(.head)
                        }
                        .disabled(r.action.isEmpty)
                        .tint(r.kind == "dir" || r.kind == "up" ? .primary : .accentColor)
                    }
                }
            }
            .navigationTitle("Add project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.act("proj-close") } }
            }
        }
        .onAppear { text = folders.text }
        .onChange(of: folders.text) { _, t in
            if !typed.contains(t) { typed = []; text = t }
        }
    }

    static func icon(_ kind: String) -> String {
        switch kind {
        case "up": "arrow.turn.left.up"
        case "add": "plus.circle"
        case "new": "folder.badge.plus"
        case "mkdir": "folder.badge.plus"
        case "off": "checkmark.circle"
        default: "folder"
        }
    }
}

private struct EntryView: View {
    let model: AppModel
    let entry: Entry

    var body: some View {
        switch entry.kind {
        case "user":
            HStack {
                Spacer(minLength: 48)
                Text(entry.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 18))
                    .contextMenu { Button("Copy", systemImage: "doc.on.doc") { model.act("copy", entry.text) } }
            }
        case "assistant":
            MarkdownView(blocks: entry.blocks ?? [])
                .contextMenu { Button("Copy", systemImage: "doc.on.doc") { model.act("copy", entry.text) } }
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

struct ThreadScreen: View {
    @Bindable var model: AppModel
    let thread: ThreadView
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(thread.entries) { EntryView(model: model, entry: $0).id($0.id) }
                    ForEach(Array(thread.sending.enumerated()), id: \.offset) { _, text in
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(text)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 18))
                            Text("Sending…").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .opacity(0.7)
                    }
                    if !thread.live.isEmpty {
                        MarkdownView(blocks: thread.live)
                    } else if !thread.working.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(thread.working).foregroundStyle(.secondary)
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.scrolls) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: thread.entries.count) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
        .safeAreaInset(edge: .bottom) {
          VStack(spacing: 0) {
            if !thread.queued.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text("Queued: ").bold() + Text(thread.queued)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal).padding(.top, 8)
                .accessibilityHint("Sends when this turn ends")
            }
            HStack {
                Menu {
                    Section("Model") {
                        ForEach(thread.picker.models, id: \.value) { c in
                            Button { model.act("model", c.value) } label: {
                                if c.on { Label(c.label, systemImage: "checkmark") } else { Text(c.label) }
                            }
                        }
                    }
                    if !thread.picker.efforts.isEmpty {
                        Section("Effort") {
                            ForEach(thread.picker.efforts, id: \.value) { c in
                                Button { model.act("effort", c.value) } label: {
                                    if c.on { Label(c.label, systemImage: "checkmark") } else { Text(c.label) }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(thread.picker.label).lineLimit(1)
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Model and effort: " + thread.picker.label)
                Spacer(minLength: 0)
            }
            .padding(.horizontal).padding(.top, 8)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask the agent", text: Binding(get: { model.composer }, set: { model.draft($0) }), axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
                Button { model.act("send") } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                }
                .disabled(model.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(thread.send)
            }
            .padding(.horizontal).padding(.vertical, 8)
          }
          .background(.bar)
        }
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: Binding(get: { !thread.viewer.open.isEmpty }, set: { if !$0 { model.act("view", "") } })) {
            if let v = model.screen?.thread?.viewer { PlotScreen(model: model, viewer: v) }
        }
        .toolbar {
            if !thread.branch.isEmpty {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(thread.title).font(.headline).lineLimit(1)
                        Text(thread.branch).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !thread.viewer.choices.isEmpty {
                    Menu {
                        ForEach(thread.viewer.choices, id: \.value) { c in
                            Button(c.label) { model.act("view", c.value) }
                        }
                    } label: {
                        Image(systemName: "cpu")
                    }
                    .accessibilityLabel("Board viewer")
                }
                ForEach(thread.tools.filter { $0.action == "interrupt" }, id: \.self) { t in
                    Button(t.label, systemImage: "stop.fill") { model.act(t.action) }
                }
                Menu {
                    ForEach(thread.tools.filter { $0.action != "interrupt" }, id: \.self) { t in
                        Button { model.act(t.action) } label: {
                            if t.on { Label(t.label, systemImage: "checkmark") } else { Text(t.label) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}
