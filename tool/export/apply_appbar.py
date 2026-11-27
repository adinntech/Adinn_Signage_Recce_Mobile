# One-off codemod: every `AppBar(` in lib/features becomes `AdinnAppBar(`
# (adds the ENG / அ switcher as the last action). Files that already place a
# LanguageSwitcher by hand are left alone.
import re, glob, sys
pat = re.compile(r'(?<![A-Za-z_])AppBar\(')
changed = []
used = set()
for f in glob.glob('lib/features/**/*.dart', recursive=True):
    t = open(f, encoding='utf-8').read()
    if 'LanguageSwitcher' in t or not pat.search(t):
        continue
    for m in pat.finditer(t):
        # collect named args used in this AppBar( ... ) roughly
        seg = t[m.end():m.end() + 900]
        used |= set(re.findall(r'\n\s+(\w+):', seg[:400]))
    n = pat.sub('AdinnAppBar(', t)
    depth = f.replace('\\', '/').count('/') - 1  # lib/features/x/y.dart -> ../../
    imp = "import '../../core/widgets/adinn_app_bar.dart';\n"
    # insert after the last import line
    lines = n.split('\n')
    last = max(i for i, l in enumerate(lines) if l.startswith('import '))
    lines.insert(last + 1, imp.strip())
    open(f, 'w', encoding='utf-8', newline='').write('\n'.join(lines))
    changed.append(f)
print(len(changed), 'files')
print(sorted(used))
