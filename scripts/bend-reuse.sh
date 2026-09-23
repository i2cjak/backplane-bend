#!/bin/sh
# Mark binders the checker reports as "consumed more than once" with `+`,
# one at a time, until the file checks or an error needs a human.
#   scripts/bend-reuse.sh FILE.bend
f=$1
for i in $(seq 1 40); do
  out=$(bend "$f" --check-only 2>&1 | grep -E '^- (message|expected|observed)|^Location|All terms|>\|' | head -4)
  echo "$out" | grep -q 'consumed more than once' || { echo "$out"; exit 0; }
  line=$(echo "$out" | grep -oE '^[0-9]+>' | head -1 | tr -d '>')
  var=$(echo "$out" | grep '^- expected' | awk '{print $4}')
  python3 - "$line" "$var" "$f" <<'PY' || { echo "$out"; exit 1; }
import sys, re
line, var, p = int(sys.argv[1]), sys.argv[2], sys.argv[3]
L = open(p).read().split('\n'); s = L[line - 1]
s2 = re.sub(r'(?<![\w+.])' + re.escape(var) + r'(?=[,}\s):])', '+' + var, s, count=1)
if s2 == s: sys.exit(1)
L[line - 1] = s2; open(p, 'w').write('\n'.join(L)); print("marked +" + var + " at line", line)
PY
done
