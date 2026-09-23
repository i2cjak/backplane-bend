import Base
import ./json.bend as J
import ./model.bend as M
import ./codec.bend as C
import ./hub.bend as B

# The Backplane MCP server, as a decider. Each agent session gets its own
# endpoint (/mcp/<thread>), so every call knows which thread is asking. A
# call answers a JSON-RPC reply now, plus the changes and effects of a hub
# step. Tools follow T3Code's orchestrator toolkit: delegate work to another
# model, watch it, and read or message other threads, within the laws of
# model.bend (bounded depth, forward-only task states, one delivery).

type McpOut is Data:
  McpOut{reply: String, step: B.Step}

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

def Mcp.tools() -> J.Json:
  J.Json.obj([J.KV{"tools", J.Json.arr([
    Tool.def("orchestrator_capabilities",
      "List the providers and models this Backplane can run, the delegation depth limit, and this thread's own provider, model and depth.",
      Nil{}, Nil{}),
    Tool.def("delegate_task",
      "Delegate one task to a child agent of THIS thread, on any provider/model (see orchestrator_capabilities). The child sees only `prompt` (no conversation history) and works in this thread's directory. Its result arrives in this thread as a message when it finishes, so end your turn instead of polling; use task_status only when you need it mid-turn. Delegation is limited in depth; children of children are allowed up to the limit.",
      [Tool.prop("prompt", "string", "The complete task for the child, with every detail it needs."),
       Tool.prop("provider", "string", "claude or codex (default: this thread's)."),
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
      [Tool.prop("path", "string", "Absolute path of the file."), Tool.prop("kind", "string", "board, schematic, 3d or step (default: from the extension).")], ["path"])])}])

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
    case M.State{_, _, _, _, tk, _}:
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
    case M.State{_, ts, _, _, _, _}:
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
    case True{} M.State{_, _, es, _, _, _}:
      Mcp.read.last(Mcp.mine(es, target, Nil{}), limit, target)
    case False{} _:
      Res.fail("that thread is not in this project")

def Mcp.send.k(ok: Bool, +s: M.State, +now: Nat, +target: String, +text: String) -> Res:
  match ok:
    case True{}:
      Res{True{}, J.Json.obj([J.KV{"threadId", J.Str{target}}, J.KV{"state", J.Str{"sent"}}]),
        B.Step{[M.MessagePosted{target, B.Hub.id("m", now, B.Hub.seq(s)), M.User{}, text, now}, M.TurnChanged{target, M.Running{}, now}],
          B.Hub.run(B.Hub.thread(s, target), B.Hub.cwd(s, B.Hub.thread(s, target)), text)}}
    case False{}:
      Res.fail("that thread is not in this project")

def Mcp.view(+path: String, +kind: String) -> Res:
  Res{True{}, J.Json.obj([J.KV{"shown", J.Str{path}}]),
    B.Step{Nil{}, [B.Broadcast{J.Json.show(J.Json.obj([J.KV{"t", J.Str{"view"}}, J.KV{"path", J.Str{path}}, J.KV{"kind", J.Str{kind}}]))}]}}

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
      Mcp.send.k(Mcp.same_project(s, thread, J.Json.get_str(a, "threadId", "")), s, now, J.Json.get_str(a, "threadId", ""), J.Json.get_str(a, "text", ""))
    case 7n:
      Mcp.view(J.Json.get_str(a, "path", ""), J.Json.get_str(a, "kind", ""))
    case _:
      Res.fail("unknown tool")

def Mcp.reply(+id: J.Json, r: Res) -> McpOut:
  match r:
    case Res{ok, body, st}:
      McpOut{Mcp.result(id, Mcp.content(ok, body)), st}

def Mcp.method.k(i: Nat, +s: M.State, +now: Nat, +thread: String, +models: J.Json, +version: String, +id: J.Json, +p: J.Json) -> McpOut:
  match i:
    case 0n:
      McpOut{Mcp.result(id, J.Json.obj([J.KV{"protocolVersion", J.Str{Mcp.or(J.Json.get_str(p, "protocolVersion", ""), "2025-06-18")}},
        J.KV{"capabilities", J.Json.obj([J.KV{"tools", J.Json.obj(Nil{})}])},
        J.KV{"serverInfo", J.Json.obj([J.KV{"name", J.Str{"backplane"}}, J.KV{"version", J.Str{version}}])}])), B.Step.none()}
    case 1n:
      McpOut{Mcp.result(id, Mcp.tools()), B.Step.none()}
    case 2n:
      Mcp.reply(id, Mcp.call.k(C.Codec.pos(Mcp.names(), J.Json.get_str(p, "name", "")), s, now, thread, models, J.Json.get_obj(p, "arguments")))
    case 3n:
      McpOut{Mcp.result(id, J.Json.obj(Nil{})), B.Step.none()}
    case 4n:
      McpOut{"", B.Step.none()}
    case _:
      McpOut{Mcp.error(id, "-32601", "method not found"), B.Step.none()}

def Mcp.method.pos.k(note: Bool, +m: String) -> Nat:
  match note:
    case True{}:
      4n
    case False{}:
      C.Codec.pos(["initialize", "tools/list", "tools/call", "ping"], m)

def Mcp.method.pos(+m: String) -> Nat:
  Mcp.method.pos.k(String.starts_with(m, "notifications/"), m)

# one JSON-RPC message from an agent of `thread` ("" reply: a notification)
def Mcp.handle(+s: M.State, +now: Nat, +thread: String, +models: J.Json, +version: String, +o: J.Json) -> McpOut:
  Mcp.method.k(Mcp.method.pos(J.Json.get_str(o, "method", "")), s, now, thread, models, version, J.Json.get_obj(o, "id"), J.Json.get_obj(o, "params"))

def Mcp.text.k(m: Maybe<&2, J.Json>, +s: M.State, +now: Nat, +thread: String, +models: J.Json, +version: String) -> McpOut:
  match m:
    case Some{+o}:
      Mcp.handle(s, now, thread, models, version, o)
    case None{}:
      McpOut{Mcp.error(J.Null{}, "-32700", "parse error"), B.Step.none()}

def Mcp.text(+s: M.State, +now: Nat, +thread: String, +models: J.Json, +version: String, body: String) -> McpOut:
  Mcp.text.k(J.Json.parse(body), s, now, thread, models, version)
