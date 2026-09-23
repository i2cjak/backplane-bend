import Base
import ./json.bend as J
import ./prompt.bend as Q

# Agent features, pure: user and project skills (SKILL.md frontmatter, the
# skills block Codex and Grok are told, `$skill` mentions), reasoning
# effort per provider, and the one-shot prompts that name a worktree's
# branch and write commit messages. The server does the IO around these.

# User and project skills
# -----------------------
# `~/.claude/skills/*/SKILL.md` (user scope) and
# `<cwd>/.claude/skills/*/SKILL.md` (project scope). `model`: the model may
# invoke it on its own (not disable-model-invocation); `user`: the user may
# invoke it with `$name` (user-invocable, the default).

type USkill is Data:
  USkill{name: String, description: String, path: String, model: Bool, user: Bool}

type UFront is Data:
  UFront{name: String, description: String, dmi: String, ui: String}

def UFront.step(f: UFront, +line: String) -> UFront:
  match f:
    case UFront{n, d, m, u}:
      UFront{Maybe.default(&2, String, Q.Skill.field(line, "name"), n), Maybe.default(&2, String, Q.Skill.field(line, "description"), d),
        Maybe.default(&2, String, Q.Skill.field(line, "disable-model-invocation"), m), Maybe.default(&2, String, Q.Skill.field(line, "user-invocable"), u)}

# fold frontmatter lines until the closing ---; `stop` is the head's verdict
def UFront.go(ls: List<&2, String>, stop: Bool, f: UFront) -> UFront:
  match ls stop:
    case +l <> +t False{}:
      UFront.go(t, Q.Front.stop(t), UFront.step(f, l))
    case _ _:
      f

def UFront.open(open: Bool, +t: List<&2, String>, +dflt: String) -> UFront:
  match open:
    case True{}:
      UFront.go(t, Q.Front.stop(t), UFront{dflt, "", "", ""})
    case False{}:
      UFront{dflt, "", "", ""}

def UFront.of(ls: List<&2, String>, +dflt: String) -> UFront:
  match ls:
    case +l <> t:
      UFront.open(String.eq(String.trim(l), "---"), t, dflt)
    case Nil{}:
      UFront{dflt, "", "", ""}

# a YAML boolean, or d when it is neither
def USkill.flag(+v: String, d: Bool) -> Bool:
  Bool.pick(Bool, String.eq(String.to_lower(v), "true"), True{}, Bool.pick(Bool, String.eq(String.to_lower(v), "false"), False{}, d))

def USkill.parse.k(f: UFront, path: String) -> USkill:
  match f:
    case UFront{n, d, +m, +u}:
      USkill{n, d, path, Bool.not(USkill.flag(m, False{})), USkill.flag(u, True{})}

# a SKILL.md: its frontmatter, the directory name when it names nothing
def USkill.parse(text: String, +dflt: String, path: String) -> USkill:
  USkill.parse.k(UFront.of(String.lines(text), dflt), path)

def USkill.name(s: USkill) -> String:
  match s:
    case USkill{n, _, _, _, _}:
      n

def USkill.has(ss: List<&2, USkill>, +n: String) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case USkill{m, _, _, _, _} <> t:
      Bool.or(String.eq(m, n), USkill.has(t, n))

def USkill.unseen.k(seen: Bool, s: USkill, rest: List<&2, USkill>) -> List<&2, USkill>:
  match seen:
    case True{}:
      rest
    case False{}:
      s <> rest

def USkill.unseen(ps: List<&2, USkill>, +us: List<&2, USkill>) -> List<&2, USkill>:
  match ps:
    case Nil{}:
      Nil{}
    case USkill{+n, d, p, m, u} <> t:
      USkill.unseen.k(USkill.has(us, n), USkill{n, d, p, m, u}, USkill.unseen(t, us))

# user skills, then the project's; the user's wins a name both use
def USkill.merge(+us: List<&2, USkill>, ps: List<&2, USkill>) -> List<&2, USkill>:
  List.append(&2, USkill, us, USkill.unseen(ps, us))

