"""Replace the shadow Text with the original Text + explicit context.ui().
Only string LITERALS are wrapped, so user content / variables never translate.
Also wraps tooltip/hintText/labelText/helperText/errorText literals."""
import os, re, sys
root = os.path.join(os.path.dirname(__file__), '..', '..', 'lib')
LIT = r"""(?:'(?:[^'\\\n$]|\\.)*'|"(?:[^"\\\n$]|\\.)*")"""
SEQ = r"(?:%s(?:\s*%s)*)" % (LIT, LIT)
text_re = re.compile(r"(?:const\s+)?\bText\(\s*(%s)(?=\s*[,)])" % SEQ)
prop_re = re.compile(r"\b(tooltip|hintText|labelText|helperText|errorText|semanticLabel)\s*:\s*(%s)(?=\s*[,)])" % SEQ)
IMP_HIDE = "import 'package:flutter/material.dart' hide Text;"
IMP_LOC = re.compile(r"import '[./]*(?:core/widgets/)?loc_text\.dart';\n")
has_letters = re.compile(r'[A-Za-z]')
changed = 0
for d, _, fs in os.walk(root):
    for f in fs:
        if not f.endswith('.dart') or f == 'loc_text.dart':
            continue
        p = os.path.join(d, f)
        s = o = open(p, encoding='utf-8').read()
        if IMP_HIDE in s:
            s = s.replace(IMP_HIDE, "import 'package:flutter/material.dart';")
            s = IMP_LOC.sub('', s)
        def wrap(m, kind):
            lit = m.group(1) if kind == 'text' else m.group(2)
            if not has_letters.search(lit):
                return m.group(0)
            if kind == 'text':
                return "Text(context.ui(%s)" % lit
            return "%s: context.ui(%s)" % (m.group(1), lit)
        s = text_re.sub(lambda m: wrap(m, 'text'), s)
        s = prop_re.sub(lambda m: wrap(m, 'prop'), s)
        if s != o:
            if 'l10n/l10n.dart' not in s and 'l10n.dart' not in s:
                rel = os.path.relpath(os.path.join(root, 'l10n', 'l10n.dart'), d).replace('\\', '/')
                # insert after the first import line
                i = s.index('import ')
                s = s[:i] + "import '%s';\n" % rel + s[i:]
            open(p, 'w', encoding='utf-8', newline='').write(s)
            changed += 1
print(changed, 'files changed')
