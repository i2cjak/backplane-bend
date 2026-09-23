import Base
import ./host.bend as H
import ./proc.bend as P
import ../core/json.bend as J
import ../core/utf8.bend as U

# KiCad on this machine: which kicad-cli to use (the Backplane KiCad fork,
# with IPC, when present), a project's canonical files, and the KiStack
# skills. The agents' instructions are built from these, so every session
# is told the same exact paths.

# the CLI, whether it is the Backplane fork, its version and source commit
type Rt is Data:
  Rt{cli: String, fork: Bool, version: String, commit: String}

# a project's canonical design files ("" when it has none)
type Files is Data:
  Files{pro: String, pcb: String, sch: String}

def KiCad.version() -> String:
  "10.0.6"

def KiCad.release() -> String:
  "backplane-kicad-v10.0.6-2"

def KiStack.revision() -> String:
  "ecf16c119c7ed610f5f251c479b03884b8d98b09"

def Io.text.done(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(String):
  (f, res) = r
  do IO<String>:
    File.close(f)
    return U.Utf8.decode(Result.default(&1, &1, U32 & String, List<&2, U32>, res, Nil{}))

def Io.text.sized(r: File & Result<&1, &1, U32 & String, U32>) -> IO(String):
  (f, res) = r
  IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, String,
    File.read_bytes(f, U32.max(Result.default(&1, &1, U32 & String, U32, res, 0), 1)), Io.text.done)

def Io.text.opened(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, String, File.size(f), Io.text.sized)
    case Fail{_}:
      IO.pure(String, "")

# Files
# -----

def Io.text(path: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, File>, String, File.open(path, "r"), Io.text.opened)

def Io.is_file.kind(v: U32 & U32 & U32) -> Bool:
  (k, _) = v
  U32.is_eq(k, 0)

def Io.is_file.k(r: Result<&1, &1, U32 & String, U32 & U32 & U32>) -> Bool:
  match r:
    case Done{v}:
      Io.is_file.kind(v)
    case Fail{_}:
      False{}

def Io.is_file(path: String) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, U32 & U32 & U32> <- H.FS.stat(path)
    return Io.is_file.k(r)

def Io.names.copy(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> Io.names.copy(t)

def Io.names.k(r: Result<&1, &1, U32 & String, List<String>>) -> List<&2, String>:
  match r:
    case Done{xs}:
      Io.names.copy(xs)
    case Fail{_}:
      Nil{}

def Io.names(path: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    r : Result<&1, &1, U32 & String, List<String>> <- H.FS.list(path)
    return List.sort(~String, ~String.is_le, Io.names.k(r))

def Rt.manifest.k(m: Maybe<&2, J.Json>, +cli: String) -> Rt:
  match m:
    case Some{+o}:
      Rt{cli, String.contains(J.Json.get_str(o, "sourceRepository", ""), "Backplane_KiCad"), J.Json.get_str(o, "version", ""), J.Json.get_str(o, "sourceCommit", "")}
    case None{}:
      Rt{cli, False{}, "", ""}

# Runtime
# -------

def Rt.manifest(+cli: String, +text: String) -> Rt:
  Rt.manifest.k(J.Json.parse(text), cli)

# <root>/bin/kicad-cli -> <root>
def Rt.root(+cli: String) -> String:
  String.take(cli, Nat.sub(String.length(cli), String.length("/bin/kicad-cli")))

# which of the paths exist, in order
def Io.flags(cs: List<&2, String>) -> IO(List<&2, Bool>):
  match cs:
    case Nil{}:
      IO.pure(List<&2, Bool>, Nil{})
    case c <> t:
      IO.bind(Bool, List<&2, Bool>, Io.is_file(c), ok => IO.bind(List<&2, Bool>, List<&2, Bool>, Io.flags(t), fs => IO.pure(List<&2, Bool>, ok <> fs)))

def Rt.found(cs: List<&2, String>, fs: List<&2, Bool>) -> String:
  match cs fs:
    case c <> _ True{} <> _:
      c
    case _ <> t False{} <> g:
      Rt.found(t, g)
    case _ _:
      ""

def Rt.read(+cli: String) -> IO(Rt):
  IO.bind(String, Rt, Io.text(Rt.root(cli) ++ "/manifest.json"), text => IO.pure(Rt, Rt.manifest(cli, text)))

def Rt.first.k(+cli: String) -> IO(Rt):
  Bool.pick(IO(Rt), String.is_empty(cli), IO.pure(Rt, Rt{"kicad-cli", False{}, "", ""}), Rt.read(cli))

# the first candidate that exists, with its runtime's manifest read
def Rt.first(+cs: List<&2, String>) -> IO(Rt):
  IO.bind(List<&2, Bool>, Rt, Io.flags(cs), fs => Rt.first.k(Rt.found(cs, fs)))

def Rt.resolve.k(none: Bool, +explicit: String, +exe: String, +data: String) -> IO(Rt):
  match none:
    case True{}:
      Rt.first([exe ++ "/kicad/bin/kicad-cli", data ++ "/kicad/" ++ KiCad.version() ++ "/bin/kicad-cli", "/usr/bin/kicad-cli", "/usr/local/bin/kicad-cli"])
    case False{}:
      Rt.read(explicit)

# an explicit BACKPLANE_KICAD_CLI, then a fork beside this install or in our
# data directory, then the system's kicad-cli
def Rt.resolve(+explicit: String, +exe: String, +data: String) -> IO(Rt):
  Rt.resolve.k(String.is_empty(explicit), explicit, exe, data)

# Project files
# -------------

def Files.pick.hit(ns: List<&2, String>, +ext: String) -> Bool:
  match ns:
    case n <> _:
      String.ends_with(n, ext)
    case Nil{}:
      False{}

def Files.pick.go(ns: List<&2, String>, hit: Bool, +ext: String) -> String:
  match ns hit:
    case n <> _ True{}:
      n
    case _ <> +t False{}:
      Files.pick.go(t, Files.pick.hit(t, ext), ext)
    case Nil{} _:
      ""

# the first name with the extension ("" when none)
def Files.pick(+ns: List<&2, String>, +ext: String) -> String:
  Files.pick.go(ns, Files.pick.hit(ns, ext), ext)

def Files.stem(+name: String, +ext: String) -> String:
  String.take(name, Nat.sub(String.length(name), String.length(ext)))

def Files.abs(+root: String, +rel: String) -> String:
  Bool.pick(String, String.is_empty(rel), "", Bool.pick(String, String.starts_with(rel, "/"), rel, root ++ "/" ++ rel))

def Files.named.k(found: Bool, +exact: String, +first: String) -> String:
  Bool.pick(String, found, exact, first)

def Files.in(ns: List<&2, String>, +want: String) -> Bool:
  match ns:
    case Nil{}:
      False{}
    case n <> t:
      Bool.or(String.eq(n, want), Files.in(t, want))

# prefer the file named like the project, else the first of its kind
def Files.named(+ns: List<&2, String>, +stem: String, +ext: String) -> String:
  Files.named.k(Files.in(ns, stem ++ ext), stem ++ ext, Files.pick(ns, ext))

# .backplane.json may name "pcb" and "schematic" (project-relative); the
# rest is found from the .kicad_pro in the project root
def Files.of(+root: String, +ns: List<&2, String>, +cfg: J.Json) -> Files:
  +pro = Files.pick(ns, ".kicad_pro")
  +stem = Files.stem(pro, ".kicad_pro")
  Files{Files.abs(root, pro),
    Files.abs(root, Bool.pick(String, String.is_empty(J.Json.get_str(cfg, "pcb", "")), Files.named(ns, stem, ".kicad_pcb"), J.Json.get_str(cfg, "pcb", ""))),
    Files.abs(root, Bool.pick(String, String.is_empty(J.Json.get_str(cfg, "schematic", "")), Files.named(ns, stem, ".kicad_sch"), J.Json.get_str(cfg, "schematic", "")))}

def Files.read(+root: String) -> IO(Files):
  do IO<Files>:
    +ns : List<&2, String> <- Io.names(root)
    text : String <- Io.text(root ++ "/.backplane.json")
    return Files.of(root, ns, Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}))