def USkill.line.k(keep: Bool, +n: String, +d: String, +p: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      ("- " ++ n ++ ": " ++ d ++ " Read \"" ++ p ++ "\"") <> rest
    case False{}:
      rest

def USkill.lines(ss: List<&2, USkill>) -> List<&2, String>:
  match ss:
    case Nil{}:
      Nil{}
    case USkill{+n, +d, +p, m, _} <> t:
      USkill.line.k(m, n, d, p, USkill.lines(t))

def USkill.block(+ls: List<&2, String>) -> String:
  Bool.pick(String, List.is_empty(&2, String, ls), "",
    "\n\n<skills>\nThe user installed these skills (Claude Code SKILL.md format). When a task matches a skill's description, read that skill's complete SKILL.md before starting and follow it. Resolve paths it mentions relative to its directory.\n"
    ++ String.join(ls, "\n") ++ "\n</skills>")

# the skills block for providers that do not read skills themselves
# (Codex, Grok): the skills the model may invoke, with their paths; "" for
# none
def USkill.prompt(ss: List<&2, USkill>) -> String:
  USkill.block(USkill.lines(ss))

def USkill.user_only.k(keep: Bool, s: USkill, rest: List<&2, USkill>) -> List<&2, USkill>:
  match keep:
    case True{}:
      s <> rest
    case False{}:
      rest

# the skills a user may name with `$`
def USkill.user_only(ss: List<&2, USkill>) -> List<&2, USkill>:
  match ss:
    case Nil{}:
      Nil{}
    case USkill{n, d, p, m, +u} <> t:
      USkill.user_only.k(u, USkill{n, d, p, m, u}, USkill.user_only(t))

def USkill.json.go(ss: List<&2, USkill>) -> List<&2, J.Json>:
  match ss:
    case Nil{}:
      Nil{}
    case USkill{n, d, _, _, _} <> t:
      J.Json.obj([J.KV{"name", J.Str{n}}, J.KV{"description", J.Str{d}}]) <> USkill.json.go(t)

# what the composer offers after `$`: name and description of each skill
# the user may invoke
def USkill.json(ss: List<&2, USkill>) -> J.Json:
  J.Json.arr(USkill.json.go(USkill.user_only(ss)))

# `$skill` mentions
# ----------------

# a character of a skill name: letters, digits, - _ :
def Mention.namec(+c: U32) -> Bool:
  Bool.or(Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90))),
    Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), Bool.or(Bool.or(U32.is_eq(c, 45), U32.is_eq(c, 95)), U32.is_eq(c, 58))))

def Mention.stop(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, _}:
      Bool.not(Mention.namec(c))

def Mention.take.go(s: String, stop: Bool, acc: String) -> String:
  match s stop:
    case _ True{}:
      String.reverse(acc)
    case SNil{} False{}:
      String.reverse(acc)
    case SCon{c, +t} False{}:
      Mention.take.go(t, Mention.stop(t), SCon{c, acc})

# the skill a word names: "$pcb-review," -> "pcb-review"; "" for a word
# that is no mention
def Mention.name(+w: String) -> String:
  Bool.pick(String, String.starts_with(w, "$"), Mention.take.go(String.drop(w, 1n), Mention.stop(String.drop(w, 1n)), ""), "")

def Mention.find(ss: List<&2, USkill>, +n: String) -> Maybe<&2, USkill>:
  match ss:
    case Nil{}:
      None{}
    case USkill{+m, d, p, mo, +u} <> t:
      Bool.pick(Maybe<&2, USkill>, Bool.and(u, String.eq(m, n)), Some{USkill{m, d, p, mo, u}}, Mention.find(t, n))

def Mention.slash.k(m: Maybe<&2, USkill>, +w: String) -> String:
  match m:
    case Some{_}:
      "/" ++ String.drop(w, 1n)
    case None{}:
      w

# for Claude: `$name` of a known skill becomes `/name`, Claude Code's own
# skill invocation; any other `$word` stays
def Mention.slash(+ss: List<&2, USkill>, +w: String) -> String:
  Bool.pick(String, String.is_empty(Mention.name(w)), w, Mention.slash.k(Mention.find(ss, Mention.name(w)), w))

def Mention.words(ws: List<&2, String>, +ss: List<&2, USkill>) -> List<&2, String>:
  match ws:
    case Nil{}:
      Nil{}
    case +w <> t:
      Mention.slash(ss, w) <> Mention.words(t, ss)

