import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/json.bend as J

def strs(xs: List<&2, String>) -> String:
  String.join(xs, ",")

def info() -> String:
  "{\"claude\":[\"opus\",\"haiku\"],\"about\":{\"claude\":{\"cli\":\"2.1\",\"labels\":{\"opus\":\"Opus 5.5 · claude-opus-5-5\"},\"efforts\":{\"default\":[\"low\",\"high\",\"max\"],\"opus\":[\"low\",\"medium\",\"high\",\"xhigh\",\"max\"],\"haiku\":[]}}}}"

def push(+text: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{})

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("opus chips", strs(U.Effort.chips(info(), "claude", "opus")), ",low,medium,high,xhigh,max")
    C.Check.str("haiku has none", strs(U.Effort.chips(info(), "claude", "haiku")), "")
    C.Check.str("default model", strs(U.Effort.chips(info(), "claude", "")), ",low,high,max")
    C.Check.str("unknown model: provider levels", strs(U.Effort.chips(info(), "claude", "sonnet")), ",low,medium,high,xhigh,max")
    C.Check.str("codex without efforts", strs(U.Effort.chips(info(), "codex", "")), ",low,medium,high,xhigh")
    C.Check.str("label", U.Models.label_of(info(), "claude", "opus"), "Opus 5.5 · claude-opus-5-5")
    C.Check.str("info push replaces models",
      U.Ui.info(U.Ui.recv(U.Ui.recv(U.Ui.init(0n), push("{\"t\":\"log\",\"items\":[],\"info\":{\"models\":\"old\",\"listen\":\"x\"}}")), push("{\"t\":\"info\",\"info\":{\"models\":\"new\"}}")), "models"), "new")
    C.Check.str("info push keeps the rest",
      U.Ui.info(U.Ui.recv(U.Ui.recv(U.Ui.init(0n), push("{\"t\":\"log\",\"items\":[],\"info\":{\"models\":\"old\",\"listen\":\"x\"}}")), push("{\"t\":\"info\",\"info\":{\"models\":\"new\"}}")), "listen"), "x")
