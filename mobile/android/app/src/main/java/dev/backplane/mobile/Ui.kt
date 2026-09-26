package dev.backplane.mobile

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Folder
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

@Composable
fun App(m: AppModel) {
    var pairing by rememberSaveable { mutableStateOf(false) }
    val s = m.screen
    when {
        m.links.isEmpty() -> Pair("", cancel = null) { m.pair(it) }
        s == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        pairing -> {
            BackHandler { pairing = false }
            Hubs(m, s) { pairing = false }
        }
        s.thread != null && s.thread.viewer.open.isNotEmpty() -> {
            BackHandler { m.act("view", "") }
            PlotScreen(m, s.thread.viewer)
        }
        // the thread's shell, in place of the screen so it follows the keyboard
        s.thread?.term != null -> {
            BackHandler { m.act("term-toggle") }
            TermSheet(m, s.thread.term)
        }
        // a bot (its chat is its thread), a room, or a bot on a linked machine
        s.bot != null -> {
            BackHandler { m.act("select", "") }
            BotDestination(m, s, s.bot)
        }
        s.thread != null -> {
            BackHandler { m.act("select", "") }
            ThreadScreen(m, s, s.thread)
        }
        else -> Projects(m, s, onPair = { pairing = true })
    }
    if (s == null || m.links.isEmpty()) return
    val d = s.deleting
    // the delete just answered: its dialog stays down until the screen drops it
    var answered by remember(d?.id) { mutableStateOf(false) }
    if (d != null && !answered) AlertDialog(
        onDismissRequest = { answered = true; m.act("delete-no") },
        title = { Text(d.title) },
        text = { Text(d.body) },
        confirmButton = {
            TextButton(onClick = { answered = true; m.act("row-delete", d.id) }) {
                Text(d.yes, color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = { TextButton(onClick = { answered = true; m.act("delete-no") }) { Text(d.no) } },
    )
    val r = s.removing
    // likewise the remove just answered
    var removed by remember(r?.id) { mutableStateOf(false) }
    if (r != null && !removed) AlertDialog(
        onDismissRequest = { removed = true; m.act("proj-keep") },
        title = { Text(r.title) },
        text = { Text(r.body) },
        confirmButton = {
            TextButton(onClick = { removed = true; m.act("proj-remove", r.id) }) {
                Text(r.yes, color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = { TextButton(onClick = { removed = true; m.act("proj-keep") }) { Text(r.no) } },
    )
    s.settings?.let { SettingsSheet(m, it) }
    s.find?.let { FindSheet(m, it) }
}

// the project search's field: typing filters the list ("proj-find-q"),
// Go goes to the first project shown ("proj-go"), the x shuts it
@Composable
private fun SearchField(m: AppModel, f: Search, first: String?) {
    var text by remember { mutableStateOf(f.query) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    OutlinedTextField(text, { t -> text = t; if (t != f.query) m.act("proj-find-q", t) },
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).focusRequester(focus),
        singleLine = true, placeholder = { Text(f.hint) },
        leadingIcon = { Icon(Icons.Filled.Search, null) },
        trailingIcon = { IconButton(onClick = { m.act("proj-find", "off") }) { Icon(Icons.Filled.Close, "Close search") } },
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Go),
        keyboardActions = KeyboardActions(onGo = { first?.let { m.act("proj-go", it) } }))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Pair(link: String, cancel: (() -> Unit)?, done: (String) -> Unit) {
    var text by rememberSaveable { mutableStateOf(link) }
    Scaffold(topBar = {
        TopAppBar(title = { Text("Pair with a hub") }, navigationIcon = {
            if (cancel != null) IconButton(onClick = cancel) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
        })
    }) { pad ->
        Column(Modifier.padding(pad).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Paste the tailnet link Backplane shows in Settings (Pairing link).",
                style = MaterialTheme.typography.bodyMedium)
            OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth(), singleLine = true,
                label = { Text("Pairing link") }, placeholder = { Text("http://host:3787/#token=…") })
            Button(onClick = { done(text) }, enabled = text.isNotBlank()) { Text("Connect") }
        }
    }
}

// the hubs this phone is paired with (the cross unpairs), the owner's
// other machines they know of (one tap pairs), and a field for a new link
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Hubs(m: AppModel, s: Screen, back: () -> Unit) {
    var text by rememberSaveable { mutableStateOf("") }
    Scaffold(topBar = {
        TopAppBar(title = { Text("Hubs") }, navigationIcon = {
            IconButton(onClick = back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
        })
    }) { pad ->
        LazyColumn(Modifier.fillMaxSize(), contentPadding = pad) {
            items(s.hubs, key = { "h:" + it.key }) { h ->
                ListItem(
                    headlineContent = { Text(h.name) },
                    supportingContent = { Text(h.key) },
                    leadingContent = { Status(if (h.online) "idle" else "stop") },
                    trailingContent = { IconButton(onClick = { m.unpair(h.key) }) { Icon(Icons.Filled.Close, "Unpair") } },
                )
            }
            if (s.found.isNotEmpty()) {
                item(key = "found") {
                    Text("On your tailnet", Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.outline)
                }
                items(s.found, key = { "f:" + it.url }) { f ->
                    ListItem(
                        headlineContent = { Text(f.name) },
                        supportingContent = { Text(f.url) },
                        trailingContent = { IconButton(onClick = { m.pair(f.url) }) { Icon(Icons.Filled.Add, "Pair") } },
                    )
                }
            }
            item(key = "add") {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Paste the tailnet link Backplane shows in Settings (Pairing link).",
                        style = MaterialTheme.typography.bodyMedium)
                    OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth(), singleLine = true,
                        label = { Text("Pairing link") }, placeholder = { Text("http://host:3787/#token=…") })
                    Button(onClick = { m.pair(text); text = "" }, enabled = text.isNotBlank()) { Text("Add hub") }
                }
            }
        }
    }
}

@Composable
private fun Errors(m: AppModel, s: Screen, host: SnackbarHostState) {
    LaunchedEffect(s.error) {
        if (s.error.isNotEmpty()) {
            val r = host.showSnackbar(s.error, actionLabel = "Dismiss", withDismissAction = false)
            if (r == SnackbarResult.ActionPerformed || r == SnackbarResult.Dismissed) m.act("dismiss")
        }
    }
}

@Composable
private fun Status(state: String) {
    Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
        when (state) {
            "run" -> CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
            else -> Box(Modifier.size(8.dp).clip(CircleShape).background(
                when (state) {
                    "fail" -> MaterialTheme.colorScheme.error
                    "stop" -> MaterialTheme.colorScheme.tertiary
                    else -> MaterialTheme.colorScheme.outlineVariant
                }))
        }
    }
}

@Composable
private fun swipeColor(s: Swipe?): Color = when (s?.tone) {
    "danger" -> MaterialTheme.colorScheme.errorContainer
    "settle" -> MaterialTheme.colorScheme.primaryContainer
    else -> MaterialTheme.colorScheme.secondaryContainer
}

// Swiping from the start sends the row's lead action; from the end it
// opens the trail's (delete, snooze and its choices). The row always
// springs back: what happens to the thread comes with the next screen.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ThreadRow(m: AppModel, r: Row) {
    var menu by remember { mutableStateOf(false) }
    val lead = r.lead.firstOrNull()
    val state = rememberSwipeToDismissBoxState(confirmValueChange = {
        when (it) {
            SwipeToDismissBoxValue.StartToEnd -> lead?.let { l -> m.act(l.action, l.value) }
            SwipeToDismissBoxValue.EndToStart -> menu = true
            SwipeToDismissBoxValue.Settled -> {}
        }
        false
    })
    Box {
        SwipeToDismissBox(
            state,
            enableDismissFromStartToEnd = lead != null,
            enableDismissFromEndToStart = r.trail.isNotEmpty(),
            backgroundContent = {
                val start = state.dismissDirection == SwipeToDismissBoxValue.StartToEnd
                Box(Modifier.fillMaxSize().background(swipeColor(if (start) lead else r.trail.firstOrNull()))
                    .padding(horizontal = 24.dp), contentAlignment = if (start) Alignment.CenterStart else Alignment.CenterEnd) {
                    Text(if (start) lead?.label ?: "" else r.trail.joinToString(" · ") { it.label },
                        style = MaterialTheme.typography.labelLarge)
                }
            },
        ) {
            ListItem(
                headlineContent = { Text(r.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                leadingContent = { StatusDot(r.state, r.status) },
                trailingContent = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (r.pinned) Icon(Icons.Filled.PushPin, "Pinned", Modifier.size(16.dp).padding(end = 4.dp))
                        Text(r.ago, style = MaterialTheme.typography.labelMedium)
                    }
                },
                modifier = Modifier.combinedClickableCompat { m.act("select", r.id) },
            )
        }
        Box(Modifier.align(Alignment.TopEnd)) {
            DropdownMenu(menu, { menu = false }) {
                for (t in r.trail) {
                    if (t.options.isEmpty()) DropdownMenuItem(
                        text = { Text(t.label, color = if (t.tone == "danger") MaterialTheme.colorScheme.error else Color.Unspecified) },
                        onClick = { menu = false; m.act(t.action, t.value) },
                    ) else {
                        HorizontalDivider()
                        Text(t.label, Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                            style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.outline)
                        for (o in t.options) DropdownMenuItem(text = { Text(o.label) }, onClick = { menu = false; m.act(t.action, o.value) })
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
internal fun Modifier.combinedClickableCompat(onLong: (() -> Unit)? = null, onClick: () -> Unit) =
    this.combinedClickable(onClick = onClick, onLongClick = onLong)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Projects(m: AppModel, s: Screen, onPair: () -> Unit) {
    val snacks = remember { SnackbarHostState() }
    var choosing by remember { mutableStateOf(false) }
    var more by remember { mutableStateOf(false) }
    Errors(m, s, snacks)
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Backplane")
                        Text(if (s.online) "Connected" else "Connecting…",
                            style = MaterialTheme.typography.labelMedium,
                            color = if (s.online) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline)
                    }
                },
                actions = {
                    // with several hubs, the picker opens on the one chosen
                    Box {
                        IconButton(onClick = { if (s.hubs.size > 1) choosing = true else m.act("picker-open") }) {
                            Icon(Icons.Filled.CreateNewFolder, "Add project")
                        }
                        DropdownMenu(choosing, { choosing = false }) {
                            for (h in s.hubs) DropdownMenuItem(text = { Text(h.name) }, onClick = {
                                choosing = false
                                m.act("picker-open", h.key + "|")
                            })
                        }
                    }
                    IconButton(onClick = { m.act("proj-find", if (s.search?.open == true) "off" else "on") }) {
                        Icon(Icons.Filled.Search, "Find a project")
                    }
                    IconButton(onClick = onPair) { Icon(Icons.Filled.Link, "Hubs") }
                    Box {
                        IconButton(onClick = { more = true }) { Icon(Icons.Filled.MoreVert, "More") }
                        DropdownMenu(more, { more = false }) {
                            DropdownMenuItem(text = { Text("Search threads") }, leadingIcon = { Icon(Icons.Filled.Search, null) },
                                onClick = { more = false; m.act("find-open", "search") })
                            DropdownMenuItem(text = { Text("Settings") }, leadingIcon = { Icon(Icons.Filled.Settings, null) },
                                onClick = { more = false; m.act("flag", "settings") })
                        }
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snacks) },
    ) { pad ->
        if (s.projects.isEmpty() && s.bots.isEmpty() && s.rooms.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(pad), contentAlignment = Alignment.Center) {
                Text(s.empty, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.outline)
            }
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = pad) {
            s.search?.takeIf { it.open }?.let { f -> item(key = "find") { SearchField(m, f, s.projects.firstOrNull()?.id) } }
            for (p in s.projects) {
                item(key = "p:" + p.id) {
                    // a long press offers to remove the project
                    var menu by remember { mutableStateOf(false) }
                    Box {
                    ListItem(
                        headlineContent = { Text(p.title, style = MaterialTheme.typography.titleMedium) },
                        supportingContent = {
                            Text(if (p.machine.isEmpty()) p.root else p.machine + ": " + p.root,
                                maxLines = 1, overflow = TextOverflow.Ellipsis)
                        },
                        trailingContent = {
                            IconButton(onClick = { m.act("new-thread", p.id) }) { Icon(Icons.Filled.Add, "New thread") }
                        },
                        modifier = Modifier.combinedClickableCompat(onLong = { menu = true }) {},
                    )
                    DropdownMenu(menu, { menu = false }) {
                        DropdownMenuItem(text = { Text("Remove project") }, leadingIcon = { Icon(Icons.Filled.Delete, null) },
                            onClick = { menu = false; m.act("proj-remove", p.id) })
                    }
                    }
                }
                items(p.threads, key = { "t:" + it.id }) { ThreadRow(m, it) }
                if (p.snoozed.isNotEmpty()) {
                    item(key = "z:" + p.id) {
                        ListItem(headlineContent = { Text(p.snoozedShelf, style = MaterialTheme.typography.labelLarge) })
                    }
                    items(p.snoozed, key = { "t:" + it.id }) { ThreadRow(m, it) }
                }
                if (p.settled.isNotEmpty()) {
                    item(key = "s:" + p.id) {
                        ListItem(
                            headlineContent = { Text(p.shelf, style = MaterialTheme.typography.labelLarge) },
                            trailingContent = {
                                Icon(if (p.open) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null)
                            },
                            modifier = Modifier.combinedClickableCompat { m.act("toggle-settled", p.id) },
                        )
                    }
                    if (p.open) items(p.settled, key = { "t:" + it.id }) { ThreadRow(m, it) }
                }
                if (p.archived.isNotEmpty() && p.value.isNotEmpty()) {
                    item(key = "a:" + p.id) {
                        ListItem(
                            headlineContent = { Text("Archived ${p.archived.size}", style = MaterialTheme.typography.labelLarge) },
                            trailingContent = {
                                Icon(if (p.archOpen) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null)
                            },
                            modifier = Modifier.combinedClickableCompat { m.act("toggle-settled", p.value) },
                        )
                    }
                    if (p.archOpen) items(p.archived, key = { "t:" + it.id }) { ThreadRow(m, it) }
                }
                item(key = "d:" + p.id) { HorizontalDivider() }
            }
            if (s.hubs.isNotEmpty()) botsSection(m, s)
        }
    }
    s.folders?.let { FolderPicker(m, it) }
    s.newBot?.let { NewBotDialog(m, it) }
    s.newRoom?.let { NewRoomDialog(m, it) }
}

// the project picker: a path field over the listed folder's rows
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FolderPicker(m: AppModel, p: Folders) {
    var text by remember { mutableStateOf(p.text) }
    // what was typed here: a screen still echoing it never overwrites the field
    val typed = remember { mutableSetOf<String>() }
    LaunchedEffect(p.text) {
        if (p.text !in typed) { typed.clear(); text = p.text }
    }
    Dialog(onDismissRequest = { m.act("proj-close") }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Add project") },
                    navigationIcon = { IconButton(onClick = { m.act("proj-close") }) { Icon(Icons.Filled.Close, "Cancel") } },
                )
            },
        ) { pad ->
            Column(Modifier.fillMaxSize().padding(pad).imePadding()) {
                OutlinedTextField(text, { t ->
                    text = t
                    typed.add(t)
                    m.act("picker-type", t)
                }, Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), singleLine = true,
                    placeholder = { Text(p.hint) }, textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false))
                if (p.error.isNotEmpty()) Text(p.error, Modifier.padding(horizontal = 16.dp),
                    color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                LazyColumn(Modifier.fillMaxSize()) {
                    items(p.items) { r ->
                        val icon = when (r.kind) {
                            "up" -> Icons.Filled.ArrowUpward
                            "add" -> Icons.Filled.AddCircleOutline
                            "new", "mkdir" -> Icons.Filled.CreateNewFolder
                            "off" -> Icons.Filled.Check
                            else -> Icons.Filled.Folder
                        }
                        val tone = if (r.kind == "dir" || r.kind == "up") MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.primary
                        ListItem(
                            headlineContent = { Text(r.label, maxLines = 1, overflow = TextOverflow.Ellipsis, color = tone) },
                            leadingContent = { Icon(icon, null, tint = tone) },
                            modifier = (if (r.action.isEmpty()) Modifier.alpha(0.5f) else Modifier.combinedClickableCompat { m.act(r.action, r.value) }),
                        )
                    }
                }
            }
        }
    }
}

