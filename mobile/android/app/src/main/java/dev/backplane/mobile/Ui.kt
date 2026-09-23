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
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PushPin
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
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
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

@Composable
fun App(m: AppModel) {
    var pairing by rememberSaveable { mutableStateOf(false) }
    val s = m.screen
    when {
        m.link.isEmpty() || pairing -> Pair(m.link, cancel = if (m.link.isEmpty()) null else ({ pairing = false })) {
            m.pair(it)
            pairing = false
        }
        s == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        s.thread != null -> {
            BackHandler { m.act("select", "") }
            ThreadScreen(m, s, s.thread)
        }
        else -> Projects(m, s, onPair = { pairing = true })
    }
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
            Text("Paste the tailnet link Backplane shows under Settings, Remote access.",
                style = MaterialTheme.typography.bodyMedium)
            OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth(), singleLine = true,
                label = { Text("Pairing link") }, placeholder = { Text("http://host:3787/#token=…") })
            Button(onClick = { done(text) }, enabled = text.isNotBlank()) { Text("Connect") }
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
private fun ThreadRow(m: AppModel, r: Row) {
    ListItem(
        headlineContent = { Text(r.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        leadingContent = { Status(r.state) },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (r.pinned) Icon(Icons.Filled.PushPin, "Pinned", Modifier.size(16.dp).padding(end = 4.dp))
                Text(r.ago, style = MaterialTheme.typography.labelMedium)
            }
        },
        modifier = Modifier.combinedClickableCompat { m.act("select", r.id) },
    )
}

@OptIn(ExperimentalFoundationApi::class)
private fun Modifier.combinedClickableCompat(onLong: (() -> Unit)? = null, onClick: () -> Unit) =
    this.combinedClickable(onClick = onClick, onLongClick = onLong)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Projects(m: AppModel, s: Screen, onPair: () -> Unit) {
    val snacks = remember { SnackbarHostState() }
    var adding by rememberSaveable { mutableStateOf(false) }
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
                    IconButton(onClick = { adding = true }) { Icon(Icons.Filled.CreateNewFolder, "Add project") }
                    IconButton(onClick = onPair) { Icon(Icons.Filled.Link, "Pairing") }
                },
            )
        },
        snackbarHost = { SnackbarHost(snacks) },
    ) { pad ->
        if (s.projects.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(pad), contentAlignment = Alignment.Center) {
                Text(s.empty, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.outline)
            }
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = pad) {
            for (p in s.projects) {
                item(key = "p:" + p.id) {
                    ListItem(
                        headlineContent = { Text(p.title, style = MaterialTheme.typography.titleMedium) },
                        supportingContent = { Text(p.root, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        trailingContent = {
                            IconButton(onClick = { m.act("new-thread", p.id) }) { Icon(Icons.Filled.Add, "New thread") }
                        },
                    )
                }
                items(p.threads, key = { "t:" + it.id }) { ThreadRow(m, it) }
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
                item(key = "d:" + p.id) { HorizontalDivider() }
            }
        }
    }
    if (adding) {
        var path by rememberSaveable { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { adding = false },
            title = { Text("Add project") },
            text = {
                OutlinedTextField(path, { path = it }, singleLine = true,
                    label = { Text("Path on the hub") }, placeholder = { Text("/path/to/project") })
            },
            confirmButton = {
                TextButton(onClick = { m.act("add-project", path); adding = false }, enabled = path.isNotBlank()) { Text("Add") }
            },
            dismissButton = { TextButton(onClick = { adding = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun EntryView(m: AppModel, e: Entry) {
    when (e.kind) {
        "user" -> Row(Modifier.fillMaxWidth()) {
            Spacer(Modifier.weight(1f).widthIn(min = 48.dp))
            Surface(
                color = MaterialTheme.colorScheme.primaryContainer,
                shape = MaterialTheme.shapes.large,
                modifier = Modifier.combinedClickableCompat(onLong = { m.act("copy", e.text) }) {},
            ) { Text(e.text, Modifier.padding(horizontal = 14.dp, vertical = 10.dp), style = MaterialTheme.typography.bodyLarge) }
        }
        "assistant" -> Markdown(e.blocks, Modifier.fillMaxWidth().combinedClickableCompat(onLong = { m.act("copy", e.text) }) {})
        else -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val color = if (e.tone == "error") MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.outline
            val mono = MaterialTheme.typography.labelMedium.copy(fontFamily = FontFamily.Monospace)
            Text(e.label, style = mono, color = color.copy(alpha = 0.7f))
            Text(e.text, style = mono, color = color, maxLines = 2, overflow = TextOverflow.Ellipsis)
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ThreadScreen(m: AppModel, s: Screen, t: ThreadView) {
    val snacks = remember { SnackbarHostState() }
    val list = rememberLazyListState()
    var menu by remember { mutableStateOf(false) }
    Errors(m, s, snacks)
    val count = t.entries.size + t.sending.size + (if (t.live.isNotEmpty() || t.working.isNotEmpty()) 1 else 0)
    LaunchedEffect(t.id, m.scrolls) { if (count > 0) list.scrollToItem(count - 1) }
    LaunchedEffect(count, t.live) {
        val last = list.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
        if (count > 0 && last >= count - 3) list.animateScrollToItem(count - 1)
    }
    Scaffold(
        topBar = {
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
                    for (tool in t.tools) if (tool.action == "interrupt")
                        IconButton(onClick = { m.act(tool.action) }) { Icon(Icons.Filled.Stop, tool.label) }
                    Box {
                        IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "More") }
                        DropdownMenu(menu, { menu = false }) {
                            for (tool in t.tools) if (tool.action != "interrupt") DropdownMenuItem(
                                text = { Text(tool.label) },
                                leadingIcon = { if (tool.on) Icon(Icons.Filled.Check, null) else Spacer(Modifier.width(24.dp)) },
                                onClick = { menu = false; m.act(tool.action) },
                            )
                        }
                    }
                },
            )
        },
        bottomBar = {
            Surface(tonalElevation = 3.dp) {
                Column(Modifier.fillMaxWidth().navigationBarsPadding().imePadding().padding(8.dp)) {
                    if (t.queued.isNotEmpty()) Text("Queued: ${t.queued} · sends when this turn ends",
                        Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                        style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.outline,
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        OutlinedTextField(m.composer, m::draft, Modifier.weight(1f), maxLines = 6,
                            placeholder = { Text("Ask the agent") })
                        IconButton(onClick = { m.act("send") }, enabled = m.composer.isNotBlank()) {
                            Icon(Icons.AutoMirrored.Filled.Send, t.send)
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
            items(t.entries, key = { it.id }) { EntryView(m, it) }
            itemsIndexed(t.sending, key = { i, _ -> "sending:$i" }) { _, text -> SendingView(text) }
            if (t.live.isNotEmpty()) item(key = "live") { Markdown(t.live) }
            else if (t.working.isNotEmpty()) item(key = "live") {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(t.working, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.outline)
                    LinearProgressIndicator(Modifier.width(120.dp))
                }
            }
        }
    }
}
