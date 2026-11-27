"""Wrap displays of FIXED enum/catalog labels (never user content) with context.ui()."""
import os, re
root = os.path.join(os.path.dirname(__file__), '..', '..', 'lib')
V = r"(?:f|unit|t|m|sv|level|kind|type|severity|shape|key|status|role|stage|layer|tool|source|_distUnit|_b\.unit)"
CH = r"((?:[\w!?]+\.)*%s\.(?:label|shortLabel))" % V
rx_text = re.compile(r"(?<![\w.])(?:const\s+)?Text\(\s*%s(?=\s*[,)])" % CH)
rx_prop = re.compile(r"\b(labelText|suffixText|hintText|tooltip)\s*:\s*%s(?=\s*[,)])" % CH)
n = 0
for d, _, fs in os.walk(root):
    for f in fs:
        if not f.endswith('.dart') or d.replace('\\', '/').endswith('lib/l10n'):
            continue
        p = os.path.join(d, f)
        s = o = open(p, encoding='utf-8').read()
        if 'package:flutter/material.dart' not in s or '_pdf' in f or 'report_' in f:
            continue
        s = rx_text.sub(lambda m: "Text(context.ui(%s)" % m.group(1), s)
        s = rx_prop.sub(lambda m: "%s: context.ui(%s)" % (m.group(1), m.group(2)), s)
        if s != o:
            if 'l10n/l10n.dart' not in s:
                rel = os.path.relpath(os.path.join(root, 'l10n', 'l10n.dart'), d).replace('\\', '/')
                i = s.index('import ')
                s = s[:i] + "import '%s';\n" % rel + s[i:]
            open(p, 'w', encoding='utf-8', newline='').write(s)
            n += 1
print(n, 'files')
