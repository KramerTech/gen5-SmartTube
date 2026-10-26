"""Print the items of a string-array resource, one per line, from
`aapt dump --values resources <apk>` on stdin.

usage: aapt dump --values resources app.apk | resource_array.py <name>
Exits 1 if the array isn't in the dump.
"""
import re
import sys

name = sys.argv[1]
lines = sys.stdin.read().split("\n")
head = re.compile(r"^\s*resource 0x[0-9a-f]+ \S+:array/" + re.escape(name) + r": <bag>")
item = re.compile(r'^\s*#\d+ \(Key=0x[0-9a-f]+\): \(string\d*\) "(.*)"$')
for i, line in enumerate(lines):
    if head.match(line):
        for nxt in lines[i + 1:]:
            if nxt.strip().startswith("Parent="):
                continue
            m = item.match(nxt)
            if not m:
                break
            print(m.group(1))
        sys.exit(0)
sys.exit(1)
