import Base
import ./utf8.bend as U
import ./sha1.bend as S

# HTTP/1.1 requests and WebSocket (RFC 6455) frames over byte lists. Pure:
# the server feeds bytes in and gets requests, frames, and bytes out.

# Requests
# --------

type Header is Data:
  Header{name: String, value: String}

type Request is Data:
  Request{method: String, path: String, headers: List<&2, Header>}

# a request head (bytes before the blank line) and the bytes after it
type Split is Data:
  Split{head: List<&2, U32>, rest: List<&2, U32>}

# `seen` counts how much of \r\n\r\n the last bytes matched
def Http.split.want(+seen: Nat) -> U32:
  Bool.pick(U32, Nat.is_eq(Nat.mod(seen, 2n), 0n), 13, 10)

def Http.split.k(hit: Bool, +x: U32, +seen: Nat) -> Nat:
  match hit:
    case True{}:
      1n+seen
    case False{}:
      Bool.pick(Nat, U32.is_eq(x, 13), 1n, 0n)

def Http.split.go(bs: List<&2, U32>, seen: Nat, acc: List<&2, U32>) -> Maybe<&2, Split>:
  match bs seen:
    case _ 1n+1n+1n+1n+_:
      Some{Split{List.reverse(&2, U32, acc), bs}}
    case Nil{} _:
      None{}
    case +x <> t +s:
      Http.split.go(t, Http.split.k(U32.is_eq(x, Http.split.want(s)), x, s), x <> acc)

# the head and the rest once the headers are complete, else None
def Http.split(bs: List<&2, U32>) -> Maybe<&2, Split>:
  Http.split.go(bs, 0n, Nil{})

def Http.header.k(parts: List<&2, String>) -> Header:
  match parts:
    case Nil{}:
      Header{"", ""}
    case n <> vs:
      Header{String.to_lower(String.trim(n)), String.trim(String.join(vs, ":"))}

def Http.header(line: String) -> Header:
  Http.header.k(String.split(line, ':'))

def Http.headers(ls: List<&2, String>) -> List<&2, Header>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      Http.header(String.trim_end(l)) <> Http.headers(t)

def Http.request.line(parts: List<&2, String>, hs: List<&2, String>) -> Request:
  match parts:
    case m <> p <> _:
      Request{m, p, Http.headers(hs)}
    case _:
      Request{"", "", Nil{}}

def Http.request.k(ls: List<&2, String>) -> Request:
  match ls:
    case Nil{}:
      Request{"", "", Nil{}}
    case l <> hs:
      Http.request.line(String.split(String.trim_end(l), ' '), hs)

def Http.request(head: List<&2, U32>) -> Request:
  Http.request.k(String.lines(U.Utf8.decode(head)))

def Http.get.hit(hs: List<&2, Header>, +name: String) -> Bool:
  match hs:
    case Header{n, _} <> _:
      String.eq(n, name)
    case Nil{}:
      False{}

def Http.get.go(hs: List<&2, Header>, hit: Bool, +name: String) -> String:
  match hs hit:
    case Header{_, v} <> _ True{}:
      v
    case _ <> +t False{}:
      Http.get.go(t, Http.get.hit(t, name), name)
    case _ _:
      ""

# a header's value by lower-case name, or ""
def Http.header_of(+hs: List<&2, Header>, +name: String) -> String:
  Http.get.go(hs, Http.get.hit(hs, name), name)

def Http.route.k(parts: List<&2, String>) -> String:
  match parts:
    case h <> _:
      h
    case Nil{}:
      "/"

# the path without its query string
def Http.route(p: String) -> String:
  Http.route.k(String.split(p, '?'))

# Responses
# ---------

def Http.response(status: String, ctype: String, body: List<&2, U32>, extra: String) -> List<&2, U32>:
  +body2 = body
  List.append(&2, U32, U.Utf8.encode("HTTP/1.1 " ++ status ++ "\r\nContent-Type: " ++ ctype
    ++ "\r\nContent-Length: " ++ Nat.show(List.length(&2, U32, body2))
    ++ "\r\nCache-Control: no-cache\r\nConnection: close\r\n" ++ extra ++ "\r\n"), body2)

def Http.text(status: String, body: String) -> List<&2, U32>:
  Http.response(status, "text/plain; charset=utf-8", U.Utf8.encode(body), "")

def Http.ctype.k(html: Bool, js: Bool, css: Bool, svg: Bool, json: Bool) -> String:
  match html js css svg json:
    case True{} _ _ _ _:
      "text/html; charset=utf-8"
    case _ True{} _ _ _:
      "text/javascript; charset=utf-8"
    case _ _ True{} _ _:
      "text/css; charset=utf-8"
    case _ _ _ True{} _:
      "image/svg+xml"
    case _ _ _ _ True{}:
      "application/json"
    case _ _ _ _ _:
      "application/octet-stream"

