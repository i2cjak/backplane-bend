# Bots

Persistent agents with a name, a face (an animated kitty cat), memory,
routines, webhooks, a browser page of their own, and a space: a UI they
write for themselves. Bots talk to each other directly or in rooms, on one
machine or across machines, including other people's Backplanes.

## Shape

- A bot is backed by one thread (`Bot.thread`). Its turns, model, provider,
  approvals, tools and timeline are the thread's. The thread belongs to no
  project (project `""`), so it never shows on a project shelf; it works in
  `<home>/bots/<id>/`, its home folder (set by a `WorktreeSet` once the hub
  has made the folder).
- Everything else lives in `M.State.bots : BT.World` (`src/core/bot.bend`),
  folded from additive `Change` variants (`Bot*`, `Room*`, `Hook*`,
  `Routine*`, `Memory*`, `Space*`, `Peer*`).
- Secrets never enter the event log or reach a client: webhook and peer
  secrets are files under `<home>/secrets/` (0700 dir, 0600 files); the
  Google refresh token too.

## Conversation depth

A message a bot sends carries a hop count: a human, a routine, a webhook or
a space button starts at 0, and a bot's message to another bot is one more
than the hop of the turn that sent it. A bot never sends past
`Hop.max()` (law `bot_hop_bounded`), so two bots cannot talk forever.

## Cats

`src/core/cat.bend`. A look (fur, pattern, eyes) comes from the bot's
`look` seed. A mood comes from the bot's status:

| mood | when | moves |
|---|---|---|
| sleep | idle for 15 min | still (breathing only on web/phone) |
| idle | ready | tail sway, blinks |
| work | turn running | kneading/typing paws, tail |
| think | queued | head tilt, tail flick |
| wait | needs you (approval, question) | ears up, bounce, "!" |
| talk | sent a bot message in the last minute | mouth, bubble |
| error | last turn failed | ears flat, still tail |
| away | remote, unreachable | greyed, still |

- Web: `Cat.svg(look, mood, px)` is one self-contained animated SVG (SMIL),
  shown as an `<img>` data URI; the browser animates it off the main thread.
- Native window: `Cat.pose(look, mood, ms)` gives polygons per colour for
  a time; flattened once per (look, mood), moved by an affine per frame.
  The window asks for frames at ~30 fps only while a visible cat moves and
  the window is focused (sleeping cats never ask).
- Phones: `Cat.rig(look, mood)` as JSON: parts with SVG path data (only
  `M L C Q Z`, absolute), fill colour, and one animation each (`rot`, `tx`,
  `ty`, `sx`, `sy`, `op` with from/to, pivot, period ms, delay ms, eased
  in-out, ping-pong). SwiftUI `Canvas` + `TimelineView`, Compose `Canvas` +
  `rememberInfiniteTransition`.

## Rooms and messages

- `bot_send(to, text)`: `to` is a bot name here, or `name@peer` elsewhere.
- `room_post(room, text)`: every other member gets it in their inbox.
- Both are logged as `RoomPosted` (direct messages in room `dm:<a>:<b>`,
  names sorted), so people can read every conversation.
- Delivery to a local bot goes through the thread inbox (`Hub.inbox`): it
  queues behind a running turn, never interrupts.

## Machines and people

A peer is another hub, linked by an invite: the inviting hub makes
`bp1:<url>:<peer id>:<secret hex>`; the other pastes it, and both keep the
32-byte secret. Every hub-to-hub request is signed like a webhook (below),
so the same verification guards both. Linked hubs exchange their bot
directory (name, look, mood) every minute and deliver messages with
`POST /bots/deliver`.

## Webhooks

`POST /hook/<hook id>` with

    X-Backplane-Timestamp: <unix seconds>
    X-Backplane-Signature: sha256=<hex HMAC-SHA256(secret, ts + "." + body)>

- The timestamp must be within 300 s of the hub's clock.
- A signature is accepted once (replay cache for the window).
- The comparison is constant time; the body is capped at 256 KB.
- GitHub's `X-Hub-Signature-256` is accepted with `X-GitHub-Delivery` as
  the replay key.
- The secret (32 random bytes, hex) is shown once, when the hook is made.
- The payload reaches the bot marked as untrusted data, never as
  instructions.

## Routines

A routine is a cron line (5 fields, the hub's time zone, `*`, lists,
ranges, steps, and `@hourly`/`@daily`/`@weekly`) and a prompt. The hub's
minute tick fires a due routine once (`RoutineFired` records it), even
after being off for a while (one catch-up run, never a burst).

## Memory

Keyed, typed items, not a notebook:

- kinds: `user` (about the people it works for), `pref` (how they want
  things done), `fact` (about the world, projects, contacts), `howto`
  (procedures it learned), `note` (what happened; short-lived).
- `memory_save(key, kind, text, tags)` replaces the item with that key, so
  a bot updates what it knows instead of piling it up.
- `memory_recall(query)` ranks by words in key, tags and text, then kind,
  then recency. `memory_forget(key)`.
- Each turn a bot starts gets a short `<memory>` block: all `user` and
  `pref` items, then the few items that match the turn's text, within a
  fixed budget (law `mem_block_budget`). Notes older than 30 days leave the
  block but stay recallable.

## Space

A bot's own UI, in its Space tab. The bot writes it with `space_set(spec)`,
a JSON document of blocks:

    {"title": "...", "blocks": [
      {"type": "heading", "text": "..."},
      {"type": "text", "text": "..."},             (markdown-ish, plain)
      {"type": "stat", "label": "...", "value": "...", "hint": "..."},
      {"type": "progress", "label": "...", "value": 0.4},
      {"type": "list", "items": ["...", ...]},
      {"type": "kv", "rows": [["k", "v"], ...]},
      {"type": "table", "head": ["a","b"], "rows": [["1","2"], ...]},
      {"type": "button", "label": "...", "action": "..."},
      {"type": "input", "label": "...", "action": "...", "placeholder": "..."},
      {"type": "divider"},
      {"type": "row", "blocks": [ ...stats/buttons... ]}
    ]}

`Space.parse` keeps what it understands and caps sizes. A button or input
sends the bot `[space] <action> <value>` as a human turn (hop 0). The spec
is data, never code a client runs, so a bot cannot script a client.

## Browser

Each bot has its own page (a tab in the shared Chrome, one persistent
profile, so logins last). The page's frames are JPEG files the hub serves at
`GET /bots/<id>/screen.jpg`; a `{"t":"shot","bot":...,"n":...}` message says
when a new one is ready, and only clients showing that tab fetch it.

## Google

Gmail and Calendar through Google's APIs, not the browser: OAuth 2.0 for
installed apps with PKCE and a loopback redirect to the hub
(`/oauth/google`), or paste the redirected URL when the browser is on
another device. Needs a Google Cloud OAuth client (Desktop app) id and
secret in Settings. Tools: `gmail_search`, `gmail_read`, `gmail_send`
(asks you first), `calendar_events`, `calendar_create` (asks you first).
