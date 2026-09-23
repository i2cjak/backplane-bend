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
- **Terminal:** a shell per thread in a pty (ctrl+j), rendered by the Bend VT emulator in both clients' state.
- **Keybindings:** ctrl+j terminal, ctrl+d diff, ctrl+n new thread, ctrl+shift+[ / ] previous / next thread, ctrl+shift+s settle, ctrl+shift+p pin.
- **Auto-update:** from GitHub releases with checksums, then a swap and restart. There is also an installer.
- **Remote:** a web client for other devices over Tailscale with a pairing token. It uses CBOR frames, resumes from a sequence number, and has an outbox, an app shell cache and gzip.
- **Viewers:** board, schematic and 3D (KiCad), STEP (through step2glb), and the agents' browser (Chrome). Clicking inspects an item.

## Not yet

- Command palette (ctrl+k), file picker (ctrl+p), thread search (ctrl+shift+f), jump to thread (ctrl+1..9).
- Snooze and the snoozed section; an archived-threads view; manual reordering of pinned and active threads.
- Sidebar status priority (approval > input > working > failed > …).
- `$skill` mentions, and user/project skills (`~/.claude/skills`, `.claude/skills`) in the prompt for Codex and Grok.
- Attachments (images) in a turn.
- Reasoning effort per thread.
- LLM-proposed branch names for worktree threads, and commit messages written by the agent.
- Web client: terminal and diff views.
- Nightly update channel.
