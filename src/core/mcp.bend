import Base
import ./json.bend as J
import ./model.bend as M
import ./codec.bend as C
import ./hub.bend as B
import ./acp.bend as AC

# The Backplane MCP server, as a decider. Each agent session gets its own
# endpoint (/mcp/<thread>), so every call knows which thread is asking. A
# call answers a JSON-RPC reply now, plus the changes and effects of a hub
# step. Tools follow T3Code's orchestrator toolkit: delegate work to another
# model, watch it, and read or message other threads, within the laws of
# model.bend (bounded depth, forward-only task states, one delivery).

type McpOut is Data:
  McpOut{reply: String, step: B.Step, park: String}

def Mcp.result(+id: J.Json, r: J.Json) -> String:
  J.Json.show(J.Json.obj([J.KV{"jsonrpc", J.Str{"2.0"}}, J.KV{"id", id}, J.KV{"result", r}]))

def Mcp.error(+id: J.Json, +code: String, msg: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"jsonrpc", J.Str{"2.0"}}, J.KV{"id", id},
    J.KV{"error", J.Json.obj([J.KV{"code", J.Num{code}}, J.KV{"message", J.Str{msg}}])}]))

# a tool's answer: text content (JSON text), isError when it failed
def Mcp.content(+ok: Bool, body: J.Json) -> J.Json:
  J.Json.obj([J.KV{"content", J.Json.arr([J.Json.obj([J.KV{"type", J.Str{"text"}}, J.KV{"text", J.Str{J.Json.show(body)}}])])},
    J.KV{"isError", J.Flag{Bool.not(ok)}}])

def Mcp.fail(msg: String) -> J.Json:
  J.Json.obj([J.KV{"error", J.Str{msg}}])

# Tool definitions
# ----------------

def Tool.prop(+name: String, +ty: String, desc: String) -> J.KV:
  J.KV{name, J.Json.obj([J.KV{"type", J.Str{ty}}, J.KV{"description", J.Str{desc}}])}

