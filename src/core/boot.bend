import Base

# Start-up. The window opens before anything slow: the providers' model
# lists are probed after it (the probes take seconds; `claude -p` starts
# its MCP servers first), and until they answer the hub serves the list
# it found last time, kept in <home>/models.cache: the list's JSON on the
# first line, the prompt's text after it. Laws models_cache_* (what is
# read back is what was written) and models_quiet (a probe that finds
# the same list tells no one).

def Cache.nl() -> Char:
  Chr{10}

def Cache.one.k(nl: Bool, +c: Char, rest: String) -> String:
  match nl:
    case True{}:
      rest
    case False{}:
      SCon{c, rest}

# the text on one line (line breaks dropped; JSON as the hub writes it
# has none)
def Cache.one(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      Cache.one.k(Char.is_eq(c, Cache.nl()), c, Cache.one(t))

def Cache.show(ms: String, mt: String) -> String:
  String.append(ms, SCon{Cache.nl(), mt})

# what the cache keeps for a list and its text
def Cache.of(ms: String, mt: String) -> String:
  Cache.show(Cache.one(ms), mt)

def Cache.json.k(nl: Bool, +c: Char, rest: String) -> String:
  match nl:
    case True{}:
      SNil{}
    case False{}:
      SCon{c, rest}

# the first line
def Cache.json(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      Cache.json.k(Char.is_eq(c, Cache.nl()), c, Cache.json(t))

def Cache.text.k(nl: Bool, after: String, rest: String) -> String:
  match nl:
    case True{}:
      after
    case False{}:
      rest

# what follows the first line
def Cache.text(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, +t}:
      Cache.text.k(Char.is_eq(c, Cache.nl()), t, Cache.text(t))

# a probe's list is news (sent to clients, cached) only when it differs
# from the one they have
def Models.news(ms: String, last: String) -> Bool:
  Bool.not(String.eq(ms, last))