# the Content-Type for a path's extension
def Http.ctype(+p: String) -> String:
  Http.ctype.k(String.ends_with(p, ".html"), String.ends_with(p, ".js"),
    String.ends_with(p, ".css"), String.ends_with(p, ".svg"), String.ends_with(p, ".json"))

# the 101 response that accepts a WebSocket upgrade for this key
def Ws.accept(key: String) -> List<&2, U32>:
  U.Utf8.encode("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: "
    ++ S.B64.encode(S.Sha1.hash(U.Utf8.encode(key ++ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))) ++ "\r\n\r\n")

# WebSocket frames
# ----------------

type Frame is Data:
  Frame{fin: Bool, op: U32, payload: List<&2, U32>}

# a decoded frame and the bytes after it, or None until enough bytes arrived
type Got is Data:
  Got{frame: Frame, rest: List<&2, U32>}

def Ws.unmask.k(+x: U32, +key: List<&2, U32>, +i: Nat) -> U32:
  U32.xor(x, Maybe.default(&2, U32, List.get(&2, U32, key, Nat.mod(i, 4n)), 0))

def Ws.unmask(bs: List<&2, U32>, +key: List<&2, U32>, +i: Nat) -> List<&2, U32>:
  match bs:
    case Nil{}:
      Nil{}
    case x <> t:
      Ws.unmask.k(x, key, i) <> Ws.unmask(t, key, 1n+i)

def Ws.be(bs: List<&2, U32>, acc: Nat) -> Nat:
  match bs:
    case Nil{}:
      acc
    case x <> t:
      Ws.be(t, Nat.add(Nat.mul(acc, 256n), U32.to_nat(x)))

def Ws.body.fit(ok: Bool, fin: Bool, +op: U32, +key: List<&2, U32>, +len: Nat, +bs: List<&2, U32>) -> Maybe<&2, Got>:
  match ok:
    case True{}:
      Some{Got{Frame{fin, op, Ws.unmask(List.take(&2, U32, bs, len), key, 0n)}, List.drop(&2, U32, bs, len)}}
    case False{}:
      None{}

# after the length: the mask key (when masked) and the payload
def Ws.body(fin: Bool, +op: U32, masked: Bool, +len: Nat, +bs: List<&2, U32>) -> Maybe<&2, Got>:
  match masked:
    case True{}:
      Ws.body.fit(Nat.is_ge(List.length(&2, U32, bs), Nat.add(4n, len)), fin, op, List.take(&2, U32, bs, 4n), len, List.drop(&2, U32, bs, 4n))
    case False{}:
      Ws.body.fit(Nat.is_ge(List.length(&2, U32, bs), len), fin, op, [0, 0, 0, 0], len, bs)

def Ws.len.k(short: Bool, mid: Bool, fin: Bool, +op: U32, masked: Bool, +n: U32, +bs: List<&2, U32>) -> Maybe<&2, Got>:
  match short mid:
    case True{} _:
      Ws.body(fin, op, masked, U32.to_nat(n), bs)
    case False{} True{}:
      Ws.body(fin, op, masked, Ws.be(List.take(&2, U32, bs, 2n), 0n), List.drop(&2, U32, bs, 2n))
    case False{} False{}:
      Ws.body(fin, op, masked, Ws.be(List.take(&2, U32, bs, 8n), 0n), List.drop(&2, U32, bs, 8n))

# one frame from the front of a byte stream, or None when incomplete
def Ws.decode(bs: List<&2, U32>) -> Maybe<&2, Got>:
  match bs:
    case +b0 <> +b1 <> rest:
      Ws.len.k(U32.is_lt(U32.and(b1, 127), 126), U32.is_eq(U32.and(b1, 127), 126),
        U32.is_ne(U32.and(b0, 128), 0), U32.and(b0, 15), U32.is_ne(U32.and(b1, 128), 0),
        U32.and(b1, 127), rest)
    case _:
      None{}

def Ws.len_bytes.k(short: Bool, mid: Bool, +n: Nat) -> List<&2, U32>:
  match short mid:
    case True{} _:
      [U32.from_nat(n)]
    case False{} True{}:
      [126, U32.from_nat(Nat.div(n, 256n)), U32.from_nat(Nat.mod(n, 256n))]
    case False{} False{}:
      [127, 0, 0, 0, 0,
        U32.from_nat(Nat.mod(Nat.div(n, 16777216n), 256n)),
        U32.from_nat(Nat.mod(Nat.div(n, 65536n), 256n)),
        U32.from_nat(Nat.mod(Nat.div(n, 256n), 256n)),
        U32.from_nat(Nat.mod(n, 256n))]

# an unmasked, final server frame
def Ws.encode(+op: U32, payload: List<&2, U32>) -> List<&2, U32>:
  +p = payload
  +n = List.length(&2, U32, p)
  U32.or(128, op) <> List.append(&2, U32, Ws.len_bytes.k(Nat.is_lt(n, 126n), Nat.is_lt(n, 65536n), n), p)

def Ws.text(s: String) -> List<&2, U32>:
  Ws.encode(1, U.Utf8.encode(s))
