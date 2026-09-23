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

# the text appended to the provider's own system prompt
def Prompt.runtime(harness: String, +kicad: String, ss: List<&2, Skill>) -> String:
  "<runtime_info>In case you're asked: you are running in Backplane through the " ++ harness
  ++ " harness. No need to mention this otherwise. You can embed images and videos in your response using Markdown with absolute file paths.</runtime_info>\n\n"
  ++ "<kicad_runtime>Use the selected KiCad CLI at `" ++ kicad ++ "` for KiCad work. Check `\"" ++ kicad ++ "\" --version` and subcommand `--help`. Export with `\"" ++ kicad ++ "\" sch export` or `\"" ++ kicad ++ "\" pcb export`; run checks with `\"" ++ kicad ++ "\" sch erc` and `\"" ++ kicad ++ "\" pcb drc`. Use the full path when invoking it, quoting paths for your shell. The Backplane viewer shows the board live: save the canonical .kicad_pcb and it updates.</kicad_runtime>\n\n"
  ++ Prompt.kistack(ss)

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
def Claude.args(+model: String, +session: String, r: M.RuntimeMode, i: M.InteractionMode, prompt: String, +dirs: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, ["-p", "--verbose", "--input-format", "stream-json", "--output-format", "stream-json",
    "--include-partial-messages", "--permission-mode", Claude.permission(r, i),
    "--append-system-prompt", prompt],
    Claude.opt("--model", model, Claude.opt("--resume", session, Claude.dirs(dirs))))
