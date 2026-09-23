# T3Code parity

What `docs/reference/t3code-parity.md` describes, and where the Bend
Backplane stands. Updated as features land.

## Done

- **Threads:** per-project threads, sidebar order, Settled after N days (setting, 1–90), pin, archive, rename, delete. Delegated child threads are shown under their parent.
- **Event log:** the log, replay, and a local store (`events.jsonl`); `replay_snoc` and `resume_is_replay` are laws.
- **Providers:**
  - Claude (stream-json, long-lived, restarted when model or mode changes)
  - Codex (`exec --json`, per turn, resumed)
  - Grok (ACP, per turn, resumed)
- **Runtime modes:** runtime modes map to each provider's permissions. Plan mode is supported for Claude and Grok.
- **Approvals:** outside full access, Claude asks through Backplane: Allow / Allow for session / Deny. AskUserQuestion becomes a question with options. ExitPlanMode becomes a proposed plan with Implement / Dismiss.
- **Queued turns:** a message sent while a turn runs is stored on the server and starts when that turn ends. Resends are stored once (`resend_stored_once`).
- **Thread inboxes:** threads message each other through inboxes, and links between threads are shown (`inbox_never_interrupts`).
- **Orchestration:** delegate_task, task_status, task_cancel, thread_list, thread_read, thread_send and orchestrator_capabilities over MCP. Delegation is bounded and each result is delivered once (laws).
- **Model picker:** per thread, plus a default for new threads. Models are detected from each installed CLI.
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
- **Terminal:** a shell per thread in a pty (ctrl+j), rendered by the Bend VT emulator in both clients' state. The web client draws it too: styled rows, the cursor, keys and paste while focused, a Terminal button and ctrl+j, and a phone's keyboard.
- **Diff on the web:** the web client's Diff button and ctrl+d show what the thread changed: files, hunks, and added and removed lines. It has Commit & push, Open PR and Revert thread, and fills the screen on a phone.
- **Attachments:** files and images in a turn.
  - The web client attaches through Attach (a file input) or by pasting an image. It sends files in pieces (`attach.put`).
  - The native window attaches through Attach or the palette's "Attach a file" (a path field). Pasting `file://` URIs or image paths also attaches (`attach.file`).
  - The server stores each file under `<home>/attachments/<thread>/<key>-<name>`. It caps files at 10 MB, cleans names (law `attach_clean_ok`), and never writes outside that directory.
  - A message carries its attachments as trailing `[attachment: /abs/path]` lines (`src/core/attach.bend`). `MessagePosted` keeps its shape, and both clients draw these lines as chips.
  - Claude gets images as base64 content blocks in stream-json (the attachments directory is also an `--add-dir`). Codex gets `--image` flags. Grok gets the path in the text, since its ACP `promptCapabilities.image` is false.
  - The native window shows chips, not image thumbnails.
- **Keybindings:** ctrl+j terminal, ctrl+d diff, ctrl+n new thread, ctrl+shift+[ / ] previous / next thread, ctrl+shift+s settle, ctrl+shift+p pin.
- **Auto-update:** from GitHub releases with checksums, then a swap and restart. There is also an installer.
  - The `update.channel` setting is `stable` or `nightly`, and both clients have a Check now button.
  - Stable takes only full releases. Nightly also takes the `vX.Y.Z-nightly.YYYYMMDD.N` prereleases that `.github/workflows/nightly.yml` publishes daily through release.yml's jobs.
  - Semver orders nightlies by day and then by build, with every nightly before its release (laws `semver_pre_before_release`, `semver_nightly_later`, `semver_nightly_next_day`).
- **Remote:** a web client for other devices over Tailscale with a pairing token. It uses CBOR frames, resumes from a sequence number, and has an outbox, an app shell cache and gzip.
- **Viewers:** board, schematic and 3D (KiCad), STEP (through step2glb), and the agents' browser (Chrome). Clicking inspects an item.

## Not yet

- Command palette (ctrl+k), file picker (ctrl+p), thread search (ctrl+shift+f), jump to thread (ctrl+1..9).
- Snooze and the snoozed section; an archived-threads view; manual reordering of pinned and active threads.
- Sidebar status priority (approval > input > working > failed > …).
- `$skill` mentions, and user/project skills (`~/.claude/skills`, `.claude/skills`) in the prompt for Codex and Grok.
- Reasoning effort per thread.
- LLM-proposed branch names for worktree threads, and commit messages written by the agent.
- Image paste from the X11 clipboard in the native window (it takes pasted paths and `file://` URIs), and image thumbnails there.
