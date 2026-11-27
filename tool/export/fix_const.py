"""Remove the outermost enclosing `const` for each 'Methods can't be invoked in constant expressions' error."""
import re, os, sys, collections
base = os.path.join(os.path.dirname(__file__), '..', '..')
errs = collections.defaultdict(list)
raw = open(os.path.join(base, 'build', 'an.txt'), 'rb').read()
txt = raw.decode('utf-16') if raw[:2] in (b'\xff\xfe', b'\xfe\xff') else raw.decode('utf-8', 'ignore')
for line in txt.splitlines():
    m = re.search(r"error - (.*?) - (\S+?):(\d+):(\d+) - ", line)
    if m and "constant" in m.group(1):
        errs[m.group(2)].append((int(m.group(3)), int(m.group(4))))
OPEN, CLOSE = '([{', ')]}'

def match_end(s, i):
    # i at an opening bracket; naive string-aware matching
    depth = 0
    j = i
    q = None
    while j < len(s):
        c = s[j]
        if q:
            if c == '\\': j += 1
            elif c == q: q = None
        elif c in '\'"': q = c
        elif c in OPEN: depth += 1
        elif c in CLOSE:
            depth -= 1
            if depth == 0: return j
        j += 1
    return len(s)

total = 0
for rel, locs in errs.items():
    p = os.path.join(base, rel)
    s = open(p, encoding='utf-8').read()
    lines = s.split('\n')
    starts = [0]
    for l in lines: starts.append(starts[-1] + len(l) + 1)
    kill = set()
    consts = [m for m in re.finditer(r'\bconst\s+', s)]
    for ln, col in locs:
        off = starts[ln - 1] + col - 1
        best = None
        for m in consts:
            if m.start() >= off: break
            k = m.end()
            while k < len(s) and s[k] not in '([{;,)': k += 1
            if k >= len(s) or s[k] not in OPEN: continue
            if match_end(s, k) >= off:
                best = m  # earliest enclosing = outermost (consts sorted by start)
                break
        if best: kill.add((best.start(), best.end()))
    for a, b in sorted(kill, reverse=True):
        s = s[:a] + s[b:]
        total += 1
    open(p, 'w', encoding='utf-8', newline='').write(s)
print('removed', total, 'consts')
