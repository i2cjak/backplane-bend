package dev.backplane.mobile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import android.util.LruCache
import android.webkit.MimeTypeMap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.BrokenImage
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Difference
import androidx.compose.material.icons.filled.FindInPage
import androidx.compose.material.icons.filled.Snooze
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.QuestionAnswer
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

// The pieces of a thread and the sheets over it, as iOS's ThreadParts.
// Every label, value and choice comes from the screen
// (src/mobile/screen.bend); these only draw them and send back the action
// each names.

private val corner = RoundedCornerShape(4.dp)
private val orange = Color(0xFFF57C00)
private val mono = FontFamily.Monospace

// a thread's dot: what most needs the user (row.status), else its turn
@Composable
fun StatusDot(state: String, status: String) {
    Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
        when (status) {
            "approval" -> Icon(Icons.Filled.PanTool, "Waits for approval", Modifier.size(16.dp), tint = orange)
            "input" -> Icon(Icons.Filled.QuestionAnswer, "Waits for an answer", Modifier.size(16.dp), tint = Color(0xFF1E88E5))
            "working" -> CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
            "failed" -> Icon(Icons.Filled.Error, "Failed", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.error)
            "queued" -> Icon(Icons.Filled.Schedule, "Queued", Modifier.size(16.dp), tint = MaterialTheme.colorScheme.outline)
            "ready" -> Dot(MaterialTheme.colorScheme.outlineVariant)
            else -> when (state) {
                "run" -> CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                "fail" -> Icon(Icons.Filled.Error, "Failed", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.error)
                "stop" -> Dot(MaterialTheme.colorScheme.tertiary)
                else -> Dot(MaterialTheme.colorScheme.outlineVariant)
            }
        }
    }
}

@Composable
private fun Dot(c: Color) = Box(Modifier.size(8.dp).clip(CircleShape).background(c))

// Images from the hub, kept by address and size (the bytes they hold)
private object Images {
    val cache = object : LruCache<String, Bitmap>(48 shl 20) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }

    // an image at most max px on its longer side, or null
    fun load(url: String, max: Int): Bitmap? {
        val key = "$max|$url"
        cache.get(key)?.let { return it }
        val bytes = runCatching {
            val c = URL(url).openConnection() as HttpURLConnection
            c.connectTimeout = 5000
            c.readTimeout = 20000
            try {
                if (c.responseCode == 200) c.inputStream.use { it.readBytes() } else null
            } finally {
                c.disconnect()
            }
        }.getOrNull() ?: return null
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, o)
        var sample = 1
        while (maxOf(o.outWidth, o.outHeight) / (sample * 2) >= max) sample *= 2
        val b = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: return null
        cache.put(key, b)
        return b
    }
}

// what an image load has come to: loading (null), failed or an image
private sealed interface Got {
    data object Failed : Got
    data class Ok(val b: Bitmap) : Got
}

@Composable
private fun hubImage(url: String, max: Int): Got? =
    produceState<Got?>(null, url, max) {
        value = withContext(Dispatchers.IO) { Images.load(url, max) }?.let { Got.Ok(it) } ?: Got.Failed
    }.value

// an image from the hub, as a thumbnail; a tap opens it full screen
@Composable
fun Thumb(m: AppModel, path: String, show: (String) -> Unit) {
    val u = m.web(path) ?: return
    when (val g = hubImage(u, 720)) {
        null -> Box(Modifier.size(80.dp, 60.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
        }
        Got.Failed -> Box(Modifier.size(80.dp, 60.dp), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.BrokenImage, "No image", tint = MaterialTheme.colorScheme.outline)
        }
        is Got.Ok -> Image(g.b.asImageBitmap(), "Image", Modifier.widthIn(max = 260.dp).heightIn(max = 200.dp)
            .clip(corner).clickable { show(u) }, contentScale = ContentScale.Fit)
    }
}

