# backplane-browser

A headless Chromium that Backplane drives, both for the agents' `preview_*`
MCP tools and for the native preview panel. It is a thin Bun host adapter
over `playwright-core`: it runs requests and publishes frames. Product
logic (which tab, when to show it, how to map panel clicks) stays in Bend.

```sh
scripts/build-browser.sh              # -> dist/backplane-browser (bun --compile)
dist/backplane-browser --frames /tmp/bp-preview.rgb
bun tools/browser/test/smoke.ts [URL] # end-to-end check (src/main.ts, or $BACKPLANE_BROWSER)
```

Flags: `--frames FILE` (frame file path; default
`$TMPDIR/backplane-browser-<pid>.rgb`, removed on exit), `--chromium PATH`,
`--headed` (debugging). `BACKPLANE_BROWSER_DEBUG=1` logs frame timings to
stderr.

## Chrome

The agents' browser is Chrome. The first request that needs a page
launches one, chosen in this order:

1. `--chromium PATH`, then `$BACKPLANE_CHROME` (or `$BACKPLANE_CHROMIUM`)
2. an installed Google Chrome: `google-chrome-stable`, `google-chrome`,
   `chrome` on `PATH`, then `/opt/google/chrome/chrome`, the macOS
   `/Applications/Google Chrome.app`, or the Windows Program Files install
3. Google's Chrome for Testing in Backplane's cache
   (`~/.cache/backplane/chrome/<version>`; `~/Library/Caches/backplane/chrome`
   on macOS, `%LOCALAPPDATA%\backplane\chrome` on Windows)

With none of these, the helper downloads the current Stable Chrome for
Testing from Google (`googlechromelabs.github.io/chrome-for-testing`) into
that cache, with no root needed, and uses it. `status` reports the path in
`chromium`.

## Protocol

Newline-delimited JSON. One request per line on stdin; one reply per request
and unsolicited events on stdout, one JSON object per line. Nothing else is
written to stdout; diagnostics go to stderr.

```
-> {"id": 1, "op": "open", "url": "example.com", "width": 700, "height": 800}
<- {"id": 1, "ok": true, "result": {...}}
<- {"id": 2, "ok": false, "error": "locator.click: Timeout 15000ms exceeded."}
<- {"event": "frame", "w": 700, "h": 800, "seq": 3, "path": "/tmp/bp-preview.rgb"}
```

- `op` names the request. Arguments sit beside it (or inside `"args": {}`).
- `id` is echoed back as given (any JSON value). Requests run concurrently,
  so replies may come out of order; match them by `id`.
- `error` is one line. An unparseable line answers `{"id": null, "ok": false,
  "error": "bad JSON"}`; an unknown op answers `unknown op: X`.
- EOF on stdin, SIGTERM, or `close` shuts the browser down and exits.
- `timeoutMs` (where accepted) defaults to 15000 and is capped at 60000.
- URLs: absolute URLs (`https:`, `http:`, `file:`, `data:`, `about:`) pass
  through; a schemeless host gets `https://`, a loopback host
  (`localhost`, `127.0.0.1`, `[::1]`, `0.0.0.0`, `*.localhost`) `http://`.
- Coordinates are viewport CSS pixels; the viewport has device scale 1, so
  one CSS pixel is one frame pixel.

### Requests

| op | arguments | result |
|---|---|---|
| `status` | | Status |
| `open` | `url?`, `width?`, `height?`, `timeoutMs?` | Status. Launches Chromium and the page if needed, sets the viewport, navigates (waits for `load`) when `url` is given. Default viewport 1280x800. |
| `navigate` | `url`, `readiness?` (`"load"` default, `"domContentLoaded"`, `"none"`), `timeoutMs?` | Status |
| `back`, `forward`, `reload` | `timeoutMs?` | Status |
| `resize` | `width`, `height` (1..4096) | Status. With frames on, a fresh frame follows. |
| `click` | a target (below) or `x`, `y`; `button?` (`left`/`right`/`middle`), `clickCount?`, `timeoutMs?` | `{}` |
| `mouse` | `type` (`move`/`down`/`up`), `x?`, `y?`, `button?` | `{}`. For drags from the panel. |
| `type` | `text`, a target?, `clear?`, `timeoutMs?` | `{}`. Focuses the target (or clears it with `clear`), then inserts `text` literally. Without a target it types into the focused element. |
| `press` | `key` (Playwright key name: `Enter`, `Escape`, `Tab`, `ArrowDown`, `Backspace`, `a`), `modifiers?` (`["Alt","Control","Meta","Shift"]`) | `{}` |
| `scroll` | `dx?`, `dy?` (aliases `deltaX`, `deltaY`; positive is right/down), `x?`, `y?`, or a target | `{}`. A wheel event at (x, y) (default: viewport centre); with a target, `element.scrollBy(dx, dy)`. |
| `snapshot` | `screenshot?` (bool), `timeoutMs?` | Snapshot |
| `evaluate` | `expression`, `awaitPromise?` (default true) | the value, JSON-serialised by Playwright. Over 64 KB: `{"truncated": true, "json": "<first 64000 chars>"}` |
| `wait_for` | any of: a target (visible), `text` (substring of `document.body.innerText`), `url` (alias `urlIncludes`; substring of `location.href`); `timeoutMs?` | `{}` once all hold, else an error |
| `frames` | `on` (bool), `maxFps?` (1..60, default 15) | `{on, maxFps, seq, path}`. Turning on publishes a frame at once. |
| `frame` | | the frame event it published (always published, even if unchanged) |
| `close` | | `{}`, then the helper exits |

