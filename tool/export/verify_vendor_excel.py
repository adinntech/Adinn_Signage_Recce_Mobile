# Verifies the generated workbook against build/export/questions.json (live catalog dump).
import json, os, zipfile
from collections import Counter
from openpyxl import load_workbook

ROOT = os.getcwd()
D = json.load(open(os.path.join(ROOT, 'build/export/questions.json'), encoding='utf8'))
P = os.path.join(ROOT, 'build/export/Recce_Site_Questions_Vendor_Review.xlsx')
assert zipfile.ZipFile(P).testzip() is None
wb = load_workbook(P)
print('sheets:', wb.sheetnames)
exp = ['00_Instructions', '01_Review_Summary', '02_GSB_Single', '03_GSB_Double', '04_NLB_Single', '05_NLB_Box',
       '06_Foam_Vinyl', '07_Acrylic', '08_One_Way_Vision', '09_Plain_Vinyl', '10_MDF', '11_New_Questions', '12_Technical_Audit']
assert wb.sheetnames == exp, wb.sheetnames
fail = 0
total = 0
uniq = set()
combos = set()
tamil = lambda s: any('஀' <= ch <= '௿' for ch in str(s))
for name in exp[2:11]:
    ws = wb[name]
    hdr = [c.value for c in ws[4]]
    assert hdr[-1].startswith('App Requirement – Vendor Decision'), name
    assert len(hdr) == 17
    last = ws.max_row
    dv_ranges = [str(r.sqref) for dv in ws.data_validations.dataValidation if dv.formula1 and 'Needed in App' in dv.formula1 for r in [dv]]
    assert any(f'Q5:Q{last}' in x for x in dv_ranges), (name, dv_ranges)
    seen = {}
    for r in range(5, last + 1):
        row = [ws.cell(r, c).value for c in range(1, 18)]
        total += 1
        uniq.add(row[6])
        combos.add((row[1], row[3]))
        key = (row[3], row[6])
        if key in seen:
            print('DUP within combo', name, key); fail += 1
        seen[key] = 1
        for ci in (2, 3, 4, 5, 7, 8, 9, 13, 14):
            if row[ci - 1] in (None, ''):
                print('EMPTY', name, r, ci); fail += 1
        if not tamil(row[7]) or not tamil(row[2]) or not tamil(row[4]):
            print('NO TAMIL', name, r); fail += 1
        if row[14] is not None or row[16] is not None or row[15] is not None:
            print('PREFILLED', name, r); fail += 1
    print(name, 'rows', last - 4)

# compare against the dump (independent of the builder's row logic)
exp_rows = 0
for c in D['combos']:
    if c['installationName'] == 'Hanging Mount':
        continue
    mapped = c['mapped']
    n = len(c['site']) + len([q for q in c['checklist'] if q['id'] not in mapped and q['id'] != 'site_evidence_photo'])
    exp_rows += n
    ws = wb[[s for s in exp[2:11] if True][['GSB_SINGLE', 'GSB_DOUBLE', 'NLB_SINGLE_FRAME', 'NLB_BOX_FRAME', 'FOAM_VINYL', 'ACRYLIC', 'OWV', 'PLAIN_VINYL', 'MDF'].index(c['optionKey'])]]
    got = [ws.cell(r, 7).value for r in range(5, ws.max_row + 1) if ws.cell(r, 4).value == c['installationName']]
    want = [q['label'] for q in c['site']] + [q['text'] for q in c['checklist'] if q['id'] not in mapped and q['id'] != 'site_evidence_photo']
    if got != want:
        print('MISMATCH', c['optionKey'], c['installationName'], set(want) ^ set(got)); fail += 1
print('expected rows', exp_rows, 'exported', total, 'unique', len(uniq), 'combos(with MDF)', len(combos))
# types / options
bad = 0
for name in exp[2:11]:
    ws = wb[name]
    for r in range(5, ws.max_row + 1):
        t = ws.cell(r, 9).value; o = ws.cell(r, 10).value; u = ws.cell(r, 12).value
        if t.startswith('Numeric') and (o != '—'):
            bad += 1
print('type/option sanity issues', bad)
print('FAILURES', fail)
# summary formulas present
s = wb['01_Review_Summary']
print([s.cell(5, c).value for c in range(1, 10)])
print('audit rows', wb['12_Technical_Audit'].max_row - 4)
