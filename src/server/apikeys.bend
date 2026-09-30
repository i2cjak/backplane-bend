import Base
import ./botnet.bend as BN
import ../core/apikeys.bend as K

# API keys' IO (core/apikeys.bend): one .env file, <home>/secrets/api.env,
# 0600 in a 0700 folder. Only names ever leave this file: a client gets the
# names, an agent the names and the path.

def Ak.path(+home: String) -> String:
  home ++ "/secrets/api.env"

# the names kept, a name a line
def Ak.names(+home: String) -> IO(String):
  IO.bind(String, String, BN.Bf.text(Ak.path(home)), t => IO.pure(String, String.join(K.Keys.names(t), "\n")))

def Ak.write(+home: String, text: String) -> IO(String):
  do IO<String>:
    BN.Bf.dir(home ++ "/secrets")
    ok : Bool <- BN.Bf.secret(Ak.path(home), text)
    return Bool.pick(String, ok, "", "error: the keys file could not be written")

def Ak.add.k(+bad: String, +home: String, +name: String, +value: String) -> IO(String):
  Bool.pick(IO(String), String.is_empty(bad),
    IO.bind(String, String, BN.Bf.text(Ak.path(home)), t => Ak.write(home, K.Keys.set(t, name, value))),
    IO.pure(String, "error: " ++ bad))

# keep a key under its name (an old one of that name replaced); "" when
# kept, else "error: why"
def Ak.add(+home: String, +name: String, +value: String) -> IO(String):
  Ak.add.k(K.Keys.bad(name, value), home, name, value)

# forget the key of that name
def Ak.del(+home: String, +name: String) -> IO(String):
  IO.bind(String, String, BN.Bf.text(Ak.path(home)), t => Ak.write(home, K.Keys.drop(t, name)))

# what an agent is told (core's Keys.prompt: nothing when there are none)
def Ak.prompt(+home: String) -> IO(String):
  IO.bind(String, String, Ak.names(home), ns => IO.pure(String, K.Keys.prompt(Ak.path(home), ns)))
