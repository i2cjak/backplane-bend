import Base
import ./model.bend as M

# What every agent session is told, as T3Code/Backplane tell it: a runtime
# block, KiCad guidance, and the KiStack skills with their SKILL.md paths.

type Skill is Data:
  Skill{name: String, description: String, path: String}

# SKILL.md frontmatter
# --------------------

type Front is Data:
  Front{name: String, description: String}

def Skill.unquote.k(a: Bool, b: Bool, +s: String) -> String:
  match a b:
    case True{} True{}:
      String.take(String.drop(s, 1n), Nat.sub(String.length(s), 2n))
    case _ _:
      s

def Skill.unquote(+s: String) -> String:
  Skill.unquote.k(String.starts_with(s, "\""), String.ends_with(s, "\""), s)

def Skill.field.k(hit: Bool, +line: String, +key: String) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{Skill.unquote(String.trim(String.drop(line, 1n+String.length(key))))}
    case False{}:
      None{}

def Skill.field(+line: String, +key: String) -> Maybe<&2, String>:
  Skill.field.k(String.starts_with(line, key ++ ":"), line, key)

def Front.step(f: Front, +line: String) -> Front:
  match f:
    case Front{n, d}:
      Front{Maybe.default(&2, String, Skill.field(line, "name"), n), Maybe.default(&2, String, Skill.field(line, "description"), d)}

def Front.stop(ls: List<&2, String>) -> Bool:
  match ls:
    case l <> _:
      String.eq(String.trim(l), "---")
    case Nil{}:
      True{}

# fold frontmatter lines until the closing ---; `stop` is the head's verdict
def Front.go(ls: List<&2, String>, stop: Bool, f: Front) -> Front:
  match ls stop:
    case +l <> +t False{}:
      Front.go(t, Front.stop(t), Front.step(f, l))
    case _ _:
      f

def Skill.front.open(open: Bool, +t: List<&2, String>, +dflt: String) -> Front:
  match open:
    case True{}:
      Front.go(t, Front.stop(t), Front{dflt, ""})
    case False{}:
      Front{dflt, ""}

# name and description from a SKILL.md's leading --- block
def Skill.front.k(ls: List<&2, String>, +dflt: String) -> Front:
  match ls:
    case +l <> t:
      Skill.front.open(String.eq(String.trim(l), "---"), t, dflt)
    case Nil{}:
      Front{dflt, ""}

def Skill.parse.k(f: Front, path: String) -> Skill:
  match f:
    case Front{n, d}:
      Skill{n, d, path}

def Skill.parse(text: String, +dflt: String, path: String) -> Skill:
  Skill.parse.k(Skill.front.k(String.lines(text), dflt), path)

# The runtime block
# -----------------

def Prompt.skill_line(s: Skill) -> String:
  match s:
    case Skill{n, d, p}:
      "- " ++ n ++ ": " ++ d ++ " Read \"" ++ p ++ "\""

def Prompt.lines(ss: List<&2, Skill>) -> List<&2, String>:
  match ss:
    case Nil{}:
      Nil{}
    case s <> t:
      Prompt.skill_line(s) <> Prompt.lines(t)

def Prompt.skills(ss: List<&2, Skill>) -> String:
  String.join(Prompt.lines(ss), "\n")

def Prompt.kistack(ss: List<&2, Skill>) -> String:
  "<kistack_skills>\nBefore doing any work related to any skill listed below, you MUST read that skill's complete SKILL.md and follow its instructions and workflow. Apply every relevant skill, even when the user does not explicitly name it. Do not skip a relevant skill because you already know how to do the task.\n"
  ++ "<backplane_kicad_board_editing>For normal KiCad PCB placement, routing, and cleanup, identify the project's canonical configured .kicad_pcb path (the board opened by the project or viewer) and keep using that exact path. Save each meaningful milestone to it so the active board and collaborators show progress. Keep backups and intermediate tool outputs in a separate backup or build directory. If a tool writes a staging or alternate file, validate it and promote the result back to the canonical path with a backup before continuing; do not silently switch the active filename. Use an alternate board only when the user explicitly requests an experiment or alternate design, and label it clearly. Coordinate ownership so only one agent or process writes the active board at a time; other agents may inspect it or prepare changes for integration.</backplane_kicad_board_editing>\n"
  ++ "Backplane includes KiStack by American Embedded (https://github.com/American-Embedded/kistack). These skills are always available in every project.\n"
  ++ "Resolve referenced scripts and documents relative to that skill's directory. User instructions take precedence. Other installed skills remain available.\n"
  ++ Prompt.skills(ss) ++ "\n</kistack_skills>"

