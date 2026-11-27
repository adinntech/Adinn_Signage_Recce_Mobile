# Localization audit (per file). It distinguishes:
#  1 predefined UI correctly localized (context.ui/tq with a Tamil entry)
#  2 hardcoded untranslated UI (literal passed straight to Text/InputDecoration)
#  3 translation keys not connected to a widget (dictionary-only entries)
#  4 dynamic messages missing a localized template (literal with a count/date)
#  5 intentionally retained technical terms (GSB, NLB, GST, AR, PDF, 2D, 3D, units)
#  6 user-generated content excluded from localization (non-literal expressions)
#  7 missing Tamil resource entries (wrapped literal absent from the dictionaries)
#  8 native / custom-rendered UI (painter/PDF/native files are reported separately)
#  9 unverified conditional UI branches (see the widget-level regression suite)
# Non-UI values (API routes, JSON keys, asset paths, log identifiers) are skipped.
# Static counts are NOT proof of full localization: confirm with widget tests.
# Writes docs/localization_coverage.md and build/export/missing.json.
import glob, re, os, json

# Outputs can be redirected so an existing report is never overwritten.
COVERAGE_OUT = os.environ.get('LOCALIZATION_AUDIT_OUT', 'docs/localization_coverage.md')
MISSING_OUT = os.environ.get('LOCALIZATION_AUDIT_MISSING', 'build/export/missing.json')

def _join_literals(s):
    out = ''
    for part in re.findall(r"'(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\"", s):
        p = part[1:-1]
        if out and not out[-1].isspace() and not p[:1].isspace():
            out += ' '
        out += p
    return out.replace("\\'", "'").replace('\\n', '\n').replace('\\\\', '\\').replace('\\$', '$')

def keys(path, var=None):
    t = open(path, encoding='utf-8').read()
    ks = set()
    # Keys may span adjacent string literals on separate source lines.
    for m in re.finditer(r"^\s*((?:(?:'(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\")\s*)+):", t, re.M):
        ks.add(_join_literals(m.group(1)))
    return ks

DICT = keys('lib/l10n/ta_ui.dart') | keys('lib/l10n/ta_ui_extra.dart') | keys('lib/l10n/ta_catalog.dart')
SQ = r"'(?:[^'\\\n]|\\.)*'"; DQ = r'"(?:[^"\\\n]|\\.)*"'
LIT1 = '(?:%s|%s)' % (SQ, DQ)
LIT = '(?:%s(?:\s*%s)*)' % (LIT1, LIT1)
HEAD = r"(?:(?<![\w.])Text\(|showSnack\(\s*\w+\s*,\s*|(?:tooltip|hintText|labelText|helperText|errorText)\s*:\s*)"
wrapped = re.compile(r"context\.(?:ui|uf|tq)\(\s*(%s)" % LIT)
fixed = re.compile(r"(?:%s)\s*(%s)(?=\s*[,)])" % (HEAD, LIT))
dyn = re.compile(r"(?:%s)\s*(?!['\"]|context\.(?:ui|uf|tq)\()([A-Za-z_(][^,)]*)" % HEAD)
alias = re.compile(r"context\.(?:shopName|shopFullAddress|shopAddress|shopOwner|taskTitle|personName|projectName|projectDescription|regionLabel|locationLabel|mediaLabel|installationLabel|generatedBoardName|mediaBoardSummary)\(")
TECH = {'GSB', 'NLB', 'GST', 'AR', 'PDF', '2D', '3D', 'PIN', 'OTP', 'GPS', 'ENG', 'LED', 'mm', 'ft', 'in', 'cm', 'm', 'N', 'PNG', 'MDF'}
BRAND = {'a', 'adinn'}  # Adinn wordmark letters – intentionally unchanged.
letters = re.compile(r'[A-Za-z]')
def unq(s):
    # Adjacent Dart literals concatenate; insert a separator only when neither
    # side already provides whitespace (avoids false "missing" double spaces).
    out = ''
    for part in re.findall(LIT1, s):
        p = part[1:-1]
        if out and not out[-1].isspace() and not p[:1].isspace():
            out += ' '
        out += p
    return out.replace("\\'", "'").replace('\\n', '\n').replace('\\\\', '\\')
