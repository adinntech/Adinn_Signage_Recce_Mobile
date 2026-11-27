# Lists the unique user-facing string literals still hard-coded in lib/
# (adjacent literals are joined exactly as Dart concatenates them).
import glob, re, json, ast
prefix = r"""(?:\bText\(|\blabel:|\btitle:|\btooltip:|\bhintText:|\blabelText:|\bhelperText:|\bsubtitle:|\bshowSnack\(\s*context,|\bconfirmText:|\bmessage:|\btext:)\s*(?:const\s+)?(?:Text\(\s*)?(?:const\s+)?"""
lit = r"""(?:'(?:[^'\\$\n]|\\.)*'|"(?:[^"\\$\n]|\\.)*")"""
pat = re.compile(prefix + r'((?:' + lit + r'\s*)+)(?=[,)])')
one = re.compile(lit)
seen = {}
for f in glob.glob('lib/features/**/*.dart', recursive=True) + glob.glob('lib/core/widgets/*.dart'):
    t = open(f, encoding='utf-8').read()
    for m in pat.finditer(t):
        parts = one.findall(m.group(1))
        try:
            s = ''.join(ast.literal_eval(p) for p in parts)
        except Exception:
            continue
        if len(s.strip()) < 2 or not re.search('[A-Za-z]', s) or s.startswith(('http', 'assets')) or re.fullmatch(r'[a-z_]+', s):
            continue
        seen.setdefault(s, len(parts))
json.dump(sorted(seen), open('build/export/literals.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
multi = [s for s, n in seen.items() if n > 1]
print(len(seen), 'multi', len(multi))
print(' || '.join(multi))