# the text every agent gets, before its per-thread blocks
def Prompt.runtime(harness: String, ss: List<&2, Skill>) -> String:
  "<runtime_info>In case you're asked: you are running in Backplane through the " ++ harness
  ++ " harness. No need to mention this otherwise. You can embed images and videos in your response using Markdown with absolute file paths.</runtime_info>\n\n"
  ++ "<backplane_images>To show the user an image (a board render, plot, screenshot or photo), save it as PNG or JPEG and write its absolute path in your reply, e.g. /tmp/board-top.png (no spaces in the path). Backplane draws every such image under your message.</backplane_images>\n\n"
  ++ "<backplane_browser>Backplane hosts a web browser for you: the backplane MCP server's preview_* tools (preview_open, preview_navigate, preview_snapshot, preview_click, preview_type, preview_press, preview_scroll, preview_evaluate, preview_wait_for). The user watches it live in the app's Browser tab. Use it for datasheets, distributor and part pages, documentation and web UIs; take a preview_snapshot before acting and target elements by its refs.</backplane_browser>\n\n"
  ++ Prompt.kistack(ss)

# Mechanical work: FreeCAD, run headless, for the modelling, and
# Backplane's own renderer for the pictures. Parts live in the project's
# mech/ folder, whose renders the Mechanical page shows
def Prompt.mech.freecad(none: Bool, +fc: String) -> String:
  match none:
    case True{}:
      "FreeCAD is not installed on this machine. When a task needs a part modelled, changed or exported, tell the user FreeCAD is missing and that they can install it from freecad.org/downloads or their package manager (Backplane finds `freecadcmd` on PATH, or set BACKPLANE_FREECAD to it); meanwhile you can still render and inspect existing STEP files."
    case False{}:
      "Model with FreeCAD, headless: `\"" ++ fc ++ "\" -c \"exec(open('mech/<part>.py').read())\"` runs a script with FreeCAD's Python modules (Part, PartDesign, Sketcher, Import, Mesh). Each part is one script in the project's `mech/` folder with its dimensions as named parameters at the top, in millimetres, Z up, the part's front facing -Y; it checks `shape.isValid()`, saves `mech/<part>.FCStd` and exports `mech/<part>.step` (`Part.export` or `Import.export`). An assembly is one more script that places the parts and exports one STEP."

def Prompt.mech.loop(+render: String) -> String:
  " Work in this loop, in as few steps as you can: 1. write or edit `mech/<part>.py`; 2. run it and read any error; 3. call the backplane MCP tool `viewer_show` with the STEP's path and kind `mech`: the user turns the part in 3D on their Mech page, which lists every part in `mech/` and draws renders when they ask. Rendering is optional: only when you need to see the result yourself, run `\"" ++ render ++ "\" --render mech/a.step mech/b.step` (several parts in one call), which writes small iso, front, top and right views to `mech/renders/<part>.<view>.png` in seconds (a large assembly's first time can take a minute while it is meshed, then it is cached), and look at the iso view first. If `--render` prints an error, tell the user instead of working around the renderer. Parts that already exist elsewhere in the project show on the page once their STEP is copied or exported into `mech/`. For a board in a fit check, `kicad-cli pcb export step --board-only` is enough unless component heights matter: the full board with parts is large and slow."

