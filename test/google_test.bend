import Base
import ./check.bend as C
import ../src/core/google.bend as G
import ../src/core/json.bend as J
import ../src/core/utf8.bend as U

# Gmail and Calendar for bots, the pure half: URL and base64 codecs, OAuth
# pastes and token answers, the messages we send, and the summaries an
# agent reads (sample answers shaped as Google's APIs answer).

def show.bytes(bs: List<&2, U32>) -> String:
  match bs:
    case Nil{}:
      ""
    case b <> t:
      U32.show(b) ++ "," ++ show.bytes(t)

def show.bool(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def show.code(m: Maybe<&2, G.CodeState>) -> String:
  match m:
    case Some{G.CodeState{c, s, b}}:
      c ++ "|" ++ s ++ "|" ++ show.bool(b)
    case None{}:
      "none"

def show.tok(m: Maybe<&2, G.Tok>) -> String:
  match m:
    case Some{G.Tok{a, e, r, m}}:
      a ++ "|" ++ Nat.show(e) ++ "|" ++ r ++ "|" ++ m
    case None{}:
      "none"

def json(s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def sample.full() -> String:
  "{\"id\": \"18c1\", \"threadId\": \"18c0\", \"labelIds\": [\"INBOX\", \"UNREAD\"], \"snippet\": \"Hello Bob, The board is ready. Caf&eacute; at 3?\", \"payload\": {\"partId\": \"\", \"mimeType\": \"multipart/mixed\", \"filename\": \"\", \"headers\": [{\"name\": \"From\", \"value\": \"Alice <alice@example.com>\"}, {\"name\": \"To\", \"value\": \"bob@example.com\"}, {\"name\": \"Subject\", \"value\": \"Board review\"}, {\"name\": \"Date\", \"value\": \"Mon, 21 Sep 2026 10:00:00 -0700\"}], \"body\": {\"size\": 0}, \"parts\": [{\"partId\": \"0\", \"mimeType\": \"multipart/alternative\", \"filename\": \"\", \"headers\": [], \"body\": {\"size\": 0}, \"parts\": [{\"partId\": \"0.0\", \"mimeType\": \"text/plain\", \"filename\": \"\", \"headers\": [{\"name\": \"Content-Type\", \"value\": \"text/plain; charset=\\\"UTF-8\\\"\"}], \"body\": {\"size\": 59, \"data\": \"SGVsbG8gQm9iLA0KDQpUaGUgYm9hcmQgaXMgcmVhZHkuIENhZsOpIGF0IDM_DQoNCi0tIEFsaWNlDQo\"}}, {\"partId\": \"0.1\", \"mimeType\": \"text/html\", \"filename\": \"\", \"headers\": [{\"name\": \"Content-Type\", \"value\": \"text/html; charset=\\\"UTF-8\\\"\"}], \"body\": {\"size\": 139, \"data\": \"PGh0bWw-PGhlYWQ-PHN0eWxlPnB7Y29sb3I6cmVkfTwvc3R5bGU-PC9oZWFkPjxib2R5PjxwPkhpICZhbXA7IHdlbGNvbWU8L3A-PGRpdj5MaW5lIHR3byZuYnNwO2hlcmU8L2Rpdj48YnI-QnllICYjMzk7bm93JiMzOTs8L2JvZHk-PC9odG1sPg\"}}]}, {\"partId\": \"1\", \"mimeType\": \"application/pdf\", \"filename\": \"board.pdf\", \"headers\": [], \"body\": {\"size\": 12345, \"attachmentId\": \"ANGjdJ8\"}}]}}"

def sample.html() -> String:
  "{\"id\": \"18c2\", \"threadId\": \"18c2\", \"labelIds\": [\"INBOX\"], \"snippet\": \"Hi\", \"payload\": {\"mimeType\": \"text/html\", \"filename\": \"\", \"headers\": [{\"name\": \"From\", \"value\": \"Alice <alice@example.com>\"}, {\"name\": \"To\", \"value\": \"bob@example.com\"}, {\"name\": \"Subject\", \"value\": \"Board review\"}, {\"name\": \"Date\", \"value\": \"Mon, 21 Sep 2026 10:00:00 -0700\"}], \"body\": {\"size\": 139, \"data\": \"PGh0bWw-PGhlYWQ-PHN0eWxlPnB7Y29sb3I6cmVkfTwvc3R5bGU-PC9oZWFkPjxib2R5PjxwPkhpICZhbXA7IHdlbGNvbWU8L3A-PGRpdj5MaW5lIHR3byZuYnNwO2hlcmU8L2Rpdj48YnI-QnllICYjMzk7bm93JiMzOTs8L2JvZHk-PC9odG1sPg\"}}}"

def sample.latin() -> String:
  "{\"id\": \"18c3\", \"threadId\": \"18c3\", \"labelIds\": [], \"snippet\": \"\", \"payload\": {\"mimeType\": \"text/plain\", \"filename\": \"\", \"headers\": [{\"name\": \"Content-Type\", \"value\": \"text/plain; charset=ISO-8859-1\"}, {\"name\": \"Subject\", \"value\": \"x\"}], \"body\": {\"size\": 4, \"data\": \"Q2Fm6Q==\"}}}"

def sample.meta() -> String:
  "[{\"id\": \"a1\", \"threadId\": \"a1\", \"labelIds\": [\"INBOX\", \"UNREAD\"], \"snippet\": \"It&#39;s done\", \"payload\": {\"mimeType\": \"multipart/alternative\", \"headers\": [{\"name\": \"From\", \"value\": \"Alice <alice@example.com>\"}, {\"name\": \"Subject\", \"value\": \"Done\"}, {\"name\": \"Date\", \"value\": \"Mon, 21 Sep 2026 10:00:00 -0700\"}]}}, {\"id\": \"a2\", \"threadId\": \"a2\", \"labelIds\": [\"INBOX\"], \"snippet\": \"See attached\", \"payload\": {\"mimeType\": \"multipart/mixed\", \"headers\": [{\"name\": \"from\", \"value\": \"carol@example.com\"}, {\"name\": \"subject\", \"value\": \"Quote\"}, {\"name\": \"date\", \"value\": \"Sun, 20 Sep 2026 08:00:00 +0000\"}]}}]"

def sample.list() -> String:
  "{\"messages\": [{\"id\": \"a1\", \"threadId\": \"a1\"}, {\"id\": \"a2\", \"threadId\": \"a2\"}], \"resultSizeEstimate\": 2}"

def sample.events() -> String:
  "{\"kind\": \"calendar#events\", \"summary\": \"bob@example.com\", \"timeZone\": \"America/Los_Angeles\", \"items\": [{\"id\": \"ev1\", \"status\": \"confirmed\", \"htmlLink\": \"https://www.google.com/calendar/event?eid=ZXYx\", \"summary\": \"Standup\", \"location\": \"Room 4\", \"start\": {\"dateTime\": \"2026-09-24T09:00:00-07:00\", \"timeZone\": \"America/Los_Angeles\"}, \"end\": {\"dateTime\": \"2026-09-24T09:15:00-07:00\"}, \"attendees\": [{\"email\": \"a@example.com\"}, {\"email\": \"b@example.com\"}]}, {\"id\": \"ev2\", \"status\": \"confirmed\", \"start\": {\"date\": \"2026-09-25\"}, \"end\": {\"date\": \"2026-09-26\"}}]}"

def sample.tok() -> String:
  "{\"access_token\": \"ya29.a0AfB\", \"expires_in\": 3599, \"refresh_token\": \"1//0gXyz\", \"scope\": \"openid email\", \"token_type\": \"Bearer\", \"id_token\": \"eyJhbGciOiJSUzI1NiJ9.eyJpc3MiOiAiaHR0cHM6Ly9hY2NvdW50cy5nb29nbGUuY29tIiwgImVtYWlsIjogIm1lQGV4YW1wbGUuY29tIn0.c2ln\"}"

def sample.refresh() -> String:
  "{\"access_token\": \"ya29.new\", \"expires_in\": 3599, \"scope\": \"x\", \"token_type\": \"Bearer\"}"

def main() -> IO(Unit):
  do IO<Unit>:
    # URLs
    C.Check.str("url encode", G.Url.encode("a b/é&=?~"), "a%20b%2F%C3%A9%26%3D%3F~")
    C.Check.str("url decode", G.Url.decode("a%20b%2f%C3%A9+x%zz%4"), "a b/é x%zz%4")
    C.Check.str("url round trip", G.Url.decode(G.Url.encode("Grüße, 日本 ✓ 100%")), "Grüße, 日本 ✓ 100%")
    C.Check.str("auth url", G.Google.auth_url("cid.apps.googleusercontent.com", "http://127.0.0.1:3787/oauth/google", "CHAL", "st8", G.Google.scopes()),
      "https://accounts.google.com/o/oauth2/v2/auth?client_id=cid.apps.googleusercontent.com&redirect_uri=http%3A%2F%2F127.0.0.1%3A3787%2Foauth%2Fgoogle&response_type=code&scope=openid%20email%20https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fgmail.modify%20https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcalendar.events&code_challenge=CHAL&code_challenge_method=S256&state=st8&access_type=offline&prompt=consent")
    # pasted redirects
    C.Check.str("code of url", show.code(G.Google.code_of("http://127.0.0.1:3787/oauth/google?state=st8&code=4%2F0AVG7fi&scope=email%20openid")), "4/0AVG7fi|st8|false")
    C.Check.str("code of query", show.code(G.Google.code_of("  /oauth/google?code=4/0Ab&state=s%20t \n")), "4/0Ab|s t|false")
    C.Check.str("code of fragment", show.code(G.Google.code_of("http://x/cb?state=a&code=c#frag")), "c|a|false")
    C.Check.str("code bare", show.code(G.Google.code_of(" 4/0AVG7fi\n")), "4/0AVG7fi||true")
    C.Check.str("code denied", show.code(G.Google.code_of("http://127.0.0.1:3787/oauth/google?error=access_denied&state=st8")), "none")
    C.Check.str("code error", G.Google.error_of("http://127.0.0.1:3787/oauth/google?error=access_denied&state=st8"), "access_denied")
    C.Check.str("code empty", show.code(G.Google.code_of("  ")), "none")
    C.Check.str("code body", G.Google.code_body("cid", "s/cr+t", "4/0A", "ver_-.~", "http://127.0.0.1:1/oauth/google"),
      "grant_type=authorization_code&code=4%2F0A&client_id=cid&client_secret=s%2Fcr%2Bt&redirect_uri=http%3A%2F%2F127.0.0.1%3A1%2Foauth%2Fgoogle&code_verifier=ver_-.~")
    C.Check.str("refresh body", G.Google.refresh_body("cid", "sec", "1//0g"), "grant_type=refresh_token&refresh_token=1%2F%2F0g&client_id=cid&client_secret=sec")
    # base64
    C.Check.str("b64url encode", G.Gb64.encode_url([251, 255, 0, 104]), "-_8AaA")
    C.Check.str("b64url decode", show.bytes(G.Gb64.decode("-_8AaA")), "251,255,0,104,")
    C.Check.str("b64 decode padded", U.Utf8.decode(G.Gb64.decode("R3LDvMOfZSwg5pel5pysIOKckw==")), "Grüße, 日本 ✓")
    C.Check.str("b64url round trip utf8", U.Utf8.decode(G.Gb64.decode(G.Gb64.encode_url(U.Utf8.encode("Grüße, 日本 ✓")))), "Grüße, 日本 ✓")
    C.Check.str("b64 decode lines", U.Utf8.decode(G.Gb64.decode("aGkN\r\nCnRo\nZXJl")), "hi\r\nthere")
    C.Check.str("b64 empty", show.bytes(G.Gb64.decode("")), "")
    # mail we send
    C.Check.str("mime", G.Google.mime("bob@x.org", "", "Héllo", "hi\nthere"),
      "To: bob@x.org\r\nSubject: =?UTF-8?B?SMOpbGxv?=\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\naGkNCnRoZXJl\r\n")
    C.Check.str("mime no header injection", G.Google.mime("a@x.org\r\nBcc: e@x.org", "c@x.org", "hi\nBcc: f@x.org", ""),
      "To: a@x.org  Bcc: e@x.org\r\nCc: c@x.org\r\nSubject: hi Bcc: f@x.org\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n\r\n")
    C.Check.str("subject folded", G.Mail.subject("Ünïcödé subject that is rather long indeed"),
      "=?UTF-8?B?w5xuw69jw7Zkw6kgc3Vi?=\r\n =?UTF-8?B?amVjdCB0aGF0IGk=?=\r\n =?UTF-8?B?cyByYXRoZXIgbG8=?=\r\n =?UTF-8?B?bmcgaW5kZWVk?=")
    C.Check.str("send body round trip", U.Utf8.decode(G.Gb64.decode(J.Json.get_str(json(G.Google.send_body("bob@x.org", "", "Héllo", "hi\nthere")), "raw", ""))),
      G.Google.mime("bob@x.org", "", "Héllo", "hi\nthere"))
    C.Check.str("split every", String.join(G.Str.split_every("abcdefg", 3n), ","), "abc,def,g")
    # mail we read
    C.Check.str("msg full", G.Google.msg_full(json(sample.full())),
      "id: 18c1\nthread: 18c0\nFrom: Alice <alice@example.com>\nTo: bob@example.com\nDate: Mon, 21 Sep 2026 10:00:00 -0700\nSubject: Board review\nLabels: INBOX, UNREAD\nAttachments: board.pdf (application/pdf, 12345 bytes)\n\nHello Bob,\n\nThe board is ready. Café at 3?\n\n-- Alice\n")
    C.Check.str("msg html only", G.Google.msg_full(json(sample.html())),
      "id: 18c2\nthread: 18c2\nFrom: Alice <alice@example.com>\nTo: bob@example.com\nDate: Mon, 21 Sep 2026 10:00:00 -0700\nSubject: Board review\nLabels: INBOX\n\nHi & welcome\nLine two here\n\nBye 'now'")
    C.Check.str("msg latin1", G.Google.msg_full(json(sample.latin())), "id: 18c3\nthread: 18c3\nSubject: x\n\nCafé")
    C.Check.str("msg list", G.Google.msg_list(J.Json.elems(json(sample.meta()))),
      "2 messages:\n- id a1 [unread]  Mon, 21 Sep 2026 10:00:00 -0700\n  From: Alice <alice@example.com>\n  Subject: Done\n  It's done\n- id a2  Sun, 20 Sep 2026 08:00:00 +0000\n  From: carol@example.com\n  Subject: Quote\n  See attached")
    C.Check.str("msg list empty", G.Google.msg_list(Nil{}), "No messages.")
    C.Check.str("msg ids", String.join(G.Google.msg_ids(json(sample.list())), ","), "a1,a2")
    C.Check.str("msg cap", G.Str.cap("abcdef", 3n), "abc\n[... truncated]")
    C.Check.str("search path", G.Google.gmail_search_path("from:alice is:unread", 10n), "/gmail/v1/users/me/messages?q=from%3Aalice%20is%3Aunread&maxResults=10")
    C.Check.str("get path", G.Google.gmail_get_path("18c1", True{}), "/gmail/v1/users/me/messages/18c1?format=full")
    # tokens
    C.Check.str("tokens", show.tok(G.Google.tokens(sample.tok(), 1000n)), "ya29.a0AfB|4599|1//0gXyz|me@example.com")
    C.Check.str("tokens refresh", show.tok(G.Google.tokens(sample.refresh(), 5n)), "ya29.new|3604||")
    C.Check.str("tokens error", show.tok(G.Google.tokens("{\"error\": \"invalid_grant\", \"error_description\": \"Bad Request\"}", 5n)), "none")
    C.Check.str("oauth error", G.Google.api_error("{\"error\": \"invalid_grant\", \"error_description\": \"Bad Request\"}"), "invalid_grant: Bad Request")
    C.Check.str("api error", G.Google.api_error("{\"error\": {\"code\": 404, \"message\": \"Requested entity was not found.\", \"status\": \"NOT_FOUND\"}}"), "Requested entity was not found.")
    C.Check.str("raw error", G.Google.api_error("<html>502</html>"), "<html>502</html>")
    C.Check.str("fresh", show.bool(G.Google.fresh(1000n, 1061n)), "true")
    C.Check.str("stale", show.bool(G.Google.fresh(1000n, 1060n)), "false")
    # calendar
    C.Check.str("events", G.Google.events(json(sample.events())),
      "2 events (calendar time zone America/Los_Angeles):\n- 2026-09-24T09:00:00-07:00 -> 2026-09-24T09:15:00-07:00  Standup\n  at Room 4\n  id ev1, 2 attendees\n- 2026-09-25 -> 2026-09-26  (no title)\n  id ev2")
    C.Check.str("events empty", G.Google.events(json("{\"items\": []}")), "No events.")
    C.Check.str("events path", G.Google.cal_list_path("2026-09-24", "2026-10-01T00:00:00-07:00", 20n, "design review"),
      "/calendar/v3/calendars/primary/events?timeMin=2026-09-24T00%3A00%3A00Z&timeMax=2026-10-01T00%3A00%3A00-07%3A00&singleEvents=true&orderBy=startTime&maxResults=20&q=design%20review")
    C.Check.str("event body", G.Google.event_body("Review", "", "2026-09-24T09:00:00-07:00", "2026-09-24T10:00:00-07:00", ["a@x.org", " b@x.org"], False{}, "America/Los_Angeles"),
      "{\"summary\":\"Review\",\"start\":{\"dateTime\":\"2026-09-24T09:00:00-07:00\",\"timeZone\":\"America/Los_Angeles\"},\"end\":{\"dateTime\":\"2026-09-24T10:00:00-07:00\",\"timeZone\":\"America/Los_Angeles\"},\"attendees\":[{\"email\":\"a@x.org\"},{\"email\":\"b@x.org\"}]}")
    C.Check.str("event all day", G.Google.event_body("Trip", "Fly", "2026-12-31", "", Nil{}, True{}, ""),
      "{\"summary\":\"Trip\",\"description\":\"Fly\",\"start\":{\"date\":\"2026-12-31\"},\"end\":{\"date\":\"2027-01-01\"}}")
    C.Check.str("iso", G.Date.iso(1790000000n), "2026-09-21T14:13:20Z")
    C.Check.str("iso epoch", G.Date.iso(0n), "1970-01-01T00:00:00Z")
    C.Check.str("next day leap", G.Date.next_day("2000-02-28"), "2000-02-29")
    C.Check.str("next day march", G.Date.next_day("2026-02-28"), "2026-03-01")
    C.Check.str("tools", String.join(G.Google.tool_names(), ","), "gmail_search,gmail_read,gmail_send,calendar_events,calendar_create")
    C.Check.str("tool defs", Nat.show(List.length(&2, J.Json, G.Google.tool_defs())), "5")
    C.Check.str("asks", show.bool(Bool.and(G.Google.asks("gmail_send"), Bool.not(G.Google.asks("gmail_read")))), "true")