// pinch to zoom, drag to pan, double-tap to zoom in or back, the cross (or
// back) closes it
@Composable
fun Lightbox(url: String, close: () -> Unit) {
    Dialog(close, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        var scale by remember { mutableFloatStateOf(1f) }
        var offset by remember { mutableStateOf(Offset.Zero) }
        Box(Modifier.fillMaxSize().background(Color.Black)
            .pointerInput(Unit) {
                detectTapGestures(onDoubleTap = {
                    scale = if (scale > 1f) 1f else 2.5f
                    if (scale == 1f) offset = Offset.Zero
                })
            }
            .pointerInput(Unit) {
                detectTransformGestures { _, pan, zoom, _ ->
                    scale = (scale * zoom).coerceIn(1f, 8f)
                    offset = if (scale == 1f) Offset.Zero else offset + pan
                }
            }) {
            when (val g = hubImage(url, 2560)) {
                null -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                Got.Failed -> Icon(Icons.Filled.BrokenImage, "No image", Modifier.align(Alignment.Center), tint = Color.Gray)
                is Got.Ok -> Image(g.b.asImageBitmap(), "Image", Modifier.fillMaxSize().graphicsLayer(
                    scaleX = scale, scaleY = scale, translationX = offset.x, translationY = offset.y), contentScale = ContentScale.Fit)
            }
            IconButton(close, Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(8.dp)) {
                Icon(Icons.Filled.Close, "Close", tint = Color.White)
            }
        }
    }
}

