#!/usr/bin/env python3
"""Reorder a .bend file so every def appears above its uses.

Bend requires definitions before use. This stable topological sort keeps the
original order wherever the dependencies allow. Comments directly above an
item travel with it. Usage: scripts/bend-order.py FILE...  (rewrites in place)
"""
import re
import sys

START = re.compile(r"^(@unsafe\s+)?(def|law|type)\s+([A-Za-z_][\w.]*)")
CTOR = re.compile(r"^\s+([A-Z][\w]*)\{")
TOKEN = re.compile(r"[A-Za-z_][\w.]*")


def items_of(text):
    lines = text.split("\n")
    head, items, cur = [], [], None
    pending = []
    for line in lines:
        m = START.match(line)
        if m:
            if cur is not None:
                items.append(cur)
            cur = {"kind": m.group(2), "name": m.group(3), "lines": pending + [line]}
            pending = []
        elif cur is None:
            if line.startswith("#"):
                pending.append(line)
            else:
                head.extend(pending)
                pending = []
                head.append(line)
        elif line.startswith("#") or (line == "" and pending):
            pending.append(line)
        elif line == "":
            pending.append(line)
        else:
            cur["lines"].extend(pending)
            pending = []
            cur["lines"].append(line)
    if cur is not None:
        items.append(cur)
    return head, items, pending


def order(items):
    names = {}
    for i, it in enumerate(items):
        names.setdefault(it["name"], []).append(i)
        if it["kind"] == "type":
            for line in it["lines"][1:]:
                m = CTOR.match(line)
                if m:
                    names.setdefault(m.group(1), []).append(i)
    deps = []
    for i, it in enumerate(items):
        body = "\n".join(l for l in it["lines"] if not l.lstrip().startswith("#"))
        d = set()
        for tok in TOKEN.findall(body):
            for j in names.get(tok, []):
                if j != i:
                    d.add(j)
        # a def filling a law comes after the law
        if it["kind"] == "def":
            for j in names.get(it["name"], []):
                if j != i and items[j]["kind"] == "law":
                    d.add(j)
        # a law is only a forward claim: it may precede its def
        if it["kind"] == "law":
            d = {j for j in d if items[j]["name"] != it["name"]}
        deps.append(d)
    placed, out = set(), []
    while len(out) < len(items):
        for i in range(len(items)):
            if i not in placed and deps[i] <= placed:
                placed.add(i)
                out.append(i)
                break
        else:
            rest = [items[i]["name"] for i in range(len(items)) if i not in placed]
            sys.exit("cycle among: " + ", ".join(rest))
    return out


def main():
    for path in sys.argv[1:]:
        text = open(path).read()
        head, items, tail = items_of(text)
        idx = order(items)
        chunks = ["\n".join(head).rstrip("\n")]
        for i in idx:
            chunks.append("\n".join(items[i]["lines"]).strip("\n"))
        open(path, "w").write("\n\n".join(chunks).rstrip("\n") + "\n")


main()
