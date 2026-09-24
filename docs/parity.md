# T3Code parity

What `docs/reference/t3code-parity.md` describes, and where the Bend
Backplane stands. Updated as features land.

## Done

- **Threads:** per-project threads, sidebar order, Settled after N days (setting, 1–90), pin, archive, rename, delete. Delegated child threads are shown under their parent.
- **Sidebar:** sections pinned → active → snoozed → settled, then an Archived shelf per project (unarchive from the thread's header). Snooze for 1 hour, until 9:00 tomorrow (the server's time zone) or 1 week; a snoozed thread wakes by the clock alone and never auto-settles while snoozed (`settle_never_snoozed`, `snooze_wakes`). Manual order of pinned and active threads by drag (native) or move buttons (web), with binary fractional order keys (`key_mid_above`, `key_mid_below`, `key_after`). Projects reorder by dragging their names (native and web): dragged projects sit first by their keys, the rest by latest activity (`project_keyed_first`, `project_unkeyed_below`). The row's dot shows approval > input > working > failed > queued > ready (`status_*`).
- **Event log:** the log, replay, and a local store (`events.jsonl`); `replay_snoc` and `resume_is_replay` are laws.
- **Providers:**
  - Claude (stream-json, long-lived, restarted when model or mode changes)
  - Codex (`exec --json`, per turn, resumed)
  - Grok (ACP, per turn, resumed)
