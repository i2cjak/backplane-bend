import Base
import ../../src/core/hub.bend as B
import ../../src/core/model.bend as M
import ../../src/core/json.bend as J
import ../../src/core/utf8.bend as U

def count(s: B.Step) -> String:
  match s:
    case B.Step{cs, os}:
      Nat.show(List.length(&2, M.Change, cs)) ++ " changes, " ++ Nat.show(List.length(&2, B.Out, os)) ++ " outs"

def run(ls: List<&2, String>) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.print("done")
    case +l <> t:
      do IO<Unit>:
        IO.print(Nat.show(String.length(l)) ++ " -> " ++ count(B.Hub.agent_line(M.State.empty(), 1n, "t1", l)))
        run(t)

def lines(r: U.Lines & List<&2, String>) -> List<&2, String>:
  (_, ls) = r
  ls

def go(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (f, res) = r
  do IO<Unit>:
    File.close(f)
    bs : List<&2, U32> <- IO.pass(List<&2, U32>, res)
    run(lines(U.Lines.feed(U.Lines.new(), bs)))

def main() -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open("/tmp/bendref/claude-sample.jsonl", "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 10000000)
    go(r)
