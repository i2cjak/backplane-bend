#!/usr/bin/env python3
# The phone apps keep the Bend client's whole state between launches, as
# the JSON of its values (a constructor per object, its fields by name).
# That shape comes only from the Bend type definitions (and Base's, so the
# bend version), not from the code around them: this hash of every type
# block names the kept state, so a build that changes only code keeps it
# and one that changes a type starts afresh.
#   python3 scripts/state-key.py   -> 16 hex digits
import hashlib, os, re, subprocess, sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
h = hashlib.sha256()
try:
    h.update(subprocess.run(["bend", "version"], capture_output=True, text=True).stdout.split("\n")[0].encode())
except OSError:
    pass
for d, _, fs in sorted(os.walk(os.path.join(root, "src"))):
    for f in sorted(fs):
        if not f.endswith(".bend"):
            continue
        lines = open(os.path.join(d, f), encoding="utf-8").read().split("\n")
        i = 0
        while i < len(lines):
            if re.match(r"type \S", lines[i]):
                block = [lines[i].rstrip()]
                i += 1
                while i < len(lines) and (lines[i].startswith(" ") or not lines[i].strip()):
                    if lines[i].strip() and not lines[i].strip().startswith("#"):
                        block.append(lines[i].rstrip())
                    i += 1
                h.update(("\n".join(block) + "\n").encode())
            else:
                i += 1
sys.stdout.write(h.hexdigest()[:16] + "\n")
