# Canonical question mapping (outside production code). Context-aware: every
# source row is mapped through the workbook's own 12_Technical_Audit sheet
# (original / canonical question ID, media code, installation code, row id) -
# never by English wording.
#   python tool/export/build_mapping_report.py <path-to-Recce-form.xlsx>
# Outputs: docs/question_mapping_rows.csv   (all 483 source rows)
#          docs/question_mapping_report.csv / .md (per canonical id summary)
import csv, collections, os, sys
from openpyxl import load_workbook

wb = load_workbook(sys.argv[1], read_only=False)   # the workbook is only read
GREEN = {('02_GSB_Single', 18), ('08_One_Way_Vision', 15)}   # manual green rows
RETAIN = {'existing_board', 'remove_existing', 'power_available', 'power_distance', 'shutter_height',
          'fascia_material', 'wall_type', 'terrace_access', 'pipe_count', 'pipe_length', 'panel_count',
          'checklist_remarks', 'electricity_nearby', 'visible_wires', 'support_pipe_required',
          'existing_stickers'}
MOVE = {'mount_height', 'pole_height', 'pole_gap', 'foundation_depth', 'structure_height',
        'building_floors', 'projection'}
SAFETY = {'excavation_permission', 'underground_utilities', 'pole_excavation_allowed'}
# ids with a verified downstream dependency (never silently hidden)
DEPS = {
 'mount_height': 'measurement bottom_height; 2D/3D/AR clearance',
 'pole_height': 'measurement bottom_height; 2D/3D/AR clearance',
 'pole_gap': 'measurement pole_spacing; 2D/3D geometry',
 'foundation_depth': 'measurement pole_embedment; 3D geometry',
 'structure_height': 'measurement rooftop_frame_height; rooftop geometry',
 'building_floors': 'rooftop building height in 2D/3D',
 'projection': 'projecting-mount geometry',
 'shutter_height': 'measurement bottom_height (-0.5 ft)',
 'pipe_count': 'measurement pipe_count', 'pipe_length': 'measurement pipe_length',
 'excavation_permission': 'twin checklist pole_excavation_allowed (feasibility review flag)',
 'pole_excavation_allowed': 'feasibility review flag (No)',
 'underground_utilities': 'feasibility review flag (Yes / Not assessed)',
 'electricity_nearby': 'feasibility review flag (No)', 'visible_wires': 'feasibility review flag (Yes)',
 'structure_accessible': 'feasibility review flag (No)', 'fixing_surface_available': 'feasibility review flag (No)',
 'ac_or_obstruction': 'feasibility review flag (Yes)', 'location_approved_by_shop': 'feasibility review flag (No)',
 'area_free_of_obstruction': 'feasibility review flag (No)',
 'pole_configuration_confirmed': 'feasibility review flag (No)',
 'door_opening_clearance': 'feasibility review flag (No)', 'moisture_exposure': 'feasibility review flag (Yes)',
 'power_available': 'conditional parent of power_distance',
 'existing_board': 'conditional parent of remove_existing',
 'panel_count': 'twin checklist glass_panel_count; glass geometry',
}

def vendor_rows():
    out = []
    for s in wb.sheetnames:
        if not (s[:2].isdigit() and 2 <= int(s[:2]) <= 10):
            continue
        ws = wb[s]
        for r in range(5, ws.max_row + 1):
            if ws.cell(r, 7).value in (None, ''):
                continue
            d = (ws.cell(r, 17).value or '')
            out.append(dict(sheet=s, row=r, sno=int(ws.cell(r, 1).value), inst=ws.cell(r, 4).value,
                            cat=ws.cell(r, 6).value, text=ws.cell(r, 7).value,
                            decision='Needed' if d.startswith('Needed') else 'NotNeeded' if d.startswith('Not') else 'Blank',
                            remarks=ws.cell(r, 16).value or ''))
    return out

aud = {}
ws = wb['12_Technical_Audit']
for r in range(5, ws.max_row + 1):
    rid = ws.cell(r, 1).value
    if not rid or str(rid).startswith('OTHER'):
        continue
    aud[(ws.cell(r, 2).value, int(str(rid).split('|')[-1]))] = dict(
        rowid=rid, media=ws.cell(r, 5).value, inst=ws.cell(r, 6).value, orig=ws.cell(r, 7).value,
        canon=ws.cell(r, 8).value, equiv=ws.cell(r, 9).value, src=ws.cell(r, 14).value)

rows = vendor_rows()
by_id = collections.defaultdict(list)
unresolved = []
for v in rows:
    a = aud.get((v['sheet'], v['sno']))
    if a is None:
        unresolved.append(v); v['audit'] = None; continue
    v['audit'] = a
    by_id[a['canon']].append(v)