def Prompt.mech(+fc: String, +render: String) -> String:
  "<backplane_mechanical>For mechanical work (enclosures, brackets, mounts, fixtures, assemblies, fit checks) use FreeCAD and Backplane's renderer, not other CAD or plotting tools. "
  ++ Prompt.mech.freecad(String.is_empty(fc), fc) ++ Prompt.mech.loop(render) ++ "</backplane_mechanical>"

def Prompt.kicad.basics(+cli: String) -> String:
  "Use the selected KiCad CLI at `" ++ cli ++ "` for KiCad work. Check `\"" ++ cli ++ "\" --version` and subcommand `--help`. Export with `\"" ++ cli ++ "\" sch export` or `\"" ++ cli ++ "\" pcb export`; run checks with `\"" ++ cli ++ "\" sch erc` and `\"" ++ cli ++ "\" pcb drc`. Use the full path when invoking it, quoting paths for your shell."

def Prompt.kicad.fork(+cli: String, +version: String, +commit: String) -> String:
  " This is Backplane KiCad " ++ version ++ ", source commit " ++ commit ++ ". For programmatic PCB/schematic edits, start `\"" ++ cli ++ "\" api-server <project-or-file> --socket <unique-socket>` and stop your server when finished. This is NNG/protobuf IPC, not HTTP. Read the matching guide https://github.com/i2cjak/Backplane_KiCad/blob/" ++ commit ++ "/BACKPLANE_IPC.md and examples https://github.com/i2cjak/Backplane_KiCad/tree/" ++ commit ++ "/scripts; protocol definitions are under api/proto at that revision. A Python IPC client is not preinstalled: when needed, use BACKPLANE_PYTHON if set to create an isolated virtualenv, install protobuf==5.29.6, pynng==0.9.0 and grpcio-tools==1.71.0, then generate matching bindings with `python -m grpc_tools.protoc` following the examples. Headless IPC has no interactive canvas; ERC/DRC use the CLI above. Preserve any `<native-filename>.backplane.json` companion metadata when moving or saving project files."

def Prompt.kicad.k(fork: Bool, ipc: Bool, +cli: String, +version: String, +commit: String) -> String:
  match fork ipc:
    case True{} True{}:
      Prompt.kicad.fork(cli, version, commit)
    case True{} False{}:
      " This is Backplane KiCad " ++ version ++ ". KiCad IPC is turned off in Backplane's settings: work through files and the CLI only, and do not start `api-server`."
    case False{} _:
      " No matching Backplane fork manifest was found; check available capabilities before using fork-specific API/IPC commands."

# the KiCad runtime: the fork's IPC server is described only when this is
# the fork and the kicad.ipc setting is on
def Prompt.kicad.at(none: Bool, +cli: String, fork: Bool, +version: String, +commit: String, ipc: Bool) -> String:
  match none:
    case True{}:
      "KiCad is not installed on this machine (no kicad-cli was found). Work on the design files directly, and when a task needs ERC, DRC, exports or another KiCad tool, tell the user KiCad is missing and that they can install it from kicad.org/download or their package manager."
    case False{}:
      Prompt.kicad.basics(cli) ++ Prompt.kicad.k(fork, ipc, cli, version, commit)

def Prompt.kicad(+cli: String, fork: Bool, +version: String, +commit: String, ipc: Bool) -> String:
  "<kicad_runtime>" ++ Prompt.kicad.at(String.is_empty(cli), cli, fork, version, commit, ipc) ++ "</kicad_runtime>"

def Prompt.path(+label: String, +p: String) -> String:
  Bool.pick(String, String.is_empty(p), "", "\n- " ++ label ++ ": `" ++ p ++ "`")

def Prompt.project.k(none: Bool, +pro: String, +pcb: String, +sch: String) -> String:
  match none:
    case True{}:
      "No KiCad project was found in this project root. When you create one, give the .kicad_pro, .kicad_pcb and .kicad_sch the same name so Backplane picks them up, or name them in `.backplane.json`."
    case False{}:
      "This project's canonical KiCad files:" ++ Prompt.path("project", pro) ++ Prompt.path("board", pcb) ++ Prompt.path("schematic", sch)
      ++ "\nWork on these exact paths. Backplane's viewer watches them and shows every save live, so save each meaningful step."