// a message the hub has not stored yet
@Composable
private fun SendingView(text: String) {
    Column(Modifier.fillMaxWidth().alpha(0.55f), horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth()) {
            Spacer(Modifier.weight(1f).widthIn(min = 48.dp))
            Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = MaterialTheme.shapes.large) {
                Text(text, Modifier.padding(horizontal = 14.dp, vertical = 10.dp), style = MaterialTheme.typography.bodyLarge)
            }
        }
        Text("Sending…", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
    }
}

// below: more under the top bar (a bot's cat and tabs)
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ThreadScreen(m: AppModel, s: Screen, t: ThreadView, below: (@Composable () -> Unit)? = null) {
    val snacks = remember { SnackbarHostState() }
    val list = rememberLazyListState()
    var menu by remember { mutableStateOf(false) }
    // the image open in the lightbox
    var shown by remember { mutableStateOf<String?>(null) }
    val termSize = rememberTermSize()
    Errors(m, s, snacks)
    val count = (if (t.parent != null) 1 else 0) + (if (t.tasks.isNotEmpty()) 1 else 0) +
        (if (t.earlier > 0) 1 else 0) + t.entries.size + t.sending.size + (if (t.live.isNotEmpty() || t.working.isNotEmpty()) 1 else 0)
    LaunchedEffect(t.id, m.scrolls) { if (count > 0) list.scrollToItem(count - 1) }
    LaunchedEffect(count, t.live) {
        val last = list.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
        if (count > 0 && last >= count - 3) list.animateScrollToItem(count - 1)
    }
    Scaffold(
        // opaque, so the entries scrolled under it (a bot's cat and tabs) never show through
        topBar = { Column(Modifier.background(MaterialTheme.colorScheme.surface)) {
            TopAppBar(
                navigationIcon = { IconButton(onClick = { m.act("select", "") }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                title = {
                    Column {
                        Text(t.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (t.branch.isNotEmpty()) Text(t.branch, style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.outline, maxLines = 1)
                    }
                },
                actions = {
                    if (t.viewer.choices.isNotEmpty()) Box {
                        var boards by remember { mutableStateOf(false) }
                        IconButton(onClick = { boards = true }) { Icon(Icons.Filled.Memory, "Board viewer") }
                        DropdownMenu(boards, { boards = false }) {
                            for (c in t.viewer.choices) DropdownMenuItem(
                                text = { Text(c.label) },
                                onClick = { boards = false; m.act("view", c.value) },
                            )
                        }
                    }
                    for (tool in t.tools) if (tool.action == "interrupt")
                        IconButton(onClick = { m.act(tool.action) }) { Icon(Icons.Filled.Stop, tool.label) }
                    Box {
                        IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "More") }
                        DropdownMenu(menu, { menu = false }) {
                            for (tool in t.tools) if (tool.action != "interrupt") DropdownMenuItem(
                                text = { Text(tool.label) },
                                leadingIcon = { if (tool.on) Icon(Icons.Filled.Check, null) else Spacer(Modifier.width(24.dp)) },
                                onClick = { menu = false; m.act(tool.action, tool.value) },
                            )
                            if (t.menu.isNotEmpty()) HorizontalDivider()
                            for (item in t.menu) {
                                if (item.options.isNotEmpty()) {
                                    Text(item.label, Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                        style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.outline)
                                    for (o in item.options) DropdownMenuItem(
                                        text = { Text(o.label) },
                                        leadingIcon = { Spacer(Modifier.width(24.dp)) },
                                        onClick = { menu = false; m.act(item.action, o.value) },
                                    )
                                } else DropdownMenuItem(
                                    text = { Text(item.label, color = if (item.danger) MaterialTheme.colorScheme.error else Color.Unspecified) },
                                    leadingIcon = {
                                        val icon = menuIcon(item.action)
                                        when {
                                            item.on -> Icon(Icons.Filled.Check, null)
                                            icon != null -> Icon(icon, null, tint = if (item.danger) MaterialTheme.colorScheme.error else Color.Unspecified)
                                            else -> Spacer(Modifier.width(24.dp))
                                        }
                                    },
                                    onClick = {
                                        menu = false
                                        // the terminal opens at the size this phone has room for
                                        m.act(item.action, if (item.action == "term-toggle") termSize() else item.value)
                                    },
                                )
                            }
                        }
                    }
                },
            )
            below?.invoke()
        } },
        bottomBar = {
            Surface(tonalElevation = 3.dp) {
                Column(Modifier.fillMaxWidth().navigationBarsPadding().imePadding().padding(8.dp)) {
                    for (a in t.asks) Box(Modifier.padding(bottom = 8.dp)) { AskCard(m, a) }
                    t.todos?.let { td ->
                        Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp)) {
                            Text(td.head, style = MaterialTheme.typography.labelMedium)
                            for (l in td.lines) Text(l.text, style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                color = if (l.status == "completed") MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface)
                        }
                    }
                    for (q in t.queue) Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(q.tag, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.tertiary)
                        Text(q.text, Modifier.weight(1f).padding(horizontal = 8.dp),
                            style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.outline,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                        for (b in q.buttons) TextButton(onClick = { m.act(b.action, b.value) }) {
                            Text(b.label, style = MaterialTheme.typography.labelSmall)
                        }
                    }
                    Box {
                        var models by remember { mutableStateOf(false) }
                        TextButton(onClick = { models = true }) {
                            Text(t.picker.label, style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.outline, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Icon(Icons.Filled.ExpandMore, "Choose the model and effort", Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.outline)
                        }
                        DropdownMenu(models, { models = false }) {
                            for (c in t.picker.models) DropdownMenuItem(
                                text = { Text(c.label) },
                                leadingIcon = { if (c.on) Icon(Icons.Filled.Check, null) else Spacer(Modifier.width(24.dp)) },
                                onClick = { models = false; m.act("model", c.value) },
                            )
                            if (t.picker.efforts.isNotEmpty()) {
                                HorizontalDivider()
                                for (c in t.picker.efforts) DropdownMenuItem(
                                    text = { Text("Effort: ${c.label}") },
                                    leadingIcon = { if (c.on) Icon(Icons.Filled.Check, null) else Spacer(Modifier.width(24.dp)) },
                                    onClick = { models = false; m.act("effort", c.value) },
                                )
                            }
                            // another provider takes the thread up from its next turn
                            if (t.picker.providers.isNotEmpty()) {
                                HorizontalDivider()
                                for (c in t.picker.providers) DropdownMenuItem(
                                    text = { Text("Provider: ${c.label}") },
                                    leadingIcon = { if (c.on) Icon(Icons.Filled.Check, null) else Spacer(Modifier.width(24.dp)) },
                                    onClick = { models = false; m.act("effort", c.value) },
                                )
                            }
                        }
                    }
                    ComposerExtras(m, t)
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        AttachButton(m)
                        OutlinedTextField(m.composer, m::draft, Modifier.weight(1f), maxLines = 6,
                            placeholder = { Text("Ask the agent") })
                        // a long press sends with the other follow-up mode (queue or steer);
                        // while a turn runs with nothing typed the button stops it
                        val stop = t.sendAct == "interrupt" && m.composer.isBlank()
                        Box(Modifier.size(48.dp).combinedClickableCompat(onLong = { if (m.composer.isNotBlank()) m.act("send-alt") }) {
                            if (stop) m.act("interrupt") else if (m.composer.isNotBlank()) m.act("send")
                        }, contentAlignment = Alignment.Center) {
                            if (stop) Icon(Icons.Filled.Stop, t.send, tint = MaterialTheme.colorScheme.error)
                            else Icon(Icons.AutoMirrored.Filled.Send, t.send,
                                tint = if (m.composer.isNotBlank()) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline)
                        }
                    }
                }
            }
        },
        snackbarHost = { SnackbarHost(snacks) },
    ) { pad ->
        LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(
            start = 16.dp, end = 16.dp, top = pad.calculateTopPadding() + 8.dp, bottom = pad.calculateBottomPadding() + 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            t.parent?.let { p -> item(key = "parent") { EntryRow(m, p) { shown = it } } }
            if (t.tasks.isNotEmpty()) item(key = "tasks") { TasksView(m, t.tasks) }
            if (t.earlier > 0) item(key = "earlier") {
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    TextButton(onClick = { m.act("earlier", "") }) { Text("Show earlier") }
                }
            }
            items(t.entries, key = { it.id }) { EntryRow(m, it) { u -> shown = u } }
            itemsIndexed(t.sending, key = { i, _ -> "sending:$i" }) { _, text -> SendingView(text) }
            if (t.live.isNotEmpty()) item(key = "live") { Markdown(t.live) }
            else if (t.working.isNotEmpty()) item(key = "live") {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(t.working, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.outline)
                    if (t.state == "run") LinearProgressIndicator(Modifier.width(120.dp))
                }
            }
        }
    }
    shown?.let { u -> Lightbox(u) { shown = null } }
    t.diff?.let { DiffSheet(m, it) }
}

