import Base
import ./check.bend as C
import ../src/core/agent.bend as A
import ../src/core/json.bend as J

# Skills (SKILL.md frontmatter, scopes, the prompt block), `$skill`
# mentions per provider, reasoning effort flags, and the one-shot answers.

def sk(+n: String, +m: Bool, +u: Bool) -> A.USkill:
  A.USkill{n, "does " ++ n, "/s/" ++ n ++ "/SKILL.md", m, u}

def names(ss: List<&2, A.USkill>) -> List<&2, String>:
  match ss:
    case Nil{}:
      Nil{}
    case s <> t:
      A.USkill.name(s) <> names(t)

def show(s: A.USkill) -> String:
  match s:
    case A.USkill{n, d, p, m, u}:
      n ++ "|" ++ d ++ "|" ++ p ++ "|" ++ Bool.pick(String, m, "model", "-") ++ "|" ++ Bool.pick(String, u, "user", "-")

def yes(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def main() -> IO(Unit):
  +full = A.USkill.parse("---\nname: pcb-review\ndescription: \"Review a board\"\ndisable-model-invocation: true\nuser-invocable: false\n---\nbody", "dir", "/p/SKILL.md")
  +bare = A.USkill.parse("no frontmatter", "dir", "/p/SKILL.md")
  +us = {[sk("a", True{}, True{}), sk("b", True{}, True{})] : List<&2, A.USkill>}
  +ps = {[A.USkill{"b", "project b", "/proj/b", True{}, True{}}, sk("c", False{}, True{}), sk("hidden", True{}, False{})] : List<&2, A.USkill>}
  +all = A.USkill.merge(us, ps)
  +codex = A.Mention.expand("codex", "$a then $c and $a, $nope $hidden", all)
  do IO<Unit>:
    C.Check.str("skill frontmatter", show(full), "pcb-review|Review a board|/p/SKILL.md|-|-")
    C.Check.str("skill defaults", show(bare), "dir||/p/SKILL.md|model|user")
    C.Check.str("user scope wins", String.join(names(all), ","), "a,b,c,hidden")
    C.Check.str("user b kept", yes(String.contains(A.USkill.prompt(all), "does b")), "yes")
    C.Check.str("prompt lists model skills", yes(String.contains(A.USkill.prompt(all), "- a: does a Read \"/s/a/SKILL.md\"")), "yes")
    C.Check.str("prompt skips disabled", yes(String.contains(A.USkill.prompt(all), "- c:")), "no")
    C.Check.str("prompt empty", A.USkill.prompt(Nil{}), "")
    C.Check.str("json offers user skills", J.Json.show(A.USkill.json([sk("a", True{}, True{}), sk("h", True{}, False{})])), "[{\"name\":\"a\",\"description\":\"does a\"}]")
    C.Check.str("mention claude", A.Mention.expand("claude", "$a fix R3\nthen $c, not $HOME or $hidden", all), "/a fix R3\nthen /c, not $HOME or $hidden")
    C.Check.str("mention none", A.Mention.expand("codex", "no skills here", all), "no skills here")
    C.Check.str("mention codex notes", codex,
      "<skill_invocations>\nThe user invoked the $a skill: read \"/s/a/SKILL.md\" completely before anything else and follow its instructions for this request.\nThe user invoked the $c skill: read \"/s/c/SKILL.md\" completely before anything else and follow its instructions for this request.\n</skill_invocations>\n\n$a then $c and $a, $nope $hidden")
    C.Check.str("effort claude", String.join(A.Effort.args("claude", "xhigh"), " "), "--effort xhigh")
    C.Check.str("effort codex", String.join(A.Effort.args("codex", "low"), " "), "-c model_reasoning_effort=\"low\"")
    C.Check.str("effort grok", String.join(A.Effort.args("grok", "high"), " "), "--reasoning-effort high")
    C.Check.str("effort grok no xhigh", String.join(A.Effort.args("grok", "xhigh"), " "), "")
    C.Check.str("effort default", String.join(A.Effort.args("claude", ""), " "), "")
    C.Check.str("effort bogus", String.join(A.Effort.args("codex", "max; rm"), " "), "")
    C.Check.str("temp branch", yes(A.Name.temp("backplane/0a1b2c3d")), "yes")
    C.Check.str("named branch", yes(A.Name.temp("backplane/fix-the-thing")), "no")
    C.Check.str("oneshot result", A.OneShot.result("warning: x\n{\"type\":\"result\",\"is_error\":false,\"result\":\"  Add effort chips \"}\n"), "Add effort chips")
    C.Check.str("oneshot error", A.OneShot.result("{\"type\":\"result\",\"is_error\":true,\"result\":\"Not logged in\"}"), "")
    C.Check.str("oneshot garbage", A.OneShot.result("command not found"), "")
    C.Check.str("name fragment", A.Name.fragment("\"Add Effort Chips\"\nmore"), "add-effort-chips")
    C.Check.str("commit fences", A.Commit.message("```\nAdd effort chips\n\nPass --effort.\n```", "title"), "Add effort chips\n\nPass --effort.")
    C.Check.str("commit fallback", A.Commit.message("  ", "title"), "title")
