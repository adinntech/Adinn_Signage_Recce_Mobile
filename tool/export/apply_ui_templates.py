"""Wrap remaining fixed messages: Text/showSnack/props literals, plus interpolated
literals -> context.uf('template {0}', [args]). Writes build/export/templates.json."""
import os, re, json
root = os.path.join(os.path.dirname(__file__), '..', '..', 'lib')
SQ = r"'(?:[^'\\\n]|\\.)*'"
DQ = r'"(?:[^"\\\n]|\\.)*"'
LIT1 = '(?:%s|%s)' % (SQ, DQ)
LIT = r'(?:%s(?:\s*%s)*)' % (LIT1, LIT1)
HEAD = r"(?:(?<![\w.])(?:const\s+)?Text\(|showSnack\(\s*\w+\s*,\s*|(?:tooltip|hintText|labelText|helperText|errorText)\s*:\s*)"
rx = re.compile(r"(%s)(%s)(?=\s*[,)])" % (HEAD, LIT))
interp = re.compile(r"\$\{([^{}'\"]*)\}|\$([A-Za-z_]\w*)")
letters = re.compile(r'[A-Za-z]')
templates = set()

def conv(m):
    head, lit = m.group(1), m.group(2)
    body = lit[1:-1]
    if '$' not in body:
        if not letters.search(body) or 'context.ui(' in head:
            return m.group(0)
        return head.replace('const ', '') + 'context.ui(%s)' % lit
    # interpolated
    args = []
    def sub(mm):
        args.append(mm.group(1) or mm.group(2))
        return '{%d}' % (len(args) - 1)
    t = interp.sub(sub, body)
    if '$' in t.replace('\\$', ''):
        return m.group(0)  # nested/complex
    if not letters.search(re.sub(r'\{\d+\}', '', t)):
        return m.group(0)
    templates.add(t)
    q = lit[0]
    return head.replace('const ', '') + "context.uf(%s%s%s, [%s])" % (q, t, q, ', '.join(args))

n = 0
for d, _, fs in os.walk(root):
    for f in fs:
        if not f.endswith('.dart') or d.replace('\\', '/').endswith('lib/l10n'):
            continue
        p = os.path.join(d, f)
        s = open(p, encoding='utf-8').read()
        if 'package:flutter/material.dart' not in s and 'package:flutter/widgets.dart' not in s:
            continue
        t = rx.sub(conv, s)
        if t != s:
            if 'l10n/l10n.dart' not in t:
                rel = os.path.relpath(os.path.join(root, 'l10n', 'l10n.dart'), d).replace('\\', '/')
                i = t.index('import ')
                t = t[:i] + "import '%s';\n" % rel + t[i:]
            open(p, 'w', encoding='utf-8', newline='').write(t)
            n += 1
os.makedirs(os.path.join(root, '..', 'build', 'export'), exist_ok=True)
json.dump(sorted(templates), open(os.path.join(root, '..', 'build', 'export', 'templates.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(n, 'files;', len(templates), 'templates')