def Mention.lines(ls: List<&2, String>, +ss: List<&2, USkill>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      String.join(Mention.words(String.split(l, ' '), ss), " ") <> Mention.lines(t, ss)

def Mention.claude(+text: String, +ss: List<&2, USkill>) -> String:
  String.join(Mention.lines(String.lines(text), ss), "\n")

def Mention.note(s: USkill) -> String:
  match s:
    case USkill{n, _, p, _, _}:
      "The user invoked the $" ++ n ++ " skill: read \"" ++ p ++ "\" completely before anything else and follow its instructions for this request."

def Mention.seen(xs: List<&2, String>, +n: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case x <> t:
      Bool.or(String.eq(x, n), Mention.seen(t, n))

def Mention.seen.add(m: Maybe<&2, USkill>, +n: String, +seen: List<&2, String>) -> List<&2, String>:
  match m:
    case Some{_}:
      n <> seen
    case None{}:
      seen

def Mention.notes.one(m: Maybe<&2, USkill>, +n: String, +seen: List<&2, String>, +rest: List<&2, String>) -> List<&2, String>:
  match m:
    case Some{s}:
      Bool.pick(List<&2, String>, Mention.seen(seen, n), rest, Mention.note(s) <> rest)
    case None{}:
      rest

# the note for each skill the words name, once each, in order
def Mention.notes(ws: List<&2, String>, +ss: List<&2, USkill>, +seen: List<&2, String>) -> List<&2, String>:
  match ws:
    case Nil{}:
      Nil{}
    case +w <> t:
      Mention.notes.one(Mention.find(ss, Mention.name(w)), Mention.name(w), seen, Mention.notes(t, ss, Mention.seen.add(Mention.find(ss, Mention.name(w)), Mention.name(w), seen)))

def Mention.all_words(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      List.append(&2, String, String.split(l, ' '), Mention.all_words(t))

def Mention.others.k(+notes: List<&2, String>, +text: String) -> String:
  Bool.pick(String, List.is_empty(&2, String, notes), text, "<skill_invocations>\n" ++ String.join(notes, "\n") ++ "\n</skill_invocations>\n\n" ++ text)

# for providers without skills of their own: the text as written, after
# one instruction per named skill to read its SKILL.md
def Mention.others(+text: String, +ss: List<&2, USkill>) -> String:
  Mention.others.k(Mention.notes(Mention.all_words(String.lines(text)), ss, Nil{}), text)

def Mention.expand.k(has: Bool, claude: Bool, +text: String, +ss: List<&2, USkill>) -> String:
  match has claude:
    case False{} _:
      text
    case True{} True{}:
      Mention.claude(text, ss)
    case True{} False{}:
      Mention.others(text, ss)

# a user message with its `$skill` mentions made real for the provider
def Mention.expand(+provider: String, +text: String, +ss: List<&2, USkill>) -> String:
  Mention.expand.k(String.contains(text, "$"), String.eq(provider, "claude"), text, ss)

# Reasoning effort
# ----------------
# Per thread, in the settings map under effort.<thread>; "" is the
# provider's default. Claude: --effort; Codex: model_reasoning_effort;
# Grok: --reasoning-effort.

def Effort.key(+thread: String) -> String:
  "effort." ++ thread

def Effort.levels(+provider: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, Bool.or(String.eq(provider, "claude"), String.eq(provider, "codex")), ["low", "medium", "high", "xhigh"],
    Bool.pick(List<&2, String>, String.eq(provider, "grok"), ["low", "medium", "high"], Nil{}))

def Effort.in(xs: List<&2, String>, +e: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case x <> t:
      Bool.or(String.eq(x, e), Effort.in(t, e))

# the effort a provider takes: e when it offers it, else its default ("")
def Effort.of(+provider: String, +e: String) -> String:
  Bool.pick(String, Effort.in(Effort.levels(provider), e), e, "")

def Effort.args.k(i: Nat, +e: String) -> List<&2, String>:
  match i:
    case 0n:
      ["--effort", e]
    case 1n:
      ["-c", "model_reasoning_effort=\"" ++ e ++ "\""]
    case 2n:
      ["--reasoning-effort", e]
    case _:
      Nil{}

def Effort.pos(xs: List<&2, String>, +x: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      i
    case +h <> t:
      Bool.pick(Nat, String.eq(h, x), i, Effort.pos(t, x, 1n+i))

# the flags that set a provider's effort (none for its default)
def Effort.args(+provider: String, +e: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(Effort.of(provider, e)), Nil{},
    Effort.args.k(Effort.pos(["claude", "codex", "grok"], provider, 0n), Effort.of(provider, e)))

# One-shot writing: branch names and commit messages
# --------------------------------------------------
# `claude -p` with a small model, no tools, no MCP and no session; the
# text goes on stdin. What comes back is one JSON object ({"result": ...}).

def OneShot.args(+system: String) -> List<&2, String>:
  ["60", "claude", "-p", "--model", "haiku", "--output-format", "json", "--no-session-persistence",
   "--tools", "", "--strict-mcp-config", "--effort", "low", "--system-prompt", system]

def OneShot.pick.k(m: Maybe<&2, J.Json>, rest: String) -> String:
  match m:
    case Some{+o}:
      Bool.pick(String, Bool.or(J.Json.get_bool(o, "is_error", False{}), Bool.not(String.eq(J.Json.get_str(o, "type", ""), "result"))), rest, J.Json.get_str(o, "result", ""))
    case None{}:
      rest

def OneShot.pick(ls: List<&2, String>) -> String:
  match ls:
    case Nil{}:
      ""
    case +l <> +t:
      Bool.pick(String, String.starts_with(String.trim(l), "{"), OneShot.pick.k(J.Json.parse(String.trim(l)), OneShot.pick(t)), OneShot.pick(t))

# the model's answer, or "" when it failed
def OneShot.result(+out: String) -> String:
  String.trim(OneShot.pick(String.lines(out)))

def Name.system() -> String:
  "You name git branches. The user's first message to a coding agent follows. Reply with only a short branch name for that work: 2 to 5 lowercase English words joined by hyphens, at most 40 characters, no prefix, no quotes, no punctuation, nothing else."

def Name.hex.k(+c: U32) -> Bool:
  Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), Bool.and(U32.is_ge(c, 97), U32.is_le(c, 102)))

def Name.hex(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(Name.hex.k(c), Name.hex(t))

# a worktree's temporary branch (backplane/<8 hex>), which the agent renames
def Name.temp(+b: String) -> Bool:
  Bool.and(Bool.and(String.starts_with(b, "backplane/"), Nat.is_eq(String.length(b), 18n)), Name.hex(String.drop(b, 10n)))

def Name.strip(+s: String) -> String:
  String.trim(String.join(String.split(String.join(String.split(String.join(String.split(s, '`'), ""), '"'), ""), '\''), ""))

# the model's answer as a branch fragment: its first line, no quotes, words
# joined by hyphens (git.bend sanitizes what is left); "" for none
def Name.fragment(+answer: String) -> String:
  String.take(String.join(String.split(String.to_lower(Name.strip(Maybe.default(&2, String, List.head(&2, String, String.lines(String.trim(answer))), ""))), ' '), "-"), 48n)

# the branch a named thread moves to
def Name.branch(+fragment: String) -> String:
  "backplane/" ++ fragment

def Commit.system() -> String:
  "You write git commit messages. A unified diff follows, after the title of the task that produced it. Reply with only the commit message: a subject line in the imperative mood under 72 characters, then, only if the change needs it, a blank line and a short body wrapped at 72 characters. No quotes, no code fences, no trailers."

# the text the commit writer reads: the task, then the diff (cut short)
def Commit.input(+title: String, +diff: String) -> String:
  "Task: " ++ title ++ "\n\n" ++ String.take(diff, 30000n)

def Commit.fence(+l: String) -> Bool:
  String.starts_with(String.trim(l), "```")

def Commit.unfence(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> +t:
      Bool.pick(List<&2, String>, Commit.fence(l), Commit.unfence(t), l <> Commit.unfence(t))

# the model's answer as a commit message, or fallback when it gave none
def Commit.message(+answer: String, +fallback: String) -> String:
  Bool.pick(String, String.is_empty(String.trim(String.join(Commit.unfence(String.lines(answer)), "\n"))), fallback,
    String.trim(String.join(Commit.unfence(String.lines(answer)), "\n")))