- **Runtime modes:** runtime modes map to each provider's permissions. Plan mode is supported for Claude and Grok.
- **Approvals:** outside full access, Claude and Grok ask through Backplane: Allow / Allow for session / Deny. Grok's ACP `session/request_permission` waits parked for the answer (allow once, allow always, reject); a tool allowed for the session is allowed again at once. AskUserQuestion becomes a question with options. ExitPlanMode becomes a proposed plan with Implement / Dismiss.
- **Queued turns:** a message sent while a turn runs is stored on the server and starts when that turn ends. Resends are stored once (`resend_stored_once`).
- **Thread inboxes:** threads message each other through inboxes, and links between threads are shown (`inbox_never_interrupts`).
- **Orchestration:** delegate_task, task_status, task_cancel, thread_list, thread_read, thread_send and orchestrator_capabilities over MCP. Delegation is bounded and each result is delivered once (laws).
- **Model picker:** per thread, plus a default for new threads. Models are detected from each installed CLI. In the window it opens above the composer at its left edge; every piece's place comes from `src/core/menu.bend`, so however many models and effort levels a CLI reports, rows stack, chips flow onto new lines, names and labels keep their own columns, and the menu never goes above the thread's header (it scrolls instead) nor past the composer's width (laws `menu_*`). A press anywhere off it, or Esc, closes it (`menu_press_*`). The web client draws it as a two-column grid over a shade that closes it.
- **Project badges:** each project has a colour and an icon (settings `project.color.<id>`, `project.icon.<id>`; without one, a colour from its id and the folder icon, laws `badge_*`). The sidebar shows the icon by the project's name, a click on it opens an editor of tints and icons under the name, the selected thread's row carries the colour down its left edge, and a thread's header starts with the icon.
- **Reasoning effort:** per thread (low, medium, high, xhigh; Grok up to high), as chips in the model picker, kept in the settings map (`effort.<thread>`). Claude `--effort` (its process restarts when the effort changes), Codex `-c model_reasoning_effort`, Grok `--reasoning-effort`.
- **Skills:** user (`~/.claude/skills`) and project (`<cwd>/.claude/skills`) skills from SKILL.md frontmatter (name, description, disable-model-invocation, user-invocable; the user's win a clash). Claude reads them itself; Codex and Grok get a skills block in their instructions. A `$skill` mention becomes `/skill` for Claude and an instruction to read its SKILL.md for the others. The composer offers skills as you type `$` (Tab or Enter completes).
- **System prompt:**
  - runtime block
  - KiCad runtime, with fork IPC when the setting allows it
  - canonical project files
  - KiStack skills, pinned
  - orchestration
  - browser tools
- **Git:**
  - worktree threads (`env: worktree`, or the `thread.env` setting)
  - a checkpoint per turn in hidden refs
  - a Diff view
  - Revert thread, Commit & push, Open PR (`gh`)
  - a worktree thread's temporary branch is renamed from its first message, and commit messages are written from the thread's diff (a one-shot run of the text generation model; the thread's title when that fails)
- **Thread titles:** a thread's first message titles it at once with its first line; the text generation model then writes a 3 to 7 word title, which replaces that only while the thread still has it (a rename by the user wins; no answer changes nothing). Local and worktree threads alike.
- **Text generation model:** the settings `text.provider` (`claude`, `codex` or `grok`; default `claude`) and `text.model` (empty, or another provider's model: the provider's light model, `haiku`, `gpt-6-luna` or `grok-4.7-build-fast`) pick the model for all one-shot writing: thread titles, branch names and commit messages. Claude runs `claude -p` without tools, Codex `codex exec --json` in a read-only sandbox at low effort, Grok its headless single-turn mode.
- **Terminal:** a shell per thread in a pty (ctrl+j), rendered by the Bend VT emulator in both clients' state. The web client draws it too: styled rows, the cursor, keys and paste while focused, a Terminal button and ctrl+j, and a phone's keyboard.
- **Diff on the web:** the web client's Diff button and ctrl+d show what the thread changed: files, hunks, and added and removed lines. It has Commit & push, Open PR and Revert thread, and fills the screen on a phone.
- **Attachments:** files and images in a turn.
  - The web client attaches through Attach (a file input) or by pasting an image. It sends files in pieces (`attach.put`).
  - The native window attaches through Attach or the palette's "Attach a file" (a path field). Pasting `file://` URIs or image paths also attaches (`attach.file`).
  - The server stores each file under `<home>/attachments/<thread>/<key>-<name>`. It caps files at 10 MB, cleans names (law `attach_clean_ok`), and never writes outside that directory.
  - A message carries its attachments as trailing `[attachment: /abs/path]` lines (`src/core/attach.bend`). `MessagePosted` keeps its shape, and both clients draw these lines as chips.
  - Claude gets images as base64 content blocks in stream-json (the attachments directory is also an `--add-dir`). Codex gets `--image` flags. Grok gets the path in the text, since its ACP `promptCapabilities.image` is false.
  - The native window shows chips, not image thumbnails.
- **Keybindings:** ctrl+j terminal, ctrl+d diff, ctrl+n new thread, ctrl+shift+[ / ] previous / next thread, ctrl+shift+s settle, ctrl+shift+p pin, ctrl+k command palette, ctrl+1..9 jump to the Nth visible thread, ctrl+shift+f thread search (titles and messages), ctrl+p file picker (inserts `@path`).
- **Auto-update:** from GitHub releases with checksums, then a swap and restart. There is also an installer.
  - The `update.channel` setting is `stable` or `nightly`, and both clients have a Check now button.
  - Stable takes only full releases. Nightly also takes the `vX.Y.Z-nightly.YYYYMMDD.N` prereleases that `.github/workflows/nightly.yml` publishes daily through release.yml's jobs.
  - Semver orders nightlies by day and then by build, with every nightly before its release (laws `semver_pre_before_release`, `semver_nightly_later`, `semver_nightly_next_day`).
- **Remote:** a web client for other devices over Tailscale with a pairing token. It uses CBOR frames, resumes from a sequence number, and has an outbox, an app shell cache and gzip.
- **Machines:** each hub listens on the tailnet by default (`--no-tailscale` turns this off) and lets in its owner's devices without the token, going by `tailscale whois` (law `tailnet_no_owner_no_trust`). It finds the owner's other hubs with GET /hello, plus any listed in `BACKPLANE_PEERS`. The sidebar lists them: the native window switches its connection there through a WebSocket link, and the web client opens that machine's page. Board viewers still read files on the machine the window runs on.
- **Models:** the pickers show what each CLI offers now. Claude Code's /model list comes from an `initialize` control request, which calls no model. Codex's list comes from its cache and Grok's from `grok models`. The lists are read again every 15 minutes and pushed to clients. The effort chips follow the model.
- **Viewers:** board, schematic and 3D (KiCad), STEP (through step2glb), and the agents' browser (Chrome). Clicking inspects an item.
- **Board viewer on phones:** a thread's board, schematic or 3D model, live, on the GPU (Metal, GLES 3). The hub sends chunks once, as CBOR, then only the ones a save changed; the 5.6 MB KiCad "video" demo board arrives as 528 KB, and a moved track as one ~1 KB delta. Tapping inspects an item (net, ref, value, footprint...) with Mention in chat; 3D shows the board's body and parts with its copper, mask and silk on the faces.

## Not yet

- Image paste from the X11 clipboard in the native window (it takes pasted paths and `file://` URIs), and image thumbnails there.