A target is one of:

- `ref`: a ref from the snapshot outline, e.g. `"e5"` (`aria-ref=e5`)
- `locator`: a Playwright selector, preferably role/text based, e.g.
  `role=button[name='Send']`, `text=Continue`, `textarea[placeholder*='Message']`
- `selector`: a CSS selector

A locator or selector acts on its first match.

Status:

```json
{"version": "1", "open": true, "chromium": "/path/to/chrome", "url": "https://example.com/",
 "title": "Example Domain", "loading": false, "width": 700, "height": 800,
 "frames": {"on": true, "maxFps": 15, "seq": 3, "path": "/tmp/bp-preview.rgb"}}
```

Snapshot:

```json
{"url": "...", "title": "...", "loading": false,
 "visibleText": "first 20000 chars of body.innerText",
 "interactiveElements": [{"tag": "button", "role": null, "name": "Go", "selector": "#go",
                          "x": 190, "y": 176, "width": 34, "height": 21}],
 "outline": "- heading \"Backplane browser\" [level=1] [ref=e2]\n- textbox \"Search\" [ref=e4]\n- button \"Go\" [ref=e5]\n...",
 "console": [{"level": "error", "text": "...", "timestamp": "2026-09-22T12:00:00.000Z"}],
 "screenshot": {"mimeType": "image/png", "data": "<base64>", "width": 700, "height": 800}}
```

`outline` is Playwright's AI aria snapshot (YAML-like, one node per line,
with `[ref=eN]` on each). Refs stay valid until the next snapshot.
`interactiveElements` (up to 200) are visible `a[href]`, `button`, `input`,
`textarea`, `select`, `[role]`, `[tabindex]` with viewport boxes. `console`
is the last 50 console messages and page errors. `screenshot` is present
only when asked for.

### Events

| event | fields | when |
|---|---|---|
| `ready` | `version`, `frames` (the frame file path) | once, at start |
| `frame` | `w`, `h`, `seq`, `path` | a new frame file is in place |
| `navigated` | `url` | the main frame committed a navigation |
| `load` | `url` | the page fired `load` |
| `closed` | | Chromium went away (crash or close); the next request relaunches it |

## Frames

Frames are raw pixels, because the Bend side cannot decode PNG or JPEG
cheaply. The helper takes Chromium's screencast (`Page.startScreencast`,
PNG, pushed by the compositor only when something repaints), decodes the
PNG itself (`src/png.ts`: zlib inflate plus filter reconstruction), and
writes the pixels to the frame file.

The frame file is 16 bytes of header and then the pixels:

| offset | size | |
|---|---|---|
| 0 | 4 | `BPF1` |
| 4 | 4 | width, u32 little-endian |
| 8 | 4 | height, u32 little-endian |
| 12 | 4 | seq, u32 little-endian |
| 16 | w*h*3 | RGB, 8 bits per channel, rows top to bottom, no padding |

Each frame is written to `FILE.tmp` and renamed over `FILE`, so a reader
that opens `FILE` always gets one whole frame, never a torn one, and needs
no locking: plain `open` + `read` of the whole file. The header makes the
file self-describing, so a reader that is one frame behind (or reads after a
resize) still decodes it correctly; `seq` tells it which frame it has. The
`frame` event carries the same `w`, `h`, `seq`; a reader may skip reading
when `seq` has not moved.

Pacing: while frames are on, a timer runs at `maxFps`. Each tick takes the
latest screencast frame, if one came since the last tick (older ones are
dropped), decodes it, and hashes the pixels; it writes and announces only
when the hash differs from the last published frame. A still page costs
nothing and emits nothing. `frame`, `resize` and turning frames on publish
at once, even if unchanged.

In Bend (`src/gfx/bitmap.bend`):

```python
f : File <- IO.try(File, File.open(path, "r"))
r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 100000000)
# ... bytes bs
+bm = Bitmap.load(bs, x0, y0, fw, fh)          # header + pixels -> Bitmap
+img = Bitmap.over(W, H, bm, base)              # composite into a W x H frame
```

A 700x800 frame is 1,680,016 bytes. The helper's decode and write take
about 5-20 ms a frame.

## Choices

- Why a file and not fd 3 or stdout: a Bend program reads files with the
  stock `File` effects; a pipe would need a custom effect and framing, and a
  slow reader would block the helper. With rename, the reader never blocks
  the writer and always sees the newest whole frame.
- Why PNG and not JPEG: lossless (text stays crisp), and decoding needs only
  zlib, which Bun has; no extra dependency.
- `chromium-bidi` is left external in the compiled binary (Playwright only
  needs it for Firefox/BiDi).