# the files this project is assigned: `.backplane.json` in the project root
# ({"pcb": "...", "schematic": "..."}) wins, else the .kicad_pro's siblings
def Prompt.project(+root: String, +pro: String, +pcb: String, +sch: String) -> String:
  "<backplane_project>Project root: `" ++ root ++ "`. "
  ++ Prompt.project.k(Bool.and(String.is_empty(pcb), String.is_empty(sch)), pro, pcb, sch)
  ++ "\nTo change which files are canonical, edit `.backplane.json` in the project root (keys `pcb`, `schematic`, relative paths). To show the user a board, schematic, 3D model or STEP file, call the backplane MCP tool `viewer_show` with its path.</backplane_project>"

def Prompt.orchestration.k(may: Bool, +models: String) -> String:
  match may:
    case True{}:
      "You may delegate well-scoped, independent pieces of work (footprint or symbol generation, part lookup, ERC/DRC review, mechanical checks) to other models with the backplane MCP tool `delegate_task`; `orchestrator_capabilities` lists them. Models available: " ++ models
      ++ ". A child sees only the prompt you give it, so include paths and acceptance criteria, and say whether it may write the canonical board or schematic: only one agent writes a file at a time. Each result reaches you exactly once as a message when the child finishes; end your turn rather than polling. Finished tasks never restart, and delegation depth is limited. For work the user should see as a thread of its own, `thread_launch` starts one in this project; `thread_send` (mode auto, queue or steer), `thread_wait`, `thread_read`, `thread_interrupt` and `thread_update` (rename, or regenerate a title) work on any thread of this project."
    case False{}:
      "You are a delegated task at the depth limit: do not delegate further. Finish the task and put the result in your final message."

def Prompt.orchestration(may: Bool, +models: String) -> String:
  "<orchestration>" ++ Prompt.orchestration.k(may, models) ++ "</orchestration>"

# Claude Code arguments
# ---------------------

def Claude.permission(r: M.RuntimeMode, i: M.InteractionMode) -> String:
  match r i:
    case _ M.PlanMode{}:
      "plan"
    case M.Supervised{} M.DefaultMode{}:
      "default"
    case M.AcceptEdits{} M.DefaultMode{}:
      "acceptEdits"
    case M.AutoMode{} M.DefaultMode{}:
      "auto"
    case M.FullAccess{} M.DefaultMode{}:
      "bypassPermissions"

def Claude.opt.k(empty: Bool, flag: String, v: String, rest: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}:
      rest
    case False{}:
      flag <> v <> rest

def Claude.opt(flag: String, +v: String, rest: List<&2, String>) -> List<&2, String>:
  Claude.opt.k(String.is_empty(v), flag, v, rest)

def Claude.dirs(ds: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}:
      Nil{}
    case d <> t:
      "--add-dir" <> d <> Claude.dirs(t)

# `claude` flags for a long-lived stream-json session
# outside full access, Claude asks Backplane (the user) before a tool runs
def Claude.ask(r: M.RuntimeMode, i: M.InteractionMode, rest: List<&2, String>) -> List<&2, String>:
  match r i:
    case M.FullAccess{} M.DefaultMode{}:
      rest
    case _ _:
      List.append(&2, String, ["--permission-prompt-tool", "mcp__backplane__permission_prompt"], rest)

def Claude.args(+model: String, +session: String, +r: M.RuntimeMode, +i: M.InteractionMode, prompt: String, +dirs: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, ["-p", "--verbose", "--input-format", "stream-json", "--output-format", "stream-json",
    "--include-partial-messages", "--permission-mode", Claude.permission(r, i),
    "--append-system-prompt", prompt],
    Claude.ask(r, i,
    Claude.opt("--model", model, Claude.opt("--resume", session, Claude.dirs(dirs)))))
