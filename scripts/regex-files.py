#!/usr/bin/env python3
# Regex file search for the start menu: match the file name (or the whole path when the
# pattern contains "/") against the fd index, shortest paths first.
# usage: regex-files.py PATTERN INDEX [MAX]
import re, sys
try:
    rx = re.compile(sys.argv[1], re.I)
except re.error:
    sys.exit(0)
full = "/" in sys.argv[1]
hits = []
with open(sys.argv[2], encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.rstrip("\n")
        p = line.rstrip("/")
        if rx.search(p if full else p[p.rfind("/") + 1:]):
            hits.append(line)
hits.sort(key=len)
print("\n".join(hits[: int(sys.argv[3]) if len(sys.argv) > 3 else 40]))