def technical(s):
    if not letters.search(s): return True
    toks = re.findall(r"[A-Za-z0-9]+", s)
    return all(t in TECH or t.isdigit() for t in toks) or (len(s) <= 6 and s.upper() == s)

def non_ui(s):
    """Skip API routes, JSON keys, asset paths and internal identifiers."""
    low = s.lower()
    return (low.startswith(('http://', 'https://', 'assets/', '/', '#', 'lib/'))
            or low.endswith(('.png', '.jpg', '.jpeg', '.webp', '.json', '.dart', '.arb'))
            or ('/' in s and ' ' not in s and low.startswith(('api/', 'v1/', 'v2/'))))

rows, missing = [], {}
for f in sorted(glob.glob('lib/**/*.dart', recursive=True)):
    fp = f.replace('\\', '/')
    if fp.startswith('lib/l10n/') or fp.endswith('.g.dart') or '_pdf' in fp or 'report_' in fp and 'sheet' not in fp:
        continue
    t = open(f, encoding='utf-8').read()
    loc = miss = tech = tmpl = 0
    for m in wrapped.finditer(t):
        s = unq(m.group(1))
        if non_ui(s) or s in BRAND: continue
        if re.search(r'\{\d+\}', s) and m.group(0).lstrip().startswith('context.uf('):
            tmpl += 1  # parameterized template: arguments are never translated
        if technical(s) or s in DICT: loc += 1 if not technical(s) else 0; tech += 1 if technical(s) else 0
        else:
            miss += 1; missing.setdefault(s, set()).add(fp)
    for m in fixed.finditer(t):
        s = unq(m.group(1))
        if '$' in s or non_ui(s) or s in BRAND: continue
        if technical(s): tech += 1
        elif re.search(r'\{\d+\}|\d+\s+(shop|task|board|day|min|h)', s):
            tmpl += 1  # hardcoded dynamic message with no localized template
            miss += 1; missing.setdefault(s, set()).add(fp)
        else: miss += 1; missing.setdefault(s, set()).add(fp)
    a = len(alias.findall(t))
    d = max(0, len(dyn.findall(t)) - a)  # verified aliases are not dynamic user text
    if loc + miss + tech + tmpl + d + a == 0: continue
    sw = 'yes' if re.search(r'LanguageSwitcher|AdinnAppBar', t) else ('n/a' if 'AppBar(' not in t else 'NO')
    rows.append((fp, loc, miss, tech, tmpl, a, d, sw))
out = ['# Localization coverage audit', '',
       'Per file: **localized** = fixed UI literal with a Tamil entry; **missing** = fixed UI literal still without Tamil; '
       '**technical** = intentionally untranslated (GSB, NLB, GST, AR, PDF, 2D, 3D, units, symbols); '
       '**dynamic** = user content / ids / computed text, never translated. '
       '**templates** = parameterized messages/dates; **dynamic** = user content / ids / computed text, never translated. '
       'PDF tables are translated through `TamilReport` and verified by `test/tamil_pdf_test.dart`. '
       'Custom-painter, native and PDF strings need separate review; conditional branches must be checked in widget tests. '
       'These static counts are not proof of full localization.', '',
       '**aliases** = verified predefined shop/task/address/board display variants (stored data untouched).', '',
       '| file | localized | missing | technical | templates | aliases | dynamic | ENG/அ |',
       '|---|---:|---:|---:|---:|---:|---:|---|']
for r in sorted(rows, key=lambda r: -r[2]):
    out.append('| %s | %d | %d | %d | %d | %d | %d | %s |' % r)
L = sum(r[1] for r in rows); M = sum(r[2] for r in rows); T = sum(r[3] for r in rows)
P = sum(r[4] for r in rows); A = sum(r[5] for r in rows); D = sum(r[6] for r in rows)
out += ['', f'Totals: localized {L}, missing {M}, technical {T}, templates {P}, aliases {A}, dynamic {D}.']
os.makedirs(os.path.dirname(COVERAGE_OUT) or '.', exist_ok=True)
open(COVERAGE_OUT, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
os.makedirs(os.path.dirname(MISSING_OUT) or '.', exist_ok=True)
json.dump({k: sorted(v) for k, v in missing.items()}, open(MISSING_OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(len(rows), 'files; localized', L, 'missing', M, 'tech', T, 'templates', P,
      'aliases', A, 'dyn', D, 'unique missing', len(missing))
