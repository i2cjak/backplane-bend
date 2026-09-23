import Base

# "ok name" when got equals want, else "FAIL name: got .. want .."
def Check.pick(same: Bool, name: String, got: String, want: String) -> String:
  match same:
    case True{}:
      "ok " ++ name
    case False{}:
      "FAIL " ++ name ++ ": got " ++ got ++ " want " ++ want

def Check.str(name: String, +got: String, +want: String) -> IO(Unit):
  IO.print(Check.pick(String.eq(got, want), name, got, want))