// an attachment chip; an image shows as a thumbnail
@Composable
fun ChipView(m: AppModel, c: Chip, show: (String) -> Unit) {
    if (c.image) Thumb(m, c.url, show)
    else Row(Modifier.background(MaterialTheme.colorScheme.surfaceVariant, corner).padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(Icons.Filled.Description, null, Modifier.size(14.dp))
        Text(c.label, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun EntryRow(m: AppModel, e: Entry, show: (String) -> Unit) {
    when (e.kind) {
        "user" -> Column(Modifier.fillMaxWidth().padding(start = 48.dp), horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (e.text.isNotEmpty()) Surface(
                color = MaterialTheme.colorScheme.primaryContainer,
                shape = MaterialTheme.shapes.large,
                modifier = Modifier.combinedClickableCompat(onLong = { m.act("copy", e.text) }) {},
            ) { Text(e.text, Modifier.padding(horizontal = 14.dp, vertical = 10.dp), style = MaterialTheme.typography.bodyLarge) }
            for (c in e.attachments) ChipView(m, c, show)
        }
        "assistant" -> Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Markdown(e.blocks, Modifier.fillMaxWidth().combinedClickableCompat(onLong = { m.act("copy", e.text) }) {})
            for (i in e.images) Thumb(m, i.url, show)
        }
        "fold" -> Row(Modifier.fillMaxWidth().clickable { m.act("fold", e.value) }.padding(vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(if (e.open) Icons.Filled.ExpandMore else Icons.AutoMirrored.Filled.KeyboardArrowRight,
                if (e.open) "Hide" else "Show", Modifier.size(16.dp), tint = MaterialTheme.colorScheme.outline)
            Text(e.text, style = MaterialTheme.typography.labelMedium.copy(fontFamily = mono),
                color = MaterialTheme.colorScheme.outline, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        "link" -> Text(e.text, Modifier.clickable { m.act("select", e.value) }.padding(vertical = 2.dp),
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        else -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val color = if (e.tone == "error") MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.outline
            val style = MaterialTheme.typography.labelMedium.copy(fontFamily = mono)
            Text(e.label, style = style, color = color.copy(alpha = 0.7f))
            Text(e.text, style = style, color = color, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

// the threads this one delegated to
@Composable
fun TasksView(m: AppModel, tasks: List<TaskRow>) {
    Surface(color = MaterialTheme.colorScheme.surfaceVariant, shape = corner, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Subagents", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.outline)
            for (t in tasks) Row(Modifier.fillMaxWidth().clickable { m.act("select", t.id) }.padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatusDot(when (t.state) { "running" -> "run"; "failed" -> "fail"; else -> "" }, "")
                Column(Modifier.weight(1f)) {
                    Text(t.title, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(t.who + " · " + t.state, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                }
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.outline)
            }
        }
    }
}

// an approval, question or plan waiting on the user
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AskCard(m: AppModel, a: Ask) {
    Surface(color = orange.copy(alpha = 0.14f), shape = corner, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(when (a.kind) { "plan" -> Icons.Filled.Checklist; "input" -> Icons.Filled.QuestionAnswer; else -> Icons.Filled.PanTool },
                    null, Modifier.size(18.dp), tint = orange)
                Text(a.head, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            }
            if (a.blocks.isNotEmpty()) Box(Modifier.heightIn(max = 220.dp).verticalScroll(rememberScrollState())) { Markdown(a.blocks) }
            else if (a.detail.isNotEmpty()) Text(a.detail, style = MaterialTheme.typography.labelMedium.copy(fontFamily = mono),
                maxLines = 8, overflow = TextOverflow.Ellipsis)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (b in a.buttons) {
                    if (b.primary) Button(onClick = { m.act("answer", b.value) }, shape = corner) { Text(b.label) }
                    else OutlinedButton(onClick = { m.act("answer", b.value) }, shape = corner) { Text(b.label) }
                }
            }
        }
    }
}

// what the next message attaches (× takes one off), what is uploading,
// and the skills a `$` being typed completes to
@Composable
fun ComposerExtras(m: AppModel, t: ThreadView) {
    if (t.skills.isNotEmpty()) Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        for (k in t.skills) Surface(onClick = { m.act("skill", k.name) }, shape = corner,
            color = MaterialTheme.colorScheme.secondaryContainer) {
            Column(Modifier.widthIn(max = 220.dp).padding(horizontal = 10.dp, vertical = 6.dp)) {
                Text("$" + k.name, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
                Text(k.desc, style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
    if (t.attaching.isNotEmpty() || t.uploading.isNotEmpty()) Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        for (c in t.attaching) Surface(onClick = { m.act("detach", c.path) }, shape = corner,
            color = MaterialTheme.colorScheme.surfaceVariant) {
            Row(Modifier.padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(if (c.image) Icons.Filled.Image else Icons.Filled.Description, null, Modifier.size(14.dp))
                Text(c.label, style = MaterialTheme.typography.labelMedium, maxLines = 1)
                Icon(Icons.Filled.Close, "Remove " + c.label, Modifier.size(14.dp))
            }
        }
        if (t.uploading.isNotEmpty()) {
            CircularProgressIndicator(Modifier.size(12.dp), strokeWidth = 2.dp)
            Text(t.uploading, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.outline, maxLines = 1)
        }
    }
}

// the paperclip: photos or files, each sent up in pieces
@Composable
fun AttachButton(m: AppModel) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var open by remember { mutableStateOf(false) }
    fun send(uris: List<Uri>, photos: Boolean) {
        scope.launch {
            uris.forEachIndexed { i, u ->
                val got = withContext(Dispatchers.IO) {
                    runCatching {
                        val cr = ctx.contentResolver
                        val data = cr.openInputStream(u)?.use { it.readBytes() } ?: return@runCatching null
                        val mime = cr.getType(u) ?: ""
                        if (photos) {
                            val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "jpg"
                            // HEIC becomes JPEG, which every agent reads
                            if (ext == "heic" || ext == "heif") {
                                val b = BitmapFactory.decodeByteArray(data, 0, data.size)
                                val out = ByteArrayOutputStream()
                                if (b != null && b.compress(Bitmap.CompressFormat.JPEG, 85, out)) out.toByteArray() to "photo-${i + 1}.jpg"
                                else data to "photo-${i + 1}.$ext"
                            } else data to "photo-${i + 1}.$ext"
                        } else {
                            val name = cr.query(u, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                                if (c.moveToFirst()) c.getString(0) else null
                            } ?: u.lastPathSegment ?: "file"
                            data to name
                        }
                    }.getOrNull()
                }
                if (got != null) m.attach(got.first, got.second)
            }
        }
    }
    val photos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(10)) { send(it, true) }
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { send(it, false) }
    Box {
        IconButton(onClick = { open = true }) { Icon(Icons.Filled.AttachFile, "Attach") }
        DropdownMenu(open, { open = false }) {
            DropdownMenuItem(text = { Text("Photos") }, leadingIcon = { Icon(Icons.Filled.Image, null) }, onClick = {
                open = false
                photos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            })
            DropdownMenuItem(text = { Text("Files") }, leadingIcon = { Icon(Icons.Filled.Folder, null) }, onClick = {
                open = false
                files.launch(arrayOf("*/*"))
            })
        }
    }
}

// a sheet over the whole screen: a top bar and its content; back closes it
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Sheet(
    title: String, close: () -> Unit, closeLabel: String = "Close",
    bar: Color = Color.Unspecified, onBar: Color = Color.Unspecified,
    // a dialog, or (inline) drawn in place of the screen, which follows the
    // keyboard as the thread's composer does
    inline: Boolean = false,
    actions: @Composable () -> Unit = {}, content: @Composable (PaddingValues) -> Unit,
) {
    if (inline) SheetBody(title, close, closeLabel, bar, onBar, actions, content)
    else Dialog(close, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        SheetBody(title, close, closeLabel, bar, onBar, actions, content)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SheetBody(
    title: String, close: () -> Unit, closeLabel: String, bar: Color, onBar: Color,
    actions: @Composable () -> Unit, content: @Composable (PaddingValues) -> Unit,
) {
        Scaffold(topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = close) { Icon(Icons.Filled.Close, closeLabel) } },
                actions = { actions() },
                colors = if (bar == Color.Unspecified) TopAppBarDefaults.topAppBarColors() else TopAppBarDefaults.topAppBarColors(
                    containerColor = bar, titleContentColor = onBar, navigationIconContentColor = onBar, actionIconContentColor = onBar),
            )
        }) { content(it) }
}

// what the thread changed, with the git actions
@Composable
fun DiffSheet(m: AppModel, d: Diff) {
    var git by remember { mutableStateOf(false) }
    var reverting by remember { mutableStateOf(false) }
    Sheet("Diff", { m.act("panel") }, actions = {
        Box {
            TextButton(onClick = { git = true }) { Text("Git") }
            DropdownMenu(git, { git = false }) {
                DropdownMenuItem(text = { Text("Commit & push") }, onClick = { git = false; m.act("git", "commit_push") })
                DropdownMenuItem(text = { Text("Open PR") }, onClick = { git = false; m.act("git", "commit_push_pr") })
                DropdownMenuItem(text = { Text("Revert thread", color = MaterialTheme.colorScheme.error) },
                    onClick = { git = false; reverting = true })
            }
        }
    }) { pad ->
        LazyColumn(Modifier.fillMaxSize(), contentPadding = pad) {
            item { Text(d.summary, Modifier.padding(16.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline) }
            for (f in d.files) {
                item {
                    Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant).padding(horizontal = 12.dp, vertical = 6.dp)) {
                        Text(f.name, Modifier.weight(1f), style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(f.status, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.outline)
                    }
                }
                items(f.lines) { l -> DiffRow(l) }
            }
        }
    }
    if (reverting) AlertDialog(
        onDismissRequest = { reverting = false },
        title = { Text("Put the files back as they were when this thread began?") },
        confirmButton = {
            TextButton(onClick = { reverting = false; m.act("revert", "0") }) { Text("Revert thread", color = MaterialTheme.colorScheme.error) }
        },
        dismissButton = { TextButton(onClick = { reverting = false }) { Text("Cancel") } },
    )
}

@Composable
private fun DiffRow(l: DiffLine) {
    val style = TextStyle(fontFamily = mono, fontSize = 11.sp, lineHeight = 14.sp)
    val bg = when (l.k) { 1 -> Color(0x2443A047); 2 -> Color(0x24E53935); else -> Color.Transparent }
    Row(Modifier.fillMaxWidth().background(bg).padding(horizontal = 8.dp)) {
        if (l.k == 4) Text(l.t, style = style, color = Color(0xFF1E88E5))
        else {
            Text(if (l.k == 2) l.o else l.n, Modifier.width(30.dp).padding(end = 4.dp), style = style,
                color = MaterialTheme.colorScheme.outline, textAlign = androidx.compose.ui.text.style.TextAlign.End)
            Text((when (l.k) { 1 -> "+"; 2 -> "-"; else -> " " }) + l.t, style = style,
                color = if (l.k == 3) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface)
        }
    }
}

private fun rgb(c: Int) = Color(0xFF000000.toInt() or c)

private val termStyle = TextStyle(fontFamily = mono, fontSize = 11.sp, lineHeight = 14.sp)

// the size a terminal has room for on this phone, as "<cols>x<rows>"
@Composable
fun rememberTermSize(): () -> String {
    val measure = rememberTextMeasurer()
    val density = LocalDensity.current
    val conf = androidx.compose.ui.platform.LocalConfiguration.current
    return {
        val cell = measure.measure("M", termStyle).size
        val w = with(density) { conf.screenWidthDp.dp.toPx() - 16.dp.toPx() }
        val h = with(density) { conf.screenHeightDp.dp.toPx() * 0.5f }
        "${maxOf((w / cell.width).toInt(), 20)}x${maxOf((h / cell.height).toInt(), 8)}"
    }
}

// the thread's shell: the screen the hub's emulator keeps, keys typed in a
// hidden field, and a row of keys a phone keyboard lacks
@Composable
fun TermSheet(m: AppModel, t: Term) {
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    var typing by remember { mutableStateOf(true) }
    var buf by remember { mutableStateOf(TextFieldValue(" ", TextRange(1))) }
    val measure = rememberTextMeasurer()
    val cell = remember { measure.measure("M", termStyle).size }
    val density = LocalDensity.current
    val vs = rememberScrollState()
    val hs = rememberScrollState()
    fun key(k: String, mods: Int = 0) = m.quiet("term-key", "$k\t$mods")
    // the cursor's row kept in view (the rows below it are mostly blank)
    val below = with(density) { 16.dp.roundToPx() }
    LaunchedEffect(t.cursor.y, vs.maxValue, vs.viewportSize) {
        vs.scrollTo(((t.cursor.y + 1) * cell.height + below - vs.viewportSize).coerceIn(0, vs.maxValue))
    }
    LaunchedEffect(Unit) { focus.requestFocus(); keyboard?.show() }
    val bg = rgb(t.bg)
    val fg = rgb(t.fg)
    Sheet(t.title.ifEmpty { "Terminal" }, { m.act("term-toggle") }, bar = bg, onBar = fg, inline = true) { pad ->
        Column(Modifier.fillMaxSize().padding(pad).imePadding()) {
            Box(Modifier.weight(1f).fillMaxWidth().background(bg)
                .clickable { focus.requestFocus(); keyboard?.show(); typing = true }
                .verticalScroll(vs).horizontalScroll(hs).padding(8.dp)) {
                Column {
                    for (l in t.lines) Text(buildAnnotatedString {
                        for (r in l) withStyle(SpanStyle(
                            color = rgb(r.fg),
                            background = if (r.bg != t.bg) rgb(r.bg) else Color.Unspecified,
                            fontWeight = if (r.b) FontWeight.Bold else null,
                            textDecoration = if (r.u) TextDecoration.Underline else null,
                        )) { append(r.t) }
                    }, style = termStyle, color = fg, softWrap = false, maxLines = 1)
                }
                if (t.cursor.on) Box(Modifier
                    .offset { IntOffset(t.cursor.x * cell.width, t.cursor.y * cell.height) }
                    .size(with(density) { cell.width.toDp() }, with(density) { cell.height.toDp() })
                    .background(fg.copy(alpha = 0.6f)))
            }
            // the field keeps one space, so a backspace always has something to take
            // what the field held against what it holds now: what went is
            // backspaced, what came is typed. It starts with a space, so a
            // backspace always has something to take, and starts over when
            // emptied or long (never as the value it has, which the field
            // would not take up)
            BasicTextField(buf, { v ->
                val old = buf.text
                val new = v.text
                var same = 0
                while (same < old.length && same < new.length && old[same] == new[same]) same++
                repeat(old.length - same) { key("Backspace") }
                val parts = new.substring(same).split('\n')
                parts.forEachIndexed { i, p ->
                    if (p.isNotEmpty()) m.quiet("term-paste", p)
                    if (i < parts.size - 1) key("Enter")
                }
                buf = if (new.isEmpty() || new.length > 200 || '\n' in new)
                    (if (old == " ") TextFieldValue("  ", TextRange(2)) else TextFieldValue(" ", TextRange(1)))
                else v
            }, Modifier.size(1.dp).focusRequester(focus), singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false,
                    keyboardType = KeyboardType.Password, imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { key("Enter") }),
                textStyle = TextStyle(color = Color.Transparent))
            Surface(tonalElevation = 3.dp) {
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    @Composable fun k(label: String, go: () -> Unit) = OutlinedButton(onClick = go, shape = corner,
                        contentPadding = PaddingValues(horizontal = 10.dp)) { Text(label, fontFamily = mono, style = MaterialTheme.typography.labelMedium) }
                    @Composable fun ik(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, go: () -> Unit) =
                        OutlinedButton(onClick = go, shape = corner, contentPadding = PaddingValues(horizontal = 10.dp)) {
                            Icon(icon, label, Modifier.size(16.dp))
                        }
                    k("esc") { key("Escape") }
                    k("tab") { key("Tab") }
                    k("^C") { key("c", 4) }
                    k("^D") { key("d", 4) }
                    k("^Z") { key("z", 4) }
                    k("^L") { key("l", 4) }
                    ik(Icons.AutoMirrored.Filled.ArrowBack, "Left") { key("ArrowLeft") }
                    ik(Icons.Filled.ArrowUpward, "Up") { key("ArrowUp") }
                    ik(Icons.Filled.ArrowDownward, "Down") { key("ArrowDown") }
                    ik(Icons.AutoMirrored.Filled.ArrowForward, "Right") { key("ArrowRight") }
                    ik(Icons.Filled.Keyboard, "Keyboard") {
                        typing = !typing
                        if (typing) { focus.requestFocus(); keyboard?.show() } else keyboard?.hide()
                    }
                }
            }
        }
    }
}

// thread search or the file picker: a field over the rows; a row sends its
// action with its value, then the sheet closes
@Composable
fun FindSheet(m: AppModel, f: Find) {
    var text by remember { mutableStateOf(f.query) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    val files = f.mode == "files"
    Sheet(if (files) "Find file" else "Search threads", { m.act("find-close") }, closeLabel = "Cancel") { pad ->
        Column(Modifier.fillMaxSize().padding(pad).imePadding()) {
            OutlinedTextField(text, { text = it; m.act("find-q", it) },
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).focusRequester(focus), singleLine = true,
                placeholder = { Text(if (files) "File name" else "Titles and messages") },
                leadingIcon = { Icon(Icons.Filled.Search, null) },
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false))
            if (f.rows.isEmpty()) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(if (f.query.isEmpty()) (if (files) "Type to find a file" else "Type to search threads") else "Nothing found",
                    color = MaterialTheme.colorScheme.outline)
            } else LazyColumn(Modifier.fillMaxSize()) {
                items(f.rows) { r ->
                    ListItem(
                        headlineContent = { Text(r.label, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                        leadingContent = {
                            Icon(when (r.kind) { "file" -> Icons.Filled.Description; "thread" -> Icons.AutoMirrored.Filled.Chat; else -> Icons.Filled.Bolt }, null)
                        },
                        modifier = Modifier.clickable { m.act(r.action, r.value); m.act("find-close") },
                    )
                }
            }
        }
    }
}

// the hub's settings, as the desktop has them
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SettingsSheet(m: AppModel, st: Settings) {
    Sheet("Settings", { m.act("flag", "settings") }, closeLabel = "Done") { pad ->
        LazyColumn(Modifier.fillMaxSize(), contentPadding = pad) {
            items(st.rows) { r ->
                Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(r.label, style = MaterialTheme.typography.bodyLarge)
                    if (r.note.isNotEmpty()) Text(r.note, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                    if (r.buttons.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        for (b in r.buttons) {
                            if (b.on) Button(onClick = { m.act(b.action, b.value) }, shape = corner) { Text(b.label) }
                            else OutlinedButton(onClick = { m.act(b.action, b.value) }, shape = corner) { Text(b.label) }
                        }
                    }
                }
                HorizontalDivider()
            }
        }
    }
}

// the thread menu's icon for an action
fun menuIcon(action: String) = when (action) {
    "diff" -> Icons.Filled.Difference
    "term-toggle" -> Icons.Filled.Terminal
    "find-open" -> Icons.Filled.FindInPage
    "snooze" -> Icons.Filled.Snooze
    "row-delete" -> Icons.Filled.Delete
    else -> null
}
