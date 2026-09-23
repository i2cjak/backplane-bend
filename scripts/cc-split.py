#!/usr/bin/env python3
# Split the one large C file `bend X -o out.c` emits into N translation
# units that compile in parallel (and each in far less memory).
#
#   scripts/cc-split.py build/app.c build/app-split 8
#
# The emitted file is: a prelude (runtime, tables, spins), the segments
# (one `WL_CASE(F)` function each, calling one another by musttail), then
# the rest of the runtime and the effects. Every unit gets the prelude;
# the segments are dealt out over units 1..N; unit 0 keeps the rest.
# Segments become hidden (not static) so units can call each other's, and
# the runtime's mutable globals are defined in unit 0 and extern elsewhere.
import os
import re
import sys

src, out, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
text = open(src).read()

SEG = "\n// Segments\n// ========\n"
TAIL = "\n// A task enters through its words"
GLOB = "\n// Globals\n// =======\n"
GLOB_END = "\n// The device program compiles from the binary's own text."
WL_FN = "#define WL_FN      static PRESERVE(preserve_none) __attribute__((noinline)) Reply"

for mark in (SEG, TAIL, GLOB, GLOB_END, WL_FN):
    if text.count(mark) != 1:
        sys.exit("cc-split: the emitted C changed shape (%r)" % mark.strip())

seg_at = text.index(SEG)
tail_at = text.index(TAIL)
prelude, segs, tail = text[:seg_at], text[seg_at:tail_at], text[tail_at:]

prelude = prelude.replace(WL_FN,
    '#define WL_FN      __attribute__((visibility("hidden"))) PRESERVE(preserve_none) __attribute__((noinline)) Reply')

# the globals: `static T name...;` (maybe with an initializer)
g0, g1 = prelude.index(GLOB), prelude.index(GLOB_END)
glob = prelude[g0:g1]
decl = re.compile(r"^static (?!const )((?:_Atomic )?[A-Za-z_][A-Za-z0-9_]*(?:\s+|\s*\*\s*))([A-Za-z_][A-Za-z0-9_]*)((?:\[[^\]]*\])*)([^;=]*)(=[^;]*)?;", re.M)

def as_extern(m):
    return "extern %s%s%s%s;" % (m.group(1), m.group(2), m.group(3), m.group(4))

def as_def(m):
    return "%s%s%s%s%s;" % (m.group(1), m.group(2), m.group(3), m.group(4), m.group(5) or "")

# functions the prelude declares and the tail defines (corpus_grow,
# f32_show...): shared, so hidden rather than static on both sides
proto = re.compile(r"^static ([A-Za-z_][A-Za-z0-9_ ]*?\**)\s*\b([A-Za-z_][A-Za-z0-9_]*)\(([^;{]*)\);$", re.M)
shared = [m.group(2) for m in proto.finditer(prelude)
          if re.search(r"(?m)^static [^;{]*\b%s\([^;]*\{" % re.escape(m.group(2)), tail)]
for name in shared:
    pat = r"(?m)^static ([^;{(]*\b%s\()" % re.escape(name)
    prelude = re.sub(pat, r'__attribute__((visibility("hidden"))) \1', prelude)
    tail = re.sub(pat, r'__attribute__((visibility("hidden"))) \1', tail)
g0, g1 = prelude.index(GLOB), prelude.index(GLOB_END)

pre_ext = prelude[:g0] + decl.sub(as_extern, glob) + prelude[g1:]
pre_def = prelude[:g0] + decl.sub(as_def, glob) + prelude[g1:]

# segments: the body between the section header's `#if !DEVICE` and the
# last `#endif`
body = segs[len(SEG):].lstrip("\n")
open_if = "#if !DEVICE\n"
if not body.startswith(open_if):
    sys.exit("cc-split: segments do not open with #if !DEVICE")
body = body[len(open_if):]
close = body.rstrip().rfind("#endif")
body = body[:close]
parts = re.split(r"(?m)^(?=  WL_CASE\()", body)
head, cases = parts[0], parts[1:]
if head.strip():
    sys.exit("cc-split: text before the first segment")

# deal the segments out in contiguous runs of similar size
total = sum(len(c) for c in cases)
units, cur, size = [], [], 0
for c in cases:
    cur.append(c)
    size += len(c)
    if size >= total / n and len(units) < n - 1:
        units.append(cur)
        cur, size = [], 0
units.append(cur)

os.makedirs(out, exist_ok=True)
for f in os.listdir(out):
    if f.startswith("u") and f.endswith(".c"):
        os.remove(os.path.join(out, f))
with open(os.path.join(out, "u0.c"), "w") as f:
    f.write(pre_def + SEG + tail)
for i, u in enumerate(units, 1):
    with open(os.path.join(out, "u%d.c" % i), "w") as f:
        f.write(pre_ext + SEG + open_if + "".join(u) + "#endif\n")
print(len(units) + 1)
