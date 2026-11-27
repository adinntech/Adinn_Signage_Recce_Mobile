# Read-only analysis of the vendor-reviewed workbook (never modifies it).
#   python tool/export/analyze_vendor_decisions.py <path-to-Recce-form.xlsx>
import sys, json, os, collections
from openpyxl import load_workbook

p = sys.argv[1]
wb = load_workbook(p)  # formulas are not evaluated; we only read cell values
sheets = [s for s in wb.sheetnames if s[:2].isdigit() and 2 <= int(s[:2]) <= 10]
rows = []
for s in sheets:
    ws = wb[s]
    hidden = [r for r, d in ws.row_dimensions.items() if d.hidden]
    cnt = collections.Counter()
    for r in range(5, ws.max_row + 1):
        if ws.cell(r, 7).value in (None, ''):
            continue
        q = ws.cell(r, 17).value or ''
        dec = 'Needed' if q.startswith('Needed') else 'NotNeeded' if q.startswith('Not Needed') else 'Blank'
        fill = ws.cell(r, 7).fill.start_color.rgb if ws.cell(r, 7).fill and ws.cell(r, 7).fill.fill_type else None
        cnt[dec] += 1
        rows.append(dict(sheet=s, row=r, sno=ws.cell(r, 1).value, option=ws.cell(r, 2).value, inst=ws.cell(r, 4).value,
                         cat=ws.cell(r, 6).value, q=ws.cell(r, 7).value, decision=dec, remarks=ws.cell(r, 16).value,
                         fill=str(fill)))
    print(s, 'rows', sum(cnt.values()), dict(cnt), 'hidden rows', len(hidden))
tot = collections.Counter(r['decision'] for r in rows)
print('TOTAL', len(rows), dict(tot), 'distinct texts', len({r['q'] for r in rows}),
      'distinct needed texts', len({r['q'] for r in rows if r['decision'] == 'Needed'}))
print('Needed texts:', sorted({r['q'] for r in rows if r['decision'] == 'Needed'}))
fills = collections.Counter(r['fill'] for r in rows)
print('fills', fills)
print('remarks:', [(r['sheet'], r['row'], r['q'], r['remarks']) for r in rows if r['remarks']])
json.dump(rows, open('build/export/vendor_decisions.json', 'w', encoding='utf8'), ensure_ascii=False, indent=1)