// The board viewer over the thread: the plot of the screen's source, the
// source choices, and a way back.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PlotScreen(m: AppModel, v: Viewer) {
    // a plot for any other source is stale (a switch in flight)
    val f = m.plots.frame?.takeIf { it.key == v.layers }
    val mesh = m.plots.mesh?.takeIf { it.key == v.key }
    Box(Modifier.fillMaxSize().background(Color(0xFF000000.toInt() or v.bg))) {
        AndroidView(factory = { PlotSurface(it) }, modifier = Modifier.fillMaxSize(), update = { s ->
            s.margin = v.margin
            s.zmin = v.zmin
            s.zmax = v.zmax
            s.tap = v.tap
            s.fadeMs = v.fade
            s.onPick = { m.act("view-pick", it) }
            s.renderer.top = v.top
            s.renderer.bottom = v.bottom
            s.renderer.orbit.fov = v.fov
            s.setThree(v.open == "3d")
            if (f != null && f.none.isEmpty()) s.show(f, v.bg, v.slab)
            if (v.open == "3d") s.mesh(mesh)
            s.mark(v.picked)
        })
        when {
            f == null -> CircularProgressIndicator(Modifier.align(Alignment.Center))
            f.none.isNotEmpty() -> Text(f.none, Modifier.align(Alignment.Center), color = Color.Gray)
            v.open == "3d" && mesh != null && mesh.none.isNotEmpty() ->
                Text(mesh.none, Modifier.align(Alignment.BottomCenter).padding(16.dp), color = Color.Gray,
                    style = MaterialTheme.typography.labelMedium)
        }
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically) {
            SingleChoiceSegmentedButtonRow(Modifier.widthIn(max = 300.dp)) {
                v.choices.forEachIndexed { i, c ->
                    SegmentedButton(selected = c.value == v.open, onClick = { m.act("view", c.value) },
                        shape = SegmentedButtonDefaults.itemShape(i, v.choices.size)) { Text(c.label) }
                }
            }
            Spacer(Modifier.weight(1f))
            IconButton(onClick = { m.act("view", "") }) { Icon(Icons.Filled.Close, "Close", tint = Color.White) }
        }
        v.card?.let { c -> PlotCard(m, c, Modifier.align(Alignment.BottomCenter)) }
    }
}

// what a tapped item is, as the window's inspector shows it
@Composable
private fun PlotCard(m: AppModel, c: Card, modifier: Modifier) {
    Surface(modifier.fillMaxWidth().navigationBarsPadding().padding(12.dp), tonalElevation = 6.dp) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(c.title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                IconButton(onClick = { m.act("view-unpick") }) { Icon(Icons.Filled.Close, "Close") }
            }
            for ((k, value) in c.rows) Row {
                Text(k, Modifier.width(92.dp), color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.bodyMedium)
                Text(value, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            Button(onClick = { m.act("view-mention", c.info) }) { Text("Mention in chat") }
        }
    }
}