def KiStack.ensure.k(have: Bool, +dir: String) -> IO(Unit):
  match have:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(dir)
        r : P.Ran <- P.Proc.run("sh", ["-c", "curl -fsSL --max-time 120 \"$1\" | tar -xz -C \"$2\" --strip-components=1", "sh",
          "https://codeload.github.com/American-Embedded/KiStack/tar.gz/" ++ KiStack.revision(), dir], "/")
        return Unit{}

# KiStack
# -------

# the skills live in <cache>/backplane/kistack/<revision>/skills (shared with
# the TypeScript Backplane); fetch the pinned revision when it is missing
def KiStack.ensure(+home: String) -> IO(Unit):
  do IO<Unit>:
    +dir : String = home ++ "/.cache/backplane/kistack/" ++ KiStack.revision()
    have : Bool <- Io.is_file(dir ++ "/skills/pcb/SKILL.md")
    KiStack.ensure.k(have, dir)

def KiCad.install.k(r: P.Ran) -> String:
  match r:
    case P.Ran{0, _}:
      ""
    case P.Ran{_, out}:
      "KiCad install failed: " ++ String.trim(out)

# The fork, installed on request
# ------------------------------

# download Backplane KiCad for linux-x86_64, check it against the release's
# SHA256SUMS, unpack into <data>/kicad/<version>; answers "" or an error
def KiCad.install(+data: String) -> IO(String):
  do IO<String>:
    +dir : String = data ++ "/kicad/" ++ KiCad.version()
    +name : String = "backplane-kicad-linux-x86_64-" ++ KiCad.version() ++ ".tar.gz"
    +base : String = "https://github.com/i2cjak/Backplane_KiCad/releases/download/" ++ KiCad.release() ++ "/"
    mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(dir)
    r : P.Ran <- P.Proc.run("sh", ["-c",
      "set -e; cd \"$1\"; curl -fsSL -o pkg.tgz \"$2$3\"; curl -fsSL -o SUMS \"$2SHA256SUMS\"; want=$(grep \" $3\" SUMS | cut -d' ' -f1); got=$(sha256sum pkg.tgz | cut -d' ' -f1); [ \"$want\" = \"$got\" ] || { echo checksum mismatch; exit 1; }; tar -xzf pkg.tgz --strip-components=1; rm pkg.tgz SUMS",
      "sh", dir, base, name], "/")
    return KiCad.install.k(r)