def Tool.strs(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      J.Str{x} <> Tool.strs(t)

def Tool.def(name: String, desc: String, props: List<&2, J.KV>, req: List<&2, String>) -> J.Json:
  J.Json.obj([J.KV{"name", J.Str{name}}, J.KV{"description", J.Str{desc}},
    J.KV{"inputSchema", J.Json.obj([J.KV{"type", J.Str{"object"}}, J.KV{"properties", J.Json.obj(props)}, J.KV{"required", J.Json.arr(Tool.strs(req))}])}])

def Tool.target() -> List<&2, J.KV>:
  [Tool.prop("ref", "string", "A ref from preview_snapshot's outline, e.g. e5 (preferred)."),
   Tool.prop("locator", "string", "A Playwright selector, role or text based, e.g. role=button[name='Send'] or text=Continue."),
   Tool.prop("selector", "string", "A CSS selector."),
   Tool.prop("timeoutMs", "number", "Timeout in ms (default 15000, at most 60000).")]

# The browser Backplane hosts (a headless Chromium the user watches in the
# app's Browser tab); the server forwards these to it
def Mcp.preview_tools() -> List<&2, J.Json>:
  [Tool.def("preview_open", "Open the Backplane browser (the user sees it live in the app's Browser tab), optionally at a URL. Use it to check web UIs, datasheets, distributor pages and docs.",
     [Tool.prop("url", "string", "URL to load; a bare host gets https://, localhost gets http://."), Tool.prop("width", "number", "Viewport width (default 1280)."), Tool.prop("height", "number", "Viewport height (default 800).")], Nil{}),
   Tool.def("preview_navigate", "Go to a URL in the Backplane browser.", [Tool.prop("url", "string", "The URL."), Tool.prop("readiness", "string", "load (default), domContentLoaded or none.")], ["url"]),
   Tool.def("preview_snapshot", "Read the page: URL, title, visible text, interactive elements and an outline whose [ref=eN] marks are targets for click and type. Snapshot before acting.",
     [Tool.prop("screenshot", "boolean", "Also return a PNG screenshot.")], Nil{}),
   Tool.def("preview_click", "Click an element (ref, locator or selector) or a point (x, y in viewport pixels).",
     List.append(&2, J.KV, Tool.target(), [Tool.prop("x", "number", "X in viewport pixels."), Tool.prop("y", "number", "Y in viewport pixels.")]), Nil{}),
   Tool.def("preview_type", "Type text into an element (or the focused one).",
     List.append(&2, J.KV, Tool.target(), [Tool.prop("text", "string", "The text, inserted literally."), Tool.prop("clear", "boolean", "Clear the field first.")]), ["text"]),
   Tool.def("preview_press", "Press a key (Enter, Escape, Tab, ArrowDown, Backspace, a...).", [Tool.prop("key", "string", "Playwright key name.")], ["key"]),
   Tool.def("preview_scroll", "Scroll the page (dx, dy in pixels; positive is right/down), or an element with a target.",
     List.append(&2, J.KV, Tool.target(), [Tool.prop("dx", "number", "Horizontal pixels."), Tool.prop("dy", "number", "Vertical pixels.")]), Nil{}),
   Tool.def("preview_evaluate", "Evaluate a JavaScript expression in the page and return its JSON value.", [Tool.prop("expression", "string", "The expression.")], ["expression"]),
   Tool.def("preview_wait_for", "Wait until an element is visible, some text appears, or the URL contains a string.",
     List.append(&2, J.KV, Tool.target(), [Tool.prop("text", "string", "Text to wait for."), Tool.prop("url", "string", "URL substring to wait for.")]), Nil{}),
   Tool.def("preview_resize", "Resize the browser viewport.", [Tool.prop("width", "number", "Width."), Tool.prop("height", "number", "Height.")], ["width", "height"]),
   Tool.def("preview_status", "The browser's state: open, URL, title, viewport.", Nil{}, Nil{})]

def Mcp.tools() -> J.Json:
  J.Json.obj([J.KV{"tools", J.Json.arr(List.append(&2, J.Json, [
    Tool.def("orchestrator_capabilities",
      "List the providers and models this Backplane can run, the delegation depth limit, and this thread's own provider, model and depth.",
      Nil{}, Nil{}),
    Tool.def("delegate_task",
      "Delegate one task to a child agent of THIS thread, on any provider/model (see orchestrator_capabilities). The child sees only `prompt` (no conversation history) and works in this thread's directory. Its result arrives in this thread as a message when it finishes, so end your turn instead of polling; use task_status only when you need it mid-turn. Delegation is limited in depth; children of children are allowed up to the limit.",
      [Tool.prop("prompt", "string", "The complete task for the child, with every detail it needs."),
       Tool.prop("provider", "string", "claude, codex or grok (default: this thread's)."),
       Tool.prop("model", "string", "Model for the child (default: this thread's)."),
       Tool.prop("title", "string", "Short title for the child thread.")], ["prompt"]),
    Tool.def("task_status", "Read a delegated task: state (queued, running, done, failed, cancelled), the child's thread, and its result summary once finished.",
      [Tool.prop("taskId", "string", "The task id delegate_task returned.")], ["taskId"]),
    Tool.def("task_cancel", "Cancel a running delegated task (stops its child agent). Finished tasks keep their result.",
      [Tool.prop("taskId", "string", "The task id.")], ["taskId"]),
    Tool.def("thread_list", "List the threads of this thread's project (id, title, provider, model, turn state), newest activity first.", Nil{}, Nil{}),
    Tool.def("thread_read", "Read a thread's timeline in this project: messages and tool activity, oldest first (the last `limit` entries).",
      [Tool.prop("threadId", "string", "The thread to read."), Tool.prop("limit", "number", "How many entries (default 40).")], ["threadId"]),
    Tool.def("thread_send", "Send a message to another thread in this project; it starts a turn there (or queues behind the running one).",
      [Tool.prop("threadId", "string", "The thread."), Tool.prop("text", "string", "The message.")], ["threadId", "text"]),
    Tool.def("viewer_show",
      "Show a file in the user's Backplane viewer panel: a .kicad_pcb (board), .kicad_sch (schematic), .step/.stp or .glb (3D). Use it after changing a design so the user sees the result; the viewer also follows the file live.",
      [Tool.prop("path", "string", "Absolute path of the file."), Tool.prop("kind", "string", "board, schematic, 3d or step (default: from the extension).")], ["path"])]
    , List.append(&2, J.Json, Mcp.preview_tools(), [Tool.def("permission_prompt", "Internal to Backplane: asks the user before a tool runs. Do not call it yourself.",
      [Tool.prop("tool_name", "string", "The tool."), Tool.prop("input", "object", "Its input."), Tool.prop("tool_use_id", "string", "The call.")], ["tool_name", "input"])])))}])

def Mcp.thread_json(t: M.Thread) -> J.Json:
  match t:
    case M.Thread{id, project, title, _, act, turn, _, _, _, _, _, _, _, _, _, provider, model, _, _, _, _}:
      J.Json.obj([J.KV{"id", J.Str{id}}, J.KV{"project", J.Str{project}}, J.KV{"title", J.Str{title}}, J.KV{"provider", J.Str{provider}},
        J.KV{"model", J.Str{model}}, J.KV{"turn", J.Str{C.Turn.name(turn)}}, J.KV{"activity", C.Codec.nat(act)}])

# Handlers
# --------

def Mcp.caps(+s: M.State, +thread: String, +models: J.Json) -> J.Json:
  J.Json.obj([J.KV{"providers", models}, J.KV{"maxDepth", C.Codec.nat(M.Task.max_depth())},
    J.KV{"thread", Mcp.thread_json(B.Hub.thread(s, thread))}, J.KV{"depth", C.Codec.nat(B.Task.depth(s, thread))}])

def Mcp.task_json(t: M.Task) -> J.Json:
  match t:
    case M.Task{id, parent, child, depth, st, summary, _, provider, model}:
      J.Json.obj([J.KV{"taskId", J.Str{id}}, J.KV{"parentThreadId", J.Str{parent}}, J.KV{"childThreadId", J.Str{child}},
        J.KV{"depth", C.Codec.nat(depth)}, J.KV{"state", J.Str{C.TaskSt.name(st)}}, J.KV{"provider", J.Str{provider}},
        J.KV{"model", J.Str{model}}, J.KV{"summary", J.Str{summary}}])

# a tool call's outcome: success flag, JSON body, and the hub step to run
type Res is Data:
  Res{ok: Bool, body: J.Json, step: B.Step}

def Res.fail(msg: String) -> Res:
  Res{False{}, Mcp.fail(msg), B.Step.none()}

def Res.ok(body: J.Json) -> Res:
  Res{True{}, body, B.Step.none()}

def Mcp.task.hit(ts: List<&2, M.Task>, +id: String, +thread: String) -> Bool:
  match ts:
    case M.Task{i, p, _, _, _, _, _, _, _} <> _:
      Bool.and(String.eq(i, id), String.eq(p, thread))
    case Nil{}:
      False{}

def Mcp.task.go(ts: List<&2, M.Task>, hit: Bool, +id: String, +thread: String) -> Maybe<&2, M.Task>:
  match ts hit:
    case t <> _ True{}:
      Some{t}
    case _ <> +rest False{}:
      Mcp.task.go(rest, Mcp.task.hit(rest, id, thread), id, thread)
    case Nil{} _:
      None{}

def Mcp.task.k(+ts: List<&2, M.Task>, +id: String, +thread: String) -> Maybe<&2, M.Task>:
  Mcp.task.go(ts, Mcp.task.hit(ts, id, thread), id, thread)

# a task this thread delegated (other threads' tasks are not its business)
def Mcp.task(s: M.State, +id: String, +thread: String) -> Maybe<&2, M.Task>:
  match s:
    case M.State{_, _, _, _, tk, _, _, _, _, _}:
      Mcp.task.k(Map.values(&2, M.Task, tk), id, thread)

def Mcp.status(m: Maybe<&2, M.Task>) -> Res:
  match m:
    case Some{t}:
      Res.ok(Mcp.task_json(t))
    case None{}:
      Res.fail("no such task of this thread")

def Mcp.cancel(m: Maybe<&2, M.Task>, +now: Nat) -> Res:
  match m:
    case Some{M.Task{+id, p, +child, d, st, su, dl, pr, mo}}:
      Res{True{}, Mcp.task_json(M.Task{id, p, child, d, M.TaskState.next(st, M.TaskCancelled{}), su, dl, pr, mo}),
        B.Step{[M.TaskStateSet{id, M.TaskCancelled{}, "cancelled by the parent", now}, M.TurnChanged{child, M.Interrupted{}, now}], [B.AgentStop{child}]}}
    case None{}:
      Res.fail("no such task of this thread")

# Delegation
# ----------

def Mcp.or(+v: String, +d: String) -> String:
  Bool.pick(String, String.is_empty(v), d, v)

def Mcp.delegate.go(+s: M.State, +now: Nat, +parent: String, +project: String, env: M.EnvMode, +branch: String, +wt: String, +provider: String, +model: String,
    +rm: M.RuntimeMode, im: M.InteractionMode, +prompt: String, +title: String) -> Res:
  +seq = {B.Hub.seq(s) : Nat}
  +task = {B.Hub.id("k", now, seq) : String}
  +child = {B.Hub.id("t", now, 1n+seq) : String}
  +depth = {1n+B.Task.depth(s, parent) : Nat}
  +name = {Mcp.or(title, B.Hub.title.of(prompt)) : String}
  +cwd = {Bool.pick(String, String.is_empty(wt), B.Hub.project.root(B.Hub.project(s, project)), wt) : String}
  Res{True{}, J.Json.obj([J.KV{"taskId", J.Str{task}}, J.KV{"childThreadId", J.Str{child}}, J.KV{"state", J.Str{"running"}},
      J.KV{"provider", J.Str{provider}}, J.KV{"model", J.Str{model}}, J.KV{"depth", C.Codec.nat(depth)},
      J.KV{"note", J.Str{"The result will arrive in this thread as a message when the child finishes. End your turn instead of polling."}}]),
    B.Step{[M.ThreadCreated{child, project, name, env, branch, wt, provider, model, now},
        M.ModesSet{child, rm, im, model, now},
        M.TaskDelegated{task, parent, child, depth, provider, model, now},
        M.TaskStateSet{task, M.TaskRunning{}, "", now},
        M.MessagePosted{child, B.Hub.id("m", now, 2n+seq), M.User{}, prompt, now},
        M.TurnChanged{child, M.Running{}, now}],
      B.Hub.run(M.Thread{child, project, name, now, now, M.Running{}, 0n, False{}, M.NoOverride{}, 0n, 0n, False{}, M.Local{}, branch, wt, provider, model, rm, M.DefaultMode{}, "", False{}}, cwd, prompt)}}

def Mcp.delegate.k(ok: Bool, t: M.Thread, +s: M.State, +now: Nat, +thread: String, +p: J.Json) -> Res:
  match ok t:
    case False{} _:
      Res.fail("delegation depth limit reached: finish this task yourself")
    case True{} M.Thread{_, +project, _, _, _, _, _, _, _, _, _, _, env, +branch, +wt, +provider, +model, rm, im, _, _}:
      Mcp.delegate.go(s, now, thread, project, env, branch, wt, Mcp.or(J.Json.get_str(p, "provider", ""), provider),
        Mcp.or(J.Json.get_str(p, "model", ""), Bool.pick(String, String.eq(J.Json.get_str(p, "provider", provider), provider), model, "")),
        rm, im, J.Json.get_str(p, "prompt", ""), J.Json.get_str(p, "title", ""))

def Mcp.delegate(+s: M.State, +now: Nat, +thread: String, +p: J.Json) -> Res:
  Mcp.delegate.k(M.Task.may_delegate(B.Task.depth(s, thread)), B.Hub.thread(s, thread), s, now, thread, p)

def Mcp.project_of(t: M.Thread) -> String:
  match t:
    case M.Thread{_, p, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      p

# Threads
# -------

def Mcp.same_project(+s: M.State, +a: String, +b: String) -> Bool:
  String.eq(Mcp.project_of(B.Hub.thread(s, a)), Mcp.project_of(B.Hub.thread(s, b)))

def Mcp.threads.k(keep: Bool, t: M.Thread, rest: List<&2, J.Json>) -> List<&2, J.Json>:
  match keep:
    case True{}:
      Mcp.thread_json(t) <> rest
    case False{}:
      rest

def Mcp.visible(t: M.Thread, +project: String) -> Bool:
  match t:
    case M.Thread{_, p, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, de}:
      Bool.and(String.eq(p, project), Bool.not(de))

def Mcp.threads(ts: List<&2, M.Thread>, +project: String) -> List<&2, J.Json>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> rest:
      Mcp.threads.k(Mcp.visible(t, project), t, Mcp.threads(rest, project))

def Mcp.list(+s: M.State, +thread: String) -> Res:
  match s:
    case M.State{_, ts, _, _, _, _, _, _, _, _}:
      Res.ok(J.Json.obj([J.KV{"threads", J.Json.arr(Mcp.threads(Map.values(&2, M.Thread, ts), Mcp.project_of(B.Hub.thread(s, thread))))}]))

def Mcp.entry(e: M.Entry) -> J.Json:
  match e:
    case M.Msg{_, _, role, text, at}:
      J.Json.obj([J.KV{"kind", J.Str{"message"}}, J.KV{"role", J.Str{C.Role.name(role)}}, J.KV{"text", J.Str{text}}, J.KV{"at", C.Codec.nat(at)}])
    case M.Act{_, _, tone, kind, summary, at}:
      J.Json.obj([J.KV{"kind", J.Str{"activity"}}, J.KV{"tone", J.Str{tone}}, J.KV{"tool", J.Str{kind}}, J.KV{"summary", J.Str{summary}}, J.KV{"at", C.Codec.nat(at)}])

def Mcp.mine.k(same: Bool, e: M.Entry, rest: List<&2, J.Json>) -> List<&2, J.Json>:
  match same:
    case True{}:
      Mcp.entry(e) <> rest
    case False{}:
      rest

def Mcp.of(e: M.Entry) -> String:
  match e:
    case M.Msg{_, t, _, _, _}:
      t
    case M.Act{_, t, _, _, _, _}:
      t

# a thread's entries, oldest first
def Mcp.mine(es: List<&2, M.Entry>, +th: String, acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match es:
    case Nil{}:
      acc
    case +e <> t:
      Mcp.mine(t, th, Mcp.mine.k(String.eq(Mcp.of(e), th), e, acc))

def Mcp.read.last(+xs: List<&2, J.Json>, +limit: Nat, +target: String) -> Res:
  Res.ok(J.Json.obj([J.KV{"threadId", J.Str{target}},
    J.KV{"entries", J.Json.arr(List.drop(&2, J.Json, xs, Nat.sub(List.length(&2, J.Json, xs), limit)))}]))

def Mcp.read.k(ok: Bool, +s: M.State, +target: String, +limit: Nat) -> Res:
  match ok s:
    case True{} M.State{_, _, es, _, _, _, _, _, _, _}:
      Mcp.read.last(Mcp.mine(es, target, Nil{}), limit, target)
    case False{} _:
      Res.fail("that thread is not in this project")

def Mcp.send.k(ok: Bool, +s: M.State, +now: Nat, +thread: String, +target: String, +text: String) -> Res:
  match ok:
    case True{}:
      Res{True{}, J.Json.obj([J.KV{"threadId", J.Str{target}}, J.KV{"state", J.Str{"sent"}}]),
        B.Hub.inbox(s, now, thread, target, M.User{}, text)}
    case False{}:
      Res.fail("that thread is not in this project")

# the file goes to the viewer of the thread that asked
def Mcp.view(+thread: String, +path: String, +kind: String) -> Res:
  Res{True{}, J.Json.obj([J.KV{"shown", J.Str{path}}]),
    B.Step{Nil{}, [B.Broadcast{J.Json.show(J.Json.obj([J.KV{"t", J.Str{"view"}}, J.KV{"thread", J.Str{thread}}, J.KV{"path", J.Str{path}}, J.KV{"kind", J.Str{kind}}]))}]}}

def Mcp.names() -> List<&2, String>:
  ["orchestrator_capabilities", "delegate_task", "task_status", "task_cancel", "thread_list", "thread_read", "thread_send", "viewer_show"]

def Mcp.call.k(i: Nat, +s: M.State, +now: Nat, +thread: String, +models: J.Json, +a: J.Json) -> Res:
  match i:
    case 0n:
      Res.ok(Mcp.caps(s, thread, models))
    case 1n:
      Mcp.delegate(s, now, thread, a)
    case 2n:
      Mcp.status(Mcp.task(s, J.Json.get_str(a, "taskId", ""), thread))
    case 3n:
      Mcp.cancel(Mcp.task(s, J.Json.get_str(a, "taskId", ""), thread), now)
    case 4n:
      Mcp.list(s, thread)
    case 5n:
      Mcp.read.k(Mcp.same_project(s, thread, J.Json.get_str(a, "threadId", "")), s, J.Json.get_str(a, "threadId", ""),
        Maybe.default(&2, Nat, Nat.read(J.Json.as_raw(J.Json.get(a, "limit"), "40")), 40n))
    case 6n:
      Mcp.send.k(Mcp.same_project(s, thread, J.Json.get_str(a, "threadId", "")), s, now, thread, J.Json.get_str(a, "threadId", ""), J.Json.get_str(a, "text", ""))
    case 7n:
      Mcp.view(thread, J.Json.get_str(a, "path", ""), J.Json.get_str(a, "kind", ""))
    case _:
      Res.fail("unknown tool")

# Permission prompts (Claude's --permission-prompt-tool)
# -----------------------------------------------------
# Claude asks before a tool runs outside full access. The request becomes
# an ask the user answers; the MCP reply waits (the server parks it) until
# then. AskUserQuestion becomes a question; ExitPlanMode's plan becomes a
# proposed plan, and Claude is told to stop and wait.

def Perm.text(+verdict: J.Json) -> J.Json:
  J.Json.obj([J.KV{"content", J.Json.arr([J.Json.obj([J.KV{"type", J.Str{"text"}}, J.KV{"text", J.Str{J.Json.show(verdict)}}])])}])

def Perm.allow(+input: J.Json) -> J.Json:
  J.Json.obj([J.KV{"behavior", J.Str{"allow"}}, J.KV{"updatedInput", input}])

def Perm.deny(+msg: String) -> J.Json:
  J.Json.obj([J.KV{"behavior", J.Str{"deny"}}, J.KV{"message", J.Str{msg}}])

def Perm.plan_note() -> String:
  "The client captured your proposed plan. Stop here and wait for the user's feedback or implementation request."

def Perm.detail.k(+short: String, +input: J.Json) -> String:
  Bool.pick(String, String.is_empty(short), String.take(J.Json.show(input), 400n), short)

# what the approval card says the tool will do
def Perm.detail(+tool: String, +input: J.Json) -> String:
  Perm.detail.k(J.Json.get_str(input, "command", J.Json.get_str(input, "file_path", J.Json.get_str(input, "url", J.Json.get_str(input, "pattern", "")))), input)

def Perm.first_q(+input: J.Json) -> J.Json:
  Maybe.default(&2, J.Json, List.head(&2, J.Json, J.Json.elems(J.Json.get_obj(input, "questions"))), J.Null{})

def Perm.labels(os: List<&2, J.Json>) -> List<&2, String>:
  match os:
    case Nil{}:
      Nil{}
    case +o <> t:
      J.Json.get_str(o, "label", J.Json.show(o)) <> Perm.labels(t)

def Perm.question(+input: J.Json) -> String:
  J.Json.get_str(Perm.first_q(input), "question", J.Json.get_str(input, "question", ""))

def Perm.options(+input: J.Json) -> String:
  String.join(Perm.labels(J.Json.elems(J.Json.get_obj(Perm.first_q(input), "options"))), "\n")

def Perm.session_ok(as: List<&2, M.Ask>, +thread: String, +tool: String) -> Bool:
  match as:
    case Nil{}:
      False{}
    case M.Ask{_, th, k, t, _, _, _, an} <> rest:
      Bool.or(Bool.and(Bool.and(String.eq(th, thread), String.eq(t, tool)), Bool.and(String.eq(k, "approval"), String.eq(an, "session"))), Perm.session_ok(rest, thread, tool))

def Perm.approve(ok: Bool, +ask: String, +s: M.State, +now: Nat, +thread: String, +id: J.Json, +tool: String, +input: J.Json) -> McpOut:
  match ok:
    case True{}:
      McpOut{Mcp.result(id, Perm.text(Perm.allow(input))), B.Step.none(), ""}
    case False{}:
      McpOut{"", B.Step{[M.AskOpened{ask, thread, "approval", tool, Perm.detail(tool, input), "", now}], Nil{}}, ask}

def Perm.k(i: Nat, +ask: String, +s: M.State, +now: Nat, +thread: String, +id: J.Json, +tool: String, +input: J.Json) -> McpOut:
  match i:
    case 0n:
      McpOut{"", B.Step{[M.AskOpened{ask, thread, "input", tool, Perm.question(input), Perm.options(input), now}], Nil{}}, ask}
    case 1n:
      McpOut{Mcp.result(id, Perm.text(Perm.deny(Perm.plan_note()))), B.Step{[M.AskOpened{ask, thread, "plan", tool, J.Json.get_str(input, "plan", ""), "", now}], Nil{}}, ""}
    case _:
      Perm.approve(Perm.session_ok(M.Asks.all(s), thread, tool), ask, s, now, thread, id, tool, input)

def Mcp.permit(+s: M.State, +now: Nat, +thread: String, +id: J.Json, +a: J.Json) -> McpOut:
  Perm.k(C.Codec.pos(["AskUserQuestion", "ExitPlanMode"], J.Json.get_str(a, "tool_name", "")), B.Hub.id("q", now, B.Hub.seq(s)), s, now, thread, id, J.Json.get_str(a, "tool_name", ""), J.Json.get_obj(a, "input"))

def Perm.answers.k(input: J.Json, extra: J.Json) -> J.Json:
  match input extra:
    case J.Obj{fs} J.Obj{J.Field{k, v, _}}:
      J.Obj{J.Field{k, v, fs}}
    case _ _:
      input

def Perm.answers(+input: J.Json, +answer: String) -> J.Json:
  Perm.answers.k(input, J.Json.obj([J.KV{"answers", J.Json.obj([J.KV{Perm.question(input), J.Str{answer}}])}]))

def Perm.verdict.k(i: Nat, +tool: String, +input: J.Json, +answer: String) -> J.Json:
  match i:
    case 0n:
      Bool.pick(J.Json, String.is_empty(answer), Perm.deny("The user dismissed the question."), Perm.allow(Perm.answers(input, answer)))
    case _:
      Bool.pick(J.Json, Bool.or(String.eq(answer, "accept"), String.eq(answer, "session")), Perm.allow(input), Perm.deny("The user declined this tool call."))

def Mcp.permission.reply.k(+o: J.Json, +answer: String) -> String:
  Mcp.result(J.Json.get_obj(o, "id"), Perm.text(Perm.verdict.k(C.Codec.pos(["AskUserQuestion"], J.Json.get_str(J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments"), "tool_name", "")),
    J.Json.get_str(J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments"), "tool_name", ""), J.Json.get_obj(J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments"), "input"), answer)))

def Mcp.permission.reply.acp(acp: Bool, +o: J.Json, +body: String, +answer: String) -> String:
  match acp:
    case True{}:
      AC.Acp.permit.answer(body, answer)
    case False{}:
      Mcp.permission.reply.k(o, answer)

# the parked reply for a request body, once the user answered: an MCP
# permission_prompt result, or the ACP response to a Grok request
def Mcp.permission.reply(+body: String, +answer: String) -> String:
  Mcp.permission.reply.acp(String.eq(J.Json.get_str(Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{}), "method", ""), "session/request_permission"),
    Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{}), body, answer)

def Mcp.reply(+id: J.Json, r: Res) -> McpOut:
  match r:
    case Res{ok, body, st}:
      McpOut{Mcp.result(id, Mcp.content(ok, body)), st, ""}

def Mcp.call.route(perm: Bool, +s: M.State, +now: Nat, +thread: String, +models: J.Json, +id: J.Json, +p: J.Json) -> McpOut:
  match perm:
    case True{}:
      Mcp.permit(s, now, thread, id, J.Json.get_obj(p, "arguments"))
    case False{}:
      Mcp.reply(id, Mcp.call.k(C.Codec.pos(Mcp.names(), J.Json.get_str(p, "name", "")), s, now, thread, models, J.Json.get_obj(p, "arguments")))

def Mcp.method.k(i: Nat, +s: M.State, +now: Nat, +thread: String, +models: J.Json, +version: String, +id: J.Json, +p: J.Json) -> McpOut:
  match i:
    case 0n:
      McpOut{Mcp.result(id, J.Json.obj([J.KV{"protocolVersion", J.Str{Mcp.or(J.Json.get_str(p, "protocolVersion", ""), "2025-06-18")}},
        J.KV{"capabilities", J.Json.obj([J.KV{"tools", J.Json.obj(Nil{})}])},
        J.KV{"serverInfo", J.Json.obj([J.KV{"name", J.Str{"backplane"}}, J.KV{"version", J.Str{version}}])}])), B.Step.none(), ""}
    case 1n:
      McpOut{Mcp.result(id, Mcp.tools()), B.Step.none(), ""}
    case 2n:
      Mcp.call.route(String.eq(J.Json.get_str(p, "name", ""), "permission_prompt"), s, now, thread, models, id, p)
    case 3n:
      McpOut{Mcp.result(id, J.Json.obj(Nil{})), B.Step.none(), ""}
    case 4n:
      McpOut{"", B.Step.none(), ""}
    case _:
      McpOut{Mcp.error(id, "-32601", "method not found"), B.Step.none(), ""}

def Mcp.method.pos.k(note: Bool, +m: String) -> Nat:
  match note:
    case True{}:
      4n
    case False{}:
      C.Codec.pos(["initialize", "tools/list", "tools/call", "ping"], m)

def Mcp.method.pos(+m: String) -> Nat:
  Mcp.method.pos.k(String.starts_with(m, "notifications/"), m)

# Grok's permission requests
# --------------------------
# The Grok runner hands an ACP session/request_permission here (Grok has
# no permission MCP tool): a tool already allowed for the session in this
# thread is allowed again at once; otherwise it becomes an approval ask
# and the request waits, parked, for the user's answer (Park, then
# Acp.permit.answer).

def Grok.permit.k(ok: Bool, +ask: String, +now: Nat, +thread: String, +o: J.Json, +tool: String) -> McpOut:
  match ok:
    case True{}:
      McpOut{AC.Acp.permit.reply(AC.Acp.id(J.Json.get(o, "id")), J.Json.get_obj(o, "params"), "accept"), B.Step.none(), ""}
    case False{}:
      McpOut{"", B.Step{[M.AskOpened{ask, thread, "approval", tool, AC.Acp.detail(J.Json.get_obj(o, "params")), "", now}], Nil{}}, ask}

def Grok.permit(+s: M.State, +now: Nat, +thread: String, +o: J.Json) -> McpOut:
  Grok.permit.k(Perm.session_ok(M.Asks.all(s), thread, AC.Acp.tool(J.Json.get_obj(o, "params"))), B.Hub.id("q", now, B.Hub.seq(s)), now, thread, o,
    AC.Acp.tool(J.Json.get_obj(o, "params")))

def Mcp.handle.k(grok: Bool, +s: M.State, +now: Nat, +thread: String, +models: J.Json, +version: String, +o: J.Json) -> McpOut:
  match grok:
    case True{}:
      Grok.permit(s, now, thread, o)
    case False{}:
      Mcp.method.k(Mcp.method.pos(J.Json.get_str(o, "method", "")), s, now, thread, models, version, J.Json.get_obj(o, "id"), J.Json.get_obj(o, "params"))

# one JSON-RPC message from an agent of `thread` ("" reply: a notification)
def Mcp.handle(+s: M.State, +now: Nat, +thread: String, +models: J.Json, +version: String, +o: J.Json) -> McpOut:
  Mcp.handle.k(String.eq(J.Json.get_str(o, "method", ""), "session/request_permission"), s, now, thread, models, version, o)

def Mcp.text.k(m: Maybe<&2, J.Json>, +s: M.State, +now: Nat, +thread: String, +models: J.Json, +version: String) -> McpOut:
  match m:
    case Some{+o}:
      Mcp.handle(s, now, thread, models, version, o)
    case None{}:
      McpOut{Mcp.error(J.Null{}, "-32700", "parse error"), B.Step.none(), ""}

def Mcp.text(+s: M.State, +now: Nat, +thread: String, +models: J.Json, +version: String, body: String) -> McpOut:
  Mcp.text.k(J.Json.parse(body), s, now, thread, models, version)
