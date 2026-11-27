# Documents the Review classifications of the question mapping (docs/).
import csv

rows = list(csv.DictReader(open('docs/question_mapping_report.csv', encoding='utf-8-sig')))
src = list(csv.DictReader(open('docs/question_mapping_rows.csv', encoding='utf-8-sig')))
rev = [r for r in rows if r['final_action'] == 'Review']
safety = ('excavation_permission', 'underground_utilities', 'pole_excavation_allowed')
out = [
    f'# Review classifications ({len(rev)} canonical IDs)', '',
    f'{len(rev)} canonical IDs are classified Review. These are canonical question IDs; the workbook has '
    f'{len(src)} source ROWS covering {len(rows)} canonical IDs. Rows per ID are counted below.', '',
    'Rule: a Review question is not removed from the vendor form until explicitly approved. N/A / Not assessed '
    'is never treated as a safe installation (feasibility shows Requires Review).', '',
    '| canonical_id | question | source rows | vendor decisions Needed/Not/Blank | dependency | current behaviour |',
    '|---|---|---|---|---|---|',
]
for r in rev:
    cid = r['canonical_id']
    n = sum(1 for s in src if s['canonical_id'] == cid)
    cur = ('kept in the form (Installation Safety)' if cid in safety else
           'kept in the form, required, until the business approves removal (it raises a feasibility '
           'review flag; hiding it would make an unassessed site look obstruction-free)')
    out.append(f"| {cid} | {r['question_en']} | {n} | {r['needed_rows']}/{r['not_needed_rows']}/{r['blank_rows']} "
               f"| {r['downstream_dependency']} | {cur} |")
open('docs/question_review_dependencies.md', 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print(len(rev), len(src), len(rows))