def id_action(cid):
    vs = by_id[cid]
    dec = {v['decision'] for v in vs}
    green = any((v['sheet'], v['row']) in GREEN for v in vs)
    if green:
        return 'Retain', 'Business override: manually green-highlighted (vendor column says Not Needed)'
    if cid in RETAIN:
        return 'Retain', 'Needed in at least one valid occurrence; kept in every compatible occurrence'
    if cid in MOVE:
        return 'Move', 'Geometry input: shown as Installation Measurements (same key and mirrors)'
    if cid in SAFETY:
        return 'Review', 'Safety check kept in Installation Safety; Not Assessed is never treated as safe'
    if cid in DEPS:
        return 'Review', ('Vendor Not Needed but a feasibility/validation dependency exists; RETAINED in the '
                          'form until business approval: ' + DEPS[cid])
    reviewed = dec - {'Blank'}   # unreviewed NLB Box rows never decide anything
    blank = ' (+ unreviewed NLB Box rows pending)' if 'Blank' in dec else ''
    if reviewed == {'NotNeeded'}:
        return 'Hide', 'Not Needed in every reviewed occurrence; no verified dependency' + blank
    if not reviewed:
        return 'Review', 'Only unreviewed rows: not treated as rejected'
    return 'Review', 'Conflicting vendor decisions'

os.makedirs('docs', exist_ok=True)
with open('docs/question_mapping_rows.csv', 'w', newline='', encoding='utf-8-sig') as f:
    w = csv.writer(f)
    w.writerow(['sheet', 'excel_row', 'sno', 'export_row_id', 'media_code', 'installation_code', 'installation',
                'original_id', 'canonical_id', 'equivalent_ids', 'question_en', 'vendor_decision', 'unreviewed',
                'conflicting_decisions', 'final_action', 'reason', 'dependency', 'source'])
    for v in rows:
        a = v['audit']
        if a is None:
            w.writerow([v['sheet'], v['row'], v['sno'], '', '', '', v['inst'], '', '', '', v['text'], v['decision'],
                        'Yes' if v['decision'] == 'Blank' else '', '', 'Review', 'UNRESOLVED ID (no audit row)', '', ''])
            continue
        cid = a['canon']
        act, why = id_action(cid)
        decs = {x['decision'] for x in by_id[cid]} - {'Blank'}
        w.writerow([v['sheet'], v['row'], v['sno'], a['rowid'], a['media'], a['inst'], v['inst'], a['orig'], cid,
                    a['equiv'], v['text'], v['decision'], 'Yes' if v['decision'] == 'Blank' else '',
                    'Yes' if len(decs) > 1 else '', act, why, DEPS.get(cid, '-'), a['src']])

summ = []
for cid, vs in by_id.items():
    act, why = id_action(cid)
    c = collections.Counter(v['decision'] for v in vs)
    srcs = [f"{v['sheet'][:2]}:{v['inst']}:row{v['row']}" for v in vs]
    summ.append([cid, vs[0]['text'], c['Needed'], c['NotNeeded'], c['Blank'], act, why, DEPS.get(cid, '-'),
                 'Yes' if (c['Needed'] and c['NotNeeded']) else '', '; '.join(srcs)])
hdr = ['canonical_id', 'question_en', 'needed_rows', 'not_needed_rows', 'blank_rows', 'final_action', 'reason',
       'downstream_dependency', 'conflicting_decisions', 'all_source_rows']
with open('docs/question_mapping_report.csv', 'w', newline='', encoding='utf-8-sig') as f:
    w = csv.writer(f); w.writerow(hdr); w.writerows(summ)
cnt = collections.Counter(r[5] for r in summ)
with open('docs/question_mapping_report.md', 'w', encoding='utf-8') as f:
    f.write('# Question mapping report (Recce-form.xlsx -> active vendor policy)\n\n')
    f.write(f"Source rows mapped: {len(rows)} (unresolved IDs: {len(unresolved)}). Canonical ids: {len(summ)}. "
            + ' | '.join(f'{k}: {v}' for k, v in sorted(cnt.items())) + '\n\n')
    conf = [r[0] for r in summ if r[8]]
    f.write('Conflicting vendor decisions (same canonical id Needed AND Not Needed): ' + ', '.join(conf) + '\n\n')
    f.write('Every one of the 483 rows is listed in `question_mapping_rows.csv`. Blank (unreviewed) rows '
            f"= {sum(1 for v in rows if v['decision']=='Blank')} (all of 05_NLB_Box) and are never treated as rejected.\n\n")
    f.write('| ' + ' | '.join(hdr) + ' |\n|' + '---|' * len(hdr) + '\n')
    for r in summ:
        f.write('| ' + ' | '.join(str(x).replace('|', '/') for x in r) + ' |\n')
print('rows', len(rows), 'unresolved', len(unresolved), 'ids', len(summ), dict(cnt))
