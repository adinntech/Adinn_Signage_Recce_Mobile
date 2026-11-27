# Standalone export script (NOT part of the app). Reads build/export/questions.json
# (produced by tool/export/dump_questions_test.dart from the live catalog) and
# writes build/export/Recce_Site_Questions_Vendor_Review.xlsx.
#   python -I tool/export/build_vendor_excel.py
import json, math, re, sys, os
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter as L
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.formatting.rule import FormulaRule

ROOT = os.getcwd()
D = json.load(open(os.path.join(ROOT, 'build/export/questions.json'), encoding='utf8'))
OUT = os.path.join(ROOT, 'build/export/Recce_Site_Questions_Vendor_Review.xlsx')

# ----------------------------------------------------------------- translations
MEDIA_TA = {
 'GSB_SINGLE': 'GSB ஒரு பக்கம் (ஒளிரும் பலகை – ஒற்றைப் பக்கம்)',
 'GSB_DOUBLE': 'GSB இரு பக்கம் (ஒளிரும் பலகை – இரட்டைப் பக்கம்)',
 'NLB_SINGLE_FRAME': 'NLB சிங்கிள் ஃபிரேம் (ஒளியில்லா பலகை)',
 'NLB_BOX_FRAME': 'NLB பாக்ஸ் ஃபிரேம் (ஒளியில்லா பலகை)',
 'FOAM_VINYL': 'ஃபோம் வினைல் (ஃபோம் போர்டில் வினைல்)',
 'ACRYLIC': 'அக்ரிலிக் (தெளிவான அக்ரிலிக்)',
 'OWV': 'ஒன்-வே விஷன் (கண்ணாடிப் படலம்)',
 'PLAIN_VINYL': 'பிளெய்ன் வினைல்',
 'MDF': 'MDF பலகை',
}
INST_TA = {
 'Shop Fascia': 'கடை முகப்பு (Shop Fascia)',
 'Wall Mount': 'சுவரில் பொருத்துதல் (Wall Mount)',
 'Double Pole': 'இரட்டை கம்பம் (Double Pole)',
 'Single Pole': 'ஒற்றை கம்பம் (Single Pole)',
 'Rooftop': 'மொட்டை மாடி / கூரை மேல் (Rooftop)',
 'Support Pipe': 'சப்போர்ட் பைப் (Support Pipe)',
 'Projecting Mount': 'சுவரிலிருந்து வெளியே நீட்டிய அமைப்பு (Projecting Mount)',
 'Direct on Wall': 'நேரடியாகச் சுவரில் (Direct on Wall)',
 'Glass / Shutter Pasting': 'கண்ணாடி / ஷட்டரில் ஒட்டுதல் (Glass / Shutter Pasting)',
 '(none configured)': 'அமைக்கப்படவில்லை (No installation type configured)',
}
Q_TA = {
 'Is there an existing board at this location?': 'இந்த இடத்தில் ஏற்கனவே பலகை உள்ளதா?',
 'Existing board removal required?': 'ஏற்கனவே உள்ள பலகையை அகற்ற வேண்டுமா?',
 'Access method for installation': 'பொருத்துவதற்கான அணுகு முறை (Access method)',
 'Shop owner permission obtained?': 'கடை உரிமையாளரின் அனுமதி பெறப்பட்டதா?',
 'Electrical point available within 10 ft?': '10 அடி தூரத்திற்குள் மின்சார இணைப்புப் புள்ளி உள்ளதா?',
 'Distance to nearest power point': 'அருகிலுள்ள மின்சாரப் புள்ளிக்கான தூரம்',
 'Illumination type': 'ஒளியூட்டும் வகை',
 'Timer switch required?': 'டைமர் ஸ்விட்ச் தேவையா?',
 'Front focus lights required?': 'முன்புற ஃபோகஸ் விளக்குகள் தேவையா?',
 'Frame material': 'ஃபிரேம் பொருள்',
 'Mounting surface': 'பொருத்தும் மேற்பரப்பு',
 'Indoor / Outdoor': 'உட்புறம் / வெளிப்புறம்',
 'Standoff (spacer) mounting?': 'ஸ்டாண்ட்ஆஃப் (இடைவெளி போல்ட்) மூலம் பொருத்துவதா?',
 'Graphics': 'கிராஃபிக்ஸ் வகை',
 'Glass clean and dry?': 'கண்ணாடி சுத்தமாகவும் உலர்ந்தும் உள்ளதா?',
 'Pasting surface': 'ஒட்டும் மேற்பரப்பு',
 'Surface clean and dry?': 'மேற்பரப்பு சுத்தமாகவும் உலர்ந்தும் உள்ளதா?',
 'Board bottom height from ground': 'தரையிலிருந்து பலகையின் அடிப்பகுதி உயரம்',
 'Number of support pipes': 'சப்போர்ட் பைப்புகளின் எண்ணிக்கை',
 'Support pipe length': 'சப்போர்ட் பைப் நீளம்',
 'Fascia material': 'முகப்பு (Fascia) பொருள்',
 'Shutter top height from ground': 'தரையிலிருந்து ஷட்டரின் மேல்பகுதி உயரம்',
 'Clear of neighbouring boards?': 'அருகிலுள்ள பலகைகளுக்கு இடையூறு இல்லாமல் உள்ளதா?',
 'Wall type': 'சுவர் வகை',
 'Wall condition': 'சுவரின் நிலை',
 'Clear height below board (pole height)': 'பலகைக்குக் கீழ் உள்ள இடைவெளி உயரம் (கம்ப உயரம்)',
 'Distance between poles': 'கம்பங்களுக்கு இடையிலான தூரம்',
 'Ground type at pole location': 'கம்பம் நிறுத்தும் இடத்தின் தரை வகை',
 'Foundation pit depth possible': 'அடித்தளக் குழியை எவ்வளவு ஆழம் தோண்ட முடியும்',
 'Pole material': 'கம்பப் பொருள்',
 'Excavation permission available?': 'தோண்டுவதற்கான அனுமதி உள்ளதா?',
 'Pole diameter': 'கம்பத்தின் விட்டம்',
 'Number of floors (incl. ground)': 'மாடிகளின் எண்ணிக்கை (தரைத்தளம் உட்பட)',
 'Roof type': 'கூரை வகை',
 'Structure height above roof': 'கூரைக்கு மேல் அமைப்பின் உயரம்',
 'Terrace access available?': 'மொட்டை மாடிக்குச் செல்லும் வழி உள்ளதா?',
 'Wind exposure': 'காற்றின் தாக்கம்',
 'Building owner NOC available?': 'கட்டிட உரிமையாளரின் NOC (தடையில்லாச் சான்று) உள்ளதா?',
 'Projection from wall': 'சுவரிலிருந்து நீட்டிப்பு தூரம்',
 'Artwork bottom height from ground': 'தரையிலிருந்து டிசைனின் அடிப்பகுதி உயரம்',
 'Wall free of pipes / wires / obstructions?': 'சுவரில் பைப் / வயர் / தடைகள் எதுவும் இல்லையா?',
 'Number of glass / shutter panels': 'கண்ணாடி / ஷட்டர் பேனல்களின் எண்ணிக்கை',
 'Is the proposed wall / structure accessible?': 'முன்மொழியப்பட்ட சுவர் / அமைப்பை அணுக முடியுமா?',
 'Is a suitable fixing surface available?': 'பொருத்துவதற்குப் பொருத்தமான மேற்பரப்பு உள்ளதா?',
 'Is electricity available nearby?': 'அருகில் மின்சாரம் கிடைக்குமா?',
 'Is there an existing electrical point?': 'ஏற்கனவே மின்சார இணைப்புப் புள்ளி உள்ளதா?',
 'Is the installation height measured?': 'பொருத்தும் உயரம் அளக்கப்பட்டதா?',
 'Are there visible electrical wires near the board area?': 'பலகை இடத்தருகே தெரியும் மின்கம்பிகள் உள்ளதா?',
 'Is there any AC unit or other obstruction?': 'AC யூனிட் அல்லது வேறு தடை ஏதேனும் உள்ளதா?',
 'Is night visibility relevant?': 'இரவு நேரத் தெரிவுநிலை முக்கியமா?',
 'Is additional access equipment likely to be required?': 'கூடுதல் அணுகு உபகரணம் தேவைப்பட வாய்ப்புள்ளதா?',
 'Is the proposed location approved by the shop representative?': 'முன்மொழியப்பட்ட இடத்தைக் கடை பிரதிநிதி ஒப்புக்கொண்டாரா?',
 'Ground condition at pole location': 'கம்பம் நிறுத்தும் இடத்தின் தரை நிலை',
 'Any underground cables / pipes suspected at pole location?': 'கம்பம் நிறுத்தும் இடத்தில் நிலத்தடி கேபிள் / குழாய்கள் இருக்க வாய்ப்புள்ளதா?',
 'Is excavation for the pole footing permitted?': 'கம்ப அடித்தளத்திற்குத் தோண்ட அனுமதி உள்ளதா?',
 'Additional site remarks': 'கூடுதல் தளக் குறிப்புகள்',
 'Wall / structure type': 'சுவர் / அமைப்பு வகை',
 'Fixing surface condition': 'பொருத்தும் மேற்பரப்பின் நிலை',
 'Is the board area free of obstructions?': 'பலகை பொருத்தும் இடத்தில் தடைகள் இல்லையா?',
 'Are support pipes required?': 'சப்போர்ட் பைப்புகள் தேவையா?',
 'Is the pole configuration confirmed on site?': 'கம்ப அமைப்பு தளத்தில் உறுதி செய்யப்பட்டதா?',
 'Access requirement for installation': 'பொருத்துவதற்கான அணுகு தேவை (Access requirement)',
 'Are the glass panel dimensions measured?': 'கண்ணாடி பேனல் அளவுகள் அளக்கப்பட்டதா?',
 'Number of panels': 'பேனல்களின் எண்ணிக்கை',
 'Glass condition': 'கண்ணாடியின் நிலை',
 'Is there clearance for door opening?': 'கதவு திறக்க இடைவெளி உள்ளதா?',
 'Are there existing stickers to remove?': 'அகற்ற வேண்டிய பழைய ஸ்டிக்கர்கள் உள்ளதா?',
 'Panel divisions (frames / joints)': 'பேனல் பிரிவுகள் (ஃபிரேம்கள் / இணைப்புகள்)',
 'Visibility requirement': 'தெரிவுநிலைத் தேவை',
 'Surface type': 'மேற்பரப்பு வகை',
 'Is the surface exposed to moisture?': 'மேற்பரப்பு ஈரப்பதத்திற்கு உள்ளாகிறதா?',
}
OPT_TA = {
 'Ladder': 'ஏணி', 'Scaffolding': 'சாரம் (Scaffolding)', 'Crane / Hydra': 'கிரேன் / ஹைட்ரா',
 'Direct reach': 'நேரடியாக எட்டலாம்', 'LED modules': 'LED மாட்யூல்கள்', 'LED strip': 'LED ஸ்ட்ரிப்',
 'Tube lights': 'டியூப் லைட்', 'MS square tube': 'MS சதுரக் குழாய்', 'Aluminium': 'அலுமினியம்',
 'Wooden': 'மரம்', 'Wall': 'சுவர்', 'Glass': 'கண்ணாடி', 'Door': 'கதவு', 'Shutter': 'ஷட்டர்',
 'Rolling shutter': 'ரோலிங் ஷட்டர்', 'Indoor': 'உட்புறம்', 'Outdoor': 'வெளிப்புறம்',
 'Reverse printed': 'பின்புறம் அச்சிடப்பட்டது', 'Vinyl applied': 'வினைல் ஒட்டப்பட்டது',
 'Plain / etched': 'சாதாரணம் / பொறிக்கப்பட்டது', 'Concrete': 'கான்கிரீட்', 'Brick': 'செங்கல்',
 'Metal sheet': 'உலோகத் தகடு', 'Stone': 'கல்', 'Good': 'நல்ல நிலை', 'Average': 'சுமாரான நிலை',
 'Poor': 'மோசமான நிலை', 'MS pipe': 'MS குழாய்', 'GI pipe': 'GI குழாய்', 'MS channel': 'MS சேனல்',
 '4 inch': '4 அங்குலம்', '6 inch': '6 அங்குலம்', '8 inch': '8 அங்குலம்', 'Soil': 'மண்',
 'Tar road': 'தார் சாலை', 'Footpath tiles': 'நடைபாதை டைல்ஸ்', 'RCC slab': 'RCC தளம்',
 'Tiles': 'ஓடுகள்', 'Low': 'குறைவு', 'Medium': 'நடுத்தரம்', 'High': 'அதிகம்', 'Other': 'மற்றவை',
 'Scratched': 'கீறல் உள்ளது', 'Cracked': 'விரிசல் உள்ளது',
 'See-through from inside (one-way)': 'உள்ளிருந்து வெளியே தெரியும் (ஒன்-வே)',
 'Fully opaque': 'முழுவதும் ஒளிபுகாதது', 'Frosted / privacy': 'ஃபிராஸ்டட் / தனியுரிமை',
 'Painted wall': 'பெயிண்ட் அடித்த சுவர்', 'Plastered': 'பூச்சு பூசிய சுவர்',
}
UNIT_TA = {'ft': 'ft (அடி)', 'in': 'in (அங்குலம்)'}
YES = 'Yes / ஆம்'; NO = 'No / இல்லை'; NA = 'Not Applicable / பொருந்தாது'
REQ = 'Required / தேவை'; OPT = 'Optional / விருப்பம்'
NEEDED = 'Needed in App / செயலியில் தேவை'
NOTNEEDED = 'Not Needed in App / செயலியில் தேவையில்லை'

# ----------------------------------------------------------------- source lines
def line_index(path):
    idx = {}
    for i, ln in enumerate(open(os.path.join(ROOT, path), encoding='utf8'), 1):
        m = re.search(r"\bid:\s*['\"](\w+)['\"]", ln)
        if m:
            idx.setdefault(m.group(1), []).append(i)
    return idx
CAT_LINES = line_index('lib/data/catalog/signage_catalog.dart')
CL_LINES = line_index('lib/data/catalog/site_checklists.dart')

def src_ref(kind, qid):
    if kind == 'site':
        return 'lib/data/catalog/signage_catalog.dart:' + ','.join(map(str, CAT_LINES.get(qid, ['?'])))
    return 'lib/data/catalog/site_checklists.dart:' + ','.join(map(str, CL_LINES.get(qid, ['?'])))

# downstream dependency knowledge (read from source; see Technical Audit notes)
GEOMETRY_IDS = {'building_floors', 'pole_height', 'mount_height', 'panel_bottom_height',
                'shutter_height', 'structure_height', 'pole_gap', 'projection', 'letter_height',
                'panel_count', 'foundation_depth', 'acp_colour', 'base_width', 'base_depth',
                'support_structure', 'overall_height'}
MIRRORS = {'mount_height': 'bottom_height', 'pole_height': 'bottom_height',
           'panel_bottom_height': 'bottom_height', 'pole_gap': 'pole_spacing',
           'foundation_depth': 'pole_embedment', 'base_width': 'base_width',
           'base_depth': 'base_depth', 'overall_height': 'standee_overall_height',
           'structure_height': 'rooftop_frame_height', 'pipe_length': 'pipe_length',
           'pipe_count': 'pipe_count', 'shutter_height': 'bottom_height (minus 0.5 ft)'}
COND_PARENT = {'existing_board': 'remove_existing', 'power_available': 'power_distance'}

# ----------------------------------------------------------------- row building
def ans_info(q, source):
    """-> (type_label, opts_en list, opts_ta list, unit, kind) kind: yn|yna|list|num|text"""
    t = q['type']
    if source == 'site':
        if t == 'yesNo':
            return 'Yes/No', ['Yes', 'No'], [YES, NO], None, 'yn'
        if t == 'choice':
            return 'Single choice (tap one option)', q['options'], q['options'], None, 'list'
        if t == 'number':
            return 'Numeric', [], [], q['unit'], 'num'
        return 'Text', [], [], None, 'text'
    if t == 'yesNoNa':
        if q['allowNa']:
            return 'Yes/No/Not Applicable', ['Yes', 'No', 'Not Applicable'], [YES, NO, NA], None, 'yna'
        return 'Yes/No', ['Yes', 'No'], [YES, NO], None, 'yn'
    if t == 'dropdown':
        opts = list(q['options']) + (['Not applicable'] if q['allowNa'] else [])
        return 'Dropdown (select one)', opts, opts, None, 'list'
    if t == 'numeric':
        return 'Numeric', [], [], q['unit'], 'num'
    if t == 'shortText':
        return 'Text (short)', [], [], None, 'text'
    if t == 'longText':
        return 'Text (long, free text)', [], [], None, 'text'
    return 'Photo evidence', [], [], None, 'text'

def tr_opt(o):
    return OPT_TA.get(o, 'பொருந்தாது (Not applicable)' if o == 'Not applicable' else o)

def build_rows():
    rows = []  # dicts
    for c in D['combos']:
        if c['installationName'] == 'Hanging Mount':
            continue  # presentation-only card: never saved, no questions behind it
        mapped = c['mapped']  # checklist id -> site id
        site_by_id = {q['id']: q for q in c['site']}
        inst_en = c['installationName']
        none_inst = c['installationCode'] is None
        items = []
        for q in c['site']:
            cat = {'Installation-Specific Questions': 'Installation',
                   'Media-Specific Questions': 'Media'}.get(q['section'], 'Common')
            items.append(('site', q, cat))
        for q in c['checklist']:
            if q['id'] in mapped or q['id'] == 'site_evidence_photo':
                continue
            if q['id'] == 'checklist_remarks':
                cat = 'Additional Site Remarks'
            elif q['installations'] is not None:
                cat = 'Installation'
            else:
                cat = 'Media'
            items.append(('checklist', q, cat))
        for src, q, cat in items:
            text = q['label'] if src == 'site' else q['text']
            tl, oen, ota, unit, kind = ans_info(q, src)
            cond_en = cond_ta = None
            if src == 'site' and q['showIfId']:
                parent = site_by_id[q['showIfId']]['label']
                val = 'Yes' if q['showIfValue'] is True else 'No' if q['showIfValue'] is False else str(q['showIfValue'])
                cond_en = f"Shown only when \"{parent}\" = {val}"
                cond_ta = f"\"{Q_TA[parent]}\" என்பதற்கு \"{'ஆம்' if val == 'Yes' else 'இல்லை'}\" என்றால் மட்டும் காட்டப்படும்"
            req_flag = bool(q['required'])
            rows.append(dict(
                option=c['optionKey'], media_code=c['mediaCode'], media_en=c['optionLabel'],
                media_ta=MEDIA_TA[c['optionKey']], inst_code=c['installationCode'],
                inst_en=inst_en, inst_ta=INST_TA[inst_en], category=cat, source=src, q=q,
                text=text, text_ta=Q_TA[text], type_label=tl, opts_en=oen, opts_ta=ota,
                unit=unit, kind=kind,
                req=(REQ if req_flag else OPT) + (' (when shown) / (காட்டப்பட்டால்)' if (req_flag and cond_en) else ''),
                req_flag=req_flag,
                cond=(f"{cond_en}\n{cond_ta}" if cond_en else 'Always shown / எப்போதும் காட்டப்படும்'),
                cond_en=cond_en, none_inst=none_inst,
                equiv=[k for k, v in mapped.items() if v == q['id']] if src == 'site' else [],
            ))
    return rows

ROWS = build_rows()
SHEETS = [('GSB_SINGLE', '02_GSB_Single'), ('GSB_DOUBLE', '03_GSB_Double'), ('NLB_SINGLE_FRAME', '04_NLB_Single'),
          ('NLB_BOX_FRAME', '05_NLB_Box'), ('FOAM_VINYL', '06_Foam_Vinyl'), ('ACRYLIC', '07_Acrylic'),
          ('OWV', '08_One_Way_Vision'), ('PLAIN_VINYL', '09_Plain_Vinyl'), ('MDF', '10_MDF')]
active_keys = [m for m in ({r['option'] for r in ROWS})]
assert {k for k, _ in SHEETS} == {o for o in [c['optionKey'] for c in D['combos']]}, 'media option mismatch'

# ----------------------------------------------------------------- styling
RED = 'C8102E'; DARK = '7A0A1C'; GREY = 'F2F2F2'; MID = 'D9D9D9'; EDIT = 'FFF8E1'; WHITE = 'FFFFFF'
FONT = 'Nirmala UI'
f_norm = Font(name=FONT, size=10)
f_bold = Font(name=FONT, size=10, bold=True)
f_hdr = Font(name=FONT, size=10, bold=True, color=WHITE)
f_title = Font(name=FONT, size=15, bold=True, color=RED)
thin = Side(style='thin', color='BFBFBF'); thick = Side(style='medium', color=RED)
box = Border(left=thin, right=thin, top=thin, bottom=thin)
wrap = Alignment(wrap_text=True, vertical='top')
center = Alignment(wrap_text=True, vertical='center', horizontal='center')
fill = lambda c: PatternFill('solid', start_color=c, end_color=c)

HEAD = [
 ('S.No\nவ.எண்', 6), ('Media Type – English\nமீடியா வகை – ஆங்கிலம்', 18), ('Media Type – Tamil\nமீடியா வகை – தமிழ்', 24),
 ('Installation Type – English\nபொருத்தும் வகை – ஆங்கிலம்', 20), ('Installation Type – Tamil\nபொருத்தும் வகை – தமிழ்', 26),
 ('Question Category\nகேள்வி வகை', 15), ('Question – English\nகேள்வி – ஆங்கிலம்', 44), ('Question – Tamil\nகேள்வி – தமிழ்', 46),
 ('Answer Type\nபதில் வகை', 18), ('Answer Options – English\nபதில் விருப்பங்கள் – ஆங்கிலம்', 26),
 ('Answer Options – Tamil\nபதில் விருப்பங்கள் – தமிழ்', 30), ('Measurement Unit\nஅளவு அலகு', 13),
 ('Requirement\nதேவை நிலை', 16), ('Display Condition\nகாட்டப்படும் நிபந்தனை', 40),
 ('Sample Answer (Optional)\nமாதிரி பதில் (விருப்பம்)', 28), ('Vendor Remarks\nவிற்பனையாளர் கருத்துகள்', 34),
 ('App Requirement – Vendor Decision\nசெயலி தேவை – விற்பனையாளர் முடிவு', 34),
]
READONLY_COLS = range(1, 15)  # A..N

def est_lines(text, width):
    if text is None: return 1
    n = 0
    for part in str(text).split('\n'):
        n += max(1, math.ceil(len(part) * 1.12 / max(width - 1, 1)))
    return n

def setup_decision_cf(ws, col, r1, r2):
    rng = f'{col}{r1}:{col}{r2}'
    ws.conditional_formatting.add(rng, FormulaRule(formula=[f'LEFT(${col}{r1},6)="Needed"'], fill=fill('C6EFCE'), stopIfTrue=True))
    ws.conditional_formatting.add(rng, FormulaRule(formula=[f'LEFT(${col}{r1},3)="Not"'], fill=fill('FFC7CE'), stopIfTrue=True))
    ws.conditional_formatting.add(rng, FormulaRule(formula=[f'${col}{r1}=""'], fill=fill('FFF2CC')))

DEC_LIST = f'"{NEEDED},{NOTNEEDED}"'
assert len(DEC_LIST) < 255

def decision_dv(ws, rng):
    dv = DataValidation(type='list', formula1=DEC_LIST, allow_blank=True, showErrorMessage=True,
                        errorTitle='Select from list', error='Please choose Needed in App or Not Needed in App.',
                        promptTitle='Vendor decision / முடிவு', prompt='Choose from the list. / பட்டியலில் இருந்து தேர்வு செய்யவும்.',
                        showInputMessage=True)
    ws.add_data_validation(dv); dv.add(rng)

def list_dv(ws, cell, items):
    f = '"' + ','.join(items) + '"'
    if len(f) > 255:
        return False
    dv = DataValidation(type='list', formula1=f, allow_blank=True, showErrorMessage=True,
                        errorTitle='Select from list', error='Please choose one of the listed answers.')
    ws.add_data_validation(dv); dv.add(cell)
    return True

wb = Workbook()
wb.remove(wb.active)

# ----------------------------------------------------------------- 00 instructions
ws = wb.create_sheet('00_Instructions')
ws.sheet_view.showGridLines = False
ws.column_dimensions['A'].width = 4; ws.column_dimensions['B'].width = 70; ws.column_dimensions['C'].width = 70
ws['B1'] = 'Adinn Signage Recce – Site Questions Vendor Review'; ws['B1'].font = f_title
ws['B2'] = 'அடின் சைனேஜ் ரெக்கி – தளக் கேள்விகள் விற்பனையாளர் மதிப்பாய்வு'; ws['B2'].font = Font(name=FONT, size=12, bold=True, color=DARK)
inst_rows = [
 ('Purpose', 'This workbook lists every Site Question currently asked in the Recce app, by media type and installation type. Please tell us which questions are needed, not needed, or missing.',
  'இந்த ஒர்க்புக்கில் ரெக்கி செயலியில் தற்போது கேட்கப்படும் அனைத்து தளக் கேள்விகளும் மீடியா வகை மற்றும் பொருத்தும் வகைப்படி உள்ளன. எந்தக் கேள்விகள் தேவை, தேவையில்லை, அல்லது விடுபட்டுள்ளன என்பதைத் தெரிவிக்கவும்.'),
 ('Step 1', 'Open the sheet of the media type you work with (02 to 10).', 'நீங்கள் பணிபுரியும் மீடியா வகையின் ஷீட்டைத் திறக்கவும் (02 முதல் 10 வரை).'),
 ('Step 2', 'For every row choose the LAST column: "Needed in App" or "Not Needed in App". Leave it empty only if you have not reviewed the row.',
  'ஒவ்வொரு வரிக்கும் கடைசி நெடுவரிசையில் "செயலியில் தேவை" அல்லது "செயலியில் தேவையில்லை" என்பதைத் தேர்வு செய்யவும். பார்க்காத வரிகளை காலியாக விடவும்.'),
 ('Step 3', 'Write corrections or comments in "Vendor Remarks". "Sample Answer" is optional and only for your own testing of the answer format.',
  'திருத்தங்கள் அல்லது கருத்துகளை "விற்பனையாளர் கருத்துகள்" நெடுவரிசையில் எழுதவும். "மாதிரி பதில்" விருப்பமானது; பதில் வடிவத்தைச் சோதிக்க மட்டுமே.'),
 ('Step 4', 'If a question is missing, add it in sheet 11_New_Questions.', 'ஒரு கேள்வி விடுபட்டிருந்தால் 11_New_Questions ஷீட்டில் சேர்க்கவும்.'),
 ('Colours', 'Grey cells = read-only information from the app. Light yellow cells = please fill. Decision cell turns green (Needed) or red (Not Needed); yellow means not reviewed yet.',
  'சாம்பல் நிறக் கட்டங்கள் = செயலியிலிருந்து வந்த தகவல் (மாற்ற வேண்டாம்). வெளிர் மஞ்சள் கட்டங்கள் = நீங்கள் நிரப்பவும். "தேவை" என்றால் பச்சை, "தேவையில்லை" என்றால் சிவப்பு, மஞ்சள் = இன்னும் பார்க்கவில்லை.'),
 ('Conditional questions', 'Some questions appear only after another answer (see "Display Condition"). Example: "Distance to nearest power point" appears only when "Electrical point available within 10 ft?" = No.',
  'சில கேள்விகள் வேறொரு பதிலுக்குப் பிறகு மட்டுமே தோன்றும் ("காட்டப்படும் நிபந்தனை" பார்க்கவும்). எ.கா: "10 அடிக்குள் மின்சார இணைப்புப் புள்ளி உள்ளதா?" என்பதற்கு "இல்லை" என்றால் மட்டுமே "அருகிலுள்ள மின்சாரப் புள்ளிக்கான தூரம்" தோன்றும்.'),
 ('Answer formats', 'Answer formats are exactly as in the app: Yes/No, Yes/No/Not Applicable, single choice / dropdown (select ONE option), numeric (with unit) and free text. The app has NO multiple-selection question; if you need one, write it in Vendor Remarks.',
  'பதில் வடிவங்கள் செயலியில் உள்ளபடியே: ஆம்/இல்லை, ஆம்/இல்லை/பொருந்தாது, ஒற்றைத் தேர்வு / டிராப்டவுன் (ஒரே ஒரு விருப்பம்), எண் (அலகுடன்), மற்றும் சுதந்திர உரை. செயலியில் பல தேர்வு கேள்வி இல்லை; தேவைப்பட்டால் கருத்துகளில் எழுதவும்.'),
 ('Same question on many rows', 'A common question (for example "Access method") is repeated for each installation type because the app asks it for every combination. It is never repeated twice inside one combination. Questions that mean the same in the Site Questions and the checklist are shown once.',
  'பொதுவான கேள்வி (எ.கா. "Access method") ஒவ்வொரு பொருத்தும் வகைக்கும் மீண்டும் வரும்; ஏனெனில் செயலி ஒவ்வொரு சேர்க்கைக்கும் அதைக் கேட்கிறது. ஒரே சேர்க்கைக்குள் ஒரே கேள்வி இரண்டு முறை வராது.'),
 ('Not listed on purpose', 'Hanging Mount (GSB Double Side) is shown as a card in the app but cannot be saved yet, so it has no questions. MDF has no approved installation type yet, so only the common questions are listed. Photo evidence selection is handled in the Site Photos step and is not listed.',
  'Hanging Mount (GSB Double Side) செயலியில் காட்டப்படுகிறது ஆனால் இன்னும் சேமிக்க முடியாது; அதற்குக் கேள்விகள் இல்லை. MDF-க்கு இன்னும் அங்கீகரிக்கப்பட்ட பொருத்தும் வகை இல்லை; பொதுவான கேள்விகள் மட்டுமே உள்ளன.'),
 ('Important', 'Your decisions are recommendations only. Nothing in this file changes the app automatically.',
  'உங்கள் முடிவுகள் பரிந்துரைகள் மட்டுமே. இந்த கோப்பு செயலியை தானாக மாற்றாது.'),
]
r = 4
for h, en, ta in inst_rows:
    ws.cell(r, 2, f'{h}\n{en}'); ws.cell(r, 3, ta)
    ws.cell(r, 2).font = f_norm; ws.cell(r, 3).font = f_norm
    ws.cell(r, 2).alignment = wrap; ws.cell(r, 3).alignment = wrap
    ws.cell(r, 2).fill = fill(GREY); ws.cell(r, 3).fill = fill(GREY)
    ws.cell(r, 2).border = box; ws.cell(r, 3).border = box
    ws.row_dimensions[r].height = 15 * max(est_lines(en, 70) + 1, est_lines(ta, 70)) + 6
    r += 1
ws['B3'] = 'English'; ws['C3'] = 'தமிழ்'
for c in ('B3', 'C3'):
    ws[c].font = f_hdr; ws[c].fill = fill(RED); ws[c].alignment = center

# ----------------------------------------------------------------- media sheets
by_opt = {}
for row in ROWS:
    by_opt.setdefault(row['option'], []).append(row)

sheet_info = {}  # sheet -> (first,last, installs, rows)
audit = []
for key, sname in SHEETS:
    rows = by_opt[key]
    ws = wb.create_sheet(sname)
    label = rows[0]['media_en']
    ws['A1'] = f'{label}  –  Site Questions for vendor review'; ws['A1'].font = f_title
    ws['A2'] = ('Read-only columns A–N come from the app. Please fill the yellow columns O–Q (Q = your decision).  |  '
                'A–N செயலியிலிருந்து வந்தவை (மாற்ற வேண்டாம்). மஞ்சள் நெடுவரிசைகள் O–Q நிரப்பவும் (Q = உங்கள் முடிவு).')
    ws['A2'].font = Font(name=FONT, size=9, italic=True, color='595959')
    for ci in range(1, 18):
        c = ws.cell(3, ci)
        c.fill = fill(MID if ci <= 14 else 'FFE082')
        c.font = Font(name=FONT, size=9, bold=True, color='404040')
        c.alignment = center
    ws.cell(3, 1, 'READ-ONLY – from the app / செயலியிலிருந்து'); ws.merge_cells('A3:N3')
    ws.cell(3, 15, 'VENDOR INPUT / விற்பனையாளர் உள்ளீடு'); ws.merge_cells('O3:Q3')
    for ci, (h, w) in enumerate(HEAD, 1):
        c = ws.cell(4, ci, h); c.font = f_hdr; c.fill = fill(RED if ci <= 14 else DARK)
        c.alignment = center; c.border = box
        ws.column_dimensions[L(ci)].width = w
    ws.row_dimensions[4].height = 46
    r = 5
    prev_inst = None
    block = 0
    for n, row in enumerate(rows, 1):
        if row['inst_en'] != prev_inst:
            block += 1; prev_inst = row['inst_en']; first_of_block = True
        else:
            first_of_block = False
        vals = [n, row['media_en'], row['media_ta'], row['inst_en'], row['inst_ta'], row['category'],
                row['text'], row['text_ta'], row['type_label'],
                '\n'.join(row['opts_en']) if row['opts_en'] else '—',
                '\n'.join(tr_opt(o) if row['source'] == 'checklist' or row['kind'] == 'list' else o
                          for o in (row['opts_ta'] if row['kind'] in ('yn', 'yna') else row['opts_en'])) if row['opts_en'] else '—',
                UNIT_TA.get(row['unit'], row['unit']) if row['unit'] else '—',
                row['req'], row['cond'], None, None, None]
        # Tamil options: yes/no kinds already carry Tamil; lists use tr_opt
        if row['kind'] == 'list':
            vals[10] = '\n'.join(tr_opt(o) for o in row['opts_en'])
        elif row['kind'] in ('yn', 'yna'):
            vals[10] = '\n'.join(row['opts_ta'])
        for ci, v in enumerate(vals, 1):
            c = ws.cell(r, ci, v); c.font = f_norm; c.alignment = wrap; c.border = box
            if ci <= 14: c.fill = fill(GREY if block % 2 else 'FAFAFA')
            else: c.fill = fill(EDIT)
            if first_of_block:
                c.border = Border(left=thin, right=thin, bottom=thin, top=thick)
        ws.cell(r, 1).alignment = center
        lines = max(est_lines(vals[6], HEAD[6][1]), est_lines(vals[7], HEAD[7][1]), est_lines(vals[9], HEAD[9][1]),
                    est_lines(vals[10], HEAD[10][1]), est_lines(vals[13], HEAD[13][1]), est_lines(vals[2], HEAD[2][1]),
                    est_lines(vals[4], HEAD[4][1]), est_lines(vals[12], HEAD[12][1]))
        ws.row_dimensions[r].height = min(max(30, 14 * lines + 6), 200)
        # sample-answer validation
        cell = f'O{r}'
        k = row['kind']
        if k == 'yn': list_dv(ws, cell, [YES, NO])
        elif k == 'yna': list_dv(ws, cell, [YES, NO, NA])
        elif k == 'list':
            opts = [f'{o} / {tr_opt(o)}' for o in row['opts_en']]
            if not list_dv(ws, cell, opts):
                list_dv(ws, cell, row['opts_en'])
        elif k == 'num':
            dv = DataValidation(type='decimal', operator='greaterThanOrEqual', formula1='0', allow_blank=True,
                                showErrorMessage=True, errorTitle='Number only', error='Enter a number (' + (row['unit'] or '') + ').')
            ws.add_data_validation(dv); dv.add(cell)
        audit.append((sname, n, row))
        r += 1
    last = r - 1
    decision_dv(ws, f'Q5:Q{last}')
    setup_decision_cf(ws, 'Q', 5, last)
    ws.freeze_panes = 'D5'
    ws.auto_filter.ref = f'A4:Q{last}'
    ws.sheet_properties.tabColor = RED
    ws.page_setup.orientation = 'landscape'; ws.page_setup.fitToWidth = 1; ws.page_setup.fitToHeight = 0
    ws.sheet_properties.pageSetUpPr.fitToPage = True
    ws.print_title_rows = '4:4'
    sheet_info[sname] = (5, last, len({x['inst_en'] for x in rows}), rows)

# ----------------------------------------------------------------- 11 new questions
ws = wb.create_sheet('11_New_Questions')
ws['A1'] = 'New / Missing Questions suggested by the vendor'; ws['A1'].font = f_title
ws['A2'] = 'Suggest questions that the app does not ask today. Yellow cells are for you.  |  செயலியில் தற்போது இல்லாத கேள்விகளை இங்கே பரிந்துரைக்கவும். மஞ்சள் கட்டங்களை நிரப்பவும்.'
ws['A2'].font = Font(name=FONT, size=9, italic=True, color='595959')
NH = [('S.No\nவ.எண்', 6), ('Media Type\nமீடியா வகை', 24), ('Installation Type\nபொருத்தும் வகை', 26),
      ('New Question – English\nபுதிய கேள்வி – ஆங்கிலம்', 46), ('New Question – Tamil\nபுதிய கேள்வி – தமிழ்', 46),
      ('Expected Answer Type\nஎதிர்பார்க்கும் பதில் வகை', 22), ('Suggested Answer Options\nபரிந்துரைக்கும் பதில் விருப்பங்கள்', 32),
      ('Measurement Unit\nஅளவு அலகு', 14), ('Reason for Adding\nசேர்க்கும் காரணம்', 36),
      ('Required / Optional recommendation\nதேவை / விருப்பம் பரிந்துரை', 22), ('Vendor Remarks\nவிற்பனையாளர் கருத்துகள்', 30),
      ('Needed in App / Not Needed in App\nசெயலியில் தேவை / தேவையில்லை', 34)]
for ci, (h, w) in enumerate(NH, 1):
    c = ws.cell(4, ci, h); c.font = f_hdr; c.fill = fill(RED); c.alignment = center; c.border = box
    ws.column_dimensions[L(ci)].width = w
ws.row_dimensions[4].height = 46
NR = 100
for i in range(NR):
    rr = 5 + i
    ws.cell(rr, 1, i + 1).alignment = center
    ws.cell(rr, 1).fill = fill(GREY)
    for ci in range(1, 13):
        c = ws.cell(rr, ci); c.border = box; c.font = f_norm
        if ci > 1: c.fill = fill(EDIT); c.alignment = wrap
    ws.row_dimensions[rr].height = 32
media_items = [f"{o['optionLabel']}" for o in {c['optionKey']: c for c in D['combos']}.values()]
media_items = [m for m in dict.fromkeys(c['optionLabel'] for c in D['combos'])] + ['All media types / அனைத்து மீடியா']
inst_items = list(dict.fromkeys(r_['inst_en'] for r_ in ROWS if r_['inst_code'])) + ['All installation types / அனைத்து வகைகள்']
def col_dv(col, items):
    f = '"' + ','.join(items) + '"'
    if len(f) > 255:
        # fall back to a hidden list range
        return None
    dv = DataValidation(type='list', formula1=f, allow_blank=True, showErrorMessage=True)
    ws.add_data_validation(dv); dv.add(f'{col}5:{col}{4 + NR}')
    return dv
col_dv('B', media_items)
if col_dv('C', inst_items) is None:
    lst = wb.create_sheet('_Lists'); lst.sheet_state = 'hidden'
    for i, v in enumerate(inst_items, 1): lst.cell(i, 1, v)
    dv = DataValidation(type='list', formula1=f"=_Lists!$A$1:$A${len(inst_items)}", allow_blank=True, showErrorMessage=True)
    ws.add_data_validation(dv); dv.add(f'C5:C{4 + NR}')
col_dv('F', ['Yes/No / ஆம்/இல்லை', 'Yes/No/Not Applicable', 'Single choice / ஒற்றைத் தேர்வு', 'Dropdown', 'Numeric / எண்', 'Text / உரை', 'Photo / புகைப்படம்'])
col_dv('H', ['ft (அடி)', 'in (அங்குலம்)', 'mm', 'm', 'Not applicable / பொருந்தாது'])
col_dv('J', ['Required / தேவை', 'Optional / விருப்பம்'])
decision_dv(ws, f'L5:L{4 + NR}'); setup_decision_cf(ws, 'L', 5, 4 + NR)
ws.freeze_panes = 'B5'; ws.auto_filter.ref = f'A4:L{4 + NR}'; ws.sheet_properties.tabColor = 'FFB300'

# ----------------------------------------------------------------- 01 summary
ws = wb.create_sheet('01_Review_Summary', 1)
ws.sheet_view.showGridLines = False
ws['A1'] = 'Review Summary / மதிப்பாய்வுச் சுருக்கம்'; ws['A1'].font = f_title
ws['A2'] = ('Counts update automatically from the vendor decisions. "Question rows" counts every occurrence (a common question repeats for each installation type); '
            '"Unique questions" counts distinct English questions.  |  எண்ணிக்கைகள் விற்பனையாளர் முடிவுகளுக்கேற்ப தானாக மாறும்.')
ws['A2'].font = Font(name=FONT, size=9, italic=True, color='595959'); ws['A2'].alignment = wrap
ws.merge_cells('A2:I2'); ws.row_dimensions[2].height = 40
SH = ['Media Type\nமீடியா வகை', 'Sheet\nஷீட்', 'Applicable installation types\nபொருத்தும் வகைகள்',
      'Question rows (occurrences)\nகேள்வி வரிகள்', 'Unique questions\nதனித்த கேள்விகள்', 'Needed in App\nசெயலியில் தேவை',
      'Not Needed in App\nதேவையில்லை', 'Pending Review\nநிலுவை', 'Review Completion %\nமுடிவு %']
for ci, h in enumerate(SH, 1):
    c = ws.cell(4, ci, h); c.font = f_hdr; c.fill = fill(RED); c.alignment = center; c.border = box
ws.row_dimensions[4].height = 44
widths = [26, 22, 18, 18, 16, 16, 16, 16, 18]
for i, w in enumerate(widths, 1): ws.column_dimensions[L(i)].width = w
r = 5
first_sum = r
for key, sname in SHEETS:
    a, b, ninst, rows = sheet_info[sname]
    q = f"'{sname}'"
    ws.cell(r, 1, rows[0]['media_en']); ws.cell(r, 2, sname)
    if key == 'MDF':
        ws.cell(r, 3, 0)  # no installation type is configured for MDF
    else:
        ws.cell(r, 3, f"=SUMPRODUCT(1/COUNTIF({q}!$D${a}:$D${b},{q}!$D${a}:$D${b}))")
    ws.cell(r, 4, f"=COUNTA({q}!$A${a}:$A${b})")
    ws.cell(r, 5, f"=SUMPRODUCT(1/COUNTIF({q}!$G${a}:$G${b},{q}!$G${a}:$G${b}))")
    ws.cell(r, 6, f'=COUNTIF({q}!$Q${a}:$Q${b},"Needed in App*")')
    ws.cell(r, 7, f'=COUNTIF({q}!$Q${a}:$Q${b},"Not Needed in App*")')
    ws.cell(r, 8, f"=D{r}-F{r}-G{r}")
    ws.cell(r, 9, f"=IF(D{r}=0,0,(F{r}+G{r})/D{r})"); ws.cell(r, 9).number_format = '0.0%'
    for ci in range(1, 10):
        c = ws.cell(r, ci); c.font = f_norm; c.border = box; c.alignment = center if ci > 2 else wrap
    r += 1
last_sum = r - 1
ws.cell(r, 1, 'TOTAL / மொத்தம்'); ws.cell(r, 2, '(all media sheets)')
for ci in (3, 4, 6, 7, 8):
    ws.cell(r, ci, f"=SUM({L(ci)}{first_sum}:{L(ci)}{last_sum})")
ws.cell(r, 5, f"=SUM(E{first_sum}:E{last_sum})")
ws.cell(r, 9, f"=IF(D{r}=0,0,(F{r}+G{r})/D{r})"); ws.cell(r, 9).number_format = '0.0%'
for ci in range(1, 10):
    c = ws.cell(r, ci); c.font = f_bold; c.fill = fill('FDE7EA'); c.border = box; c.alignment = center if ci > 2 else wrap
tot_row = r
uniq_overall = len({(x['text']) for x in ROWS})
combos_real = len({(x['option'], x['inst_en']) for x in ROWS if x['inst_code']})
r += 2
notes = [
 ('Unique questions across the whole app (distinct English wording) / ஒட்டுமொத்த தனித்த கேள்விகள்', uniq_overall,
  'Fixed value from the export; the per-media "Unique questions" above can overlap, so their sum is larger.'),
 ('Valid media + installation combinations / செல்லுபடியான சேர்க்கைகள்', combos_real,
  'MDF has no installation type, so it adds no combination. Hanging Mount (GSB Double) cannot be saved and is excluded.'),
 ('Total question rows exported / மொத்த வரிகள்', len(ROWS), 'Every occurrence across combinations.'),
]
for t, v, n in notes:
    ws.cell(r, 1, t); ws.cell(r, 3, v); ws.cell(r, 4, n)
    ws.merge_cells(start_row=r, start_column=1, end_row=r, end_column=2)
    ws.merge_cells(start_row=r, start_column=4, end_row=r, end_column=9)
    for ci in (1, 3, 4):
        ws.cell(r, ci).font = f_norm; ws.cell(r, ci).alignment = wrap
    ws.row_dimensions[r].height = 34
    r += 1
r += 1
ws.cell(r, 1, 'Per media + installation combination / ஒவ்வொரு சேர்க்கைக்கும்').font = Font(name=FONT, size=11, bold=True, color=DARK)
r += 1
CH = ['Media Type', 'Installation Type', 'Question rows', 'Needed', 'Not Needed', 'Pending', 'Completion %']
for ci, h in enumerate(CH, 1):
    c = ws.cell(r, ci, h); c.font = f_hdr; c.fill = fill(RED); c.alignment = center; c.border = box
r += 1
for key, sname in SHEETS:
    a, b, ninst, rows = sheet_info[sname]
    q = f"'{sname}'"
    for inst in dict.fromkeys(x['inst_en'] for x in rows):
        ws.cell(r, 1, rows[0]['media_en']); ws.cell(r, 2, inst)
        ws.cell(r, 3, f'=COUNTIF({q}!$D${a}:$D${b},B{r})')
        ws.cell(r, 4, f'=COUNTIFS({q}!$D${a}:$D${b},B{r},{q}!$Q${a}:$Q${b},"Needed in App*")')
        ws.cell(r, 5, f'=COUNTIFS({q}!$D${a}:$D${b},B{r},{q}!$Q${a}:$Q${b},"Not Needed in App*")')
        ws.cell(r, 6, f'=C{r}-D{r}-E{r}')
        ws.cell(r, 7, f'=IF(C{r}=0,0,(D{r}+E{r})/C{r})'); ws.cell(r, 7).number_format = '0.0%'
        for ci in range(1, 8):
            c = ws.cell(r, ci); c.font = f_norm; c.border = box; c.alignment = center if ci > 2 else wrap
        r += 1
ws.freeze_panes = 'A5'; ws.sheet_properties.tabColor = DARK

# ----------------------------------------------------------------- 12 technical audit
ws = wb.create_sheet('12_Technical_Audit')
ws['A1'] = 'Technical Audit & Traceability (for the implementation team – not for vendor decisions)'; ws['A1'].font = f_title
ws['A2'] = ('Source: runtime resolution of lib/data/catalog/*.dart (SignageCatalog.questionsForUnit, SiteChecklists.questionsFor, QuestionEquivalence.pairsFor). '
            'Impact columns describe code dependencies found in the repository; nothing was changed. "Yes" = removing/changing the question can affect that area.')
ws['A2'].font = Font(name=FONT, size=9, italic=True, color='595959')
AH = ['Export Row ID', 'Sheet', 'Entry Kind', 'Media Option', 'Media Code', 'Installation Code', 'Original Question ID',
      'Canonical Question ID', 'Equivalent Checklist ID(s)', 'Question Source', 'Question Type', 'Required', 'Conditional Dependencies',
      'Source File:Line', 'Current Visibility (Vendor Workflow)', 'Validation Dependencies', 'Measurement Dependencies',
      'PDF / Report Dependencies', 'Installation Feasibility / Review Dependencies', 'Board Completion', 'Recce Readiness',
      'Installation Feasibility', 'Other Conditional Questions', '2D Drawing', '3D Preview', 'Camera AR', 'PDF Generation',
      'Review & Submit', 'Technical Review Flag', 'Notes']
AW = [30, 18, 20, 18, 12, 16, 24, 24, 26, 12, 14, 10, 34, 46, 40, 34, 28, 32, 34, 11, 11, 11, 11, 11, 11, 11, 11, 11, 16, 46]
for ci, (h, w) in enumerate(zip(AH, AW), 1):
    c = ws.cell(4, ci, h); c.font = f_hdr; c.fill = fill(RED); c.alignment = center; c.border = box
    ws.column_dimensions[L(ci)].width = w
ws.row_dimensions[4].height = 44

def impacts(row):
    q = row['q']; qid = q['id']; src = row['source']
    canonical = qid
    req = row['req_flag']
    geometry = qid in GEOMETRY_IDS
    review_flag = src == 'checklist' and (q.get('reviewIfYes') or q.get('reviewIfNo'))
    equiv_flag = False
    if src == 'site' and row['equiv']:
        # site answer is synced to the checklist; checklist review flags read the synced value
        for cid in row['equiv']:
            cq = next((x for x in D['definitions'] for y in x['questions'] if y['id'] == cid for _ in [0]), None)
        equiv_flag = True
    # review flag via equivalence
    via_equiv_review = False
    if src == 'site' and row['equiv']:
        for d in D['definitions']:
            for y in d['questions']:
                if y['id'] in row['equiv'] and (y['reviewIfYes'] or y['reviewIfNo']):
                    via_equiv_review = True
    cond_children = COND_PARENT.get(qid) if src == 'site' else None
    mirror = MIRRORS.get(qid) if src == 'site' else None
    d = dict(
        validation=('Required + visible: counted in missingAnswersFor / readiness' if (src == 'site' and req)
                    else 'Required checklist item: counted in uniqueMissing / readiness' if (src == 'checklist' and req)
                    else 'Optional: not counted'),
        measurement=(f'Mirrored to measurement field "{mirror}" (kAnswerMirrors)' if mirror else 'None found'),
        pdf=('Exported in report Site Questions (report_data.dart:378)' if src == 'site'
             else 'Exported in report checklist rows (report_data.dart:478)'),
        feas=('Answer can flag Requires Review (reviewIf' + ('Yes' if q.get('reviewIfYes') else 'No') + ')' if review_flag
              else 'Via synced checklist answer "' + ','.join(row['equiv']) + '" review flag' if via_equiv_review
              else 'None found'),
        board=('Yes' if req else 'No'), ready=('Yes' if req else 'No'),
        feasi=('Yes' if (review_flag or via_equiv_review) else 'No'),
        cond=('Yes – parent of "' + cond_children + '"' if cond_children else 'No'),
        d2='Yes' if geometry and src == 'site' else ('Indirect (answer listed in 2D sheet text)' if src == 'site' else 'No'),
        d3='Yes' if geometry and src == 'site' else 'No',
        ar='Yes' if geometry and src == 'site' else 'No',
        pdf_i='Yes', sub=('Yes' if req else 'Indirect'),
    )
    flags = []
    if geometry and src == 'site': flags.append('Drives geometry / drawing')
    if mirror: flags.append('Measurement mirror')
    if d['feasi'] == 'Yes': flags.append('Feasibility')
    if cond_children: flags.append('Conditional parent')
    if row['equiv']: flags.append('Equivalence mapped')
    d['flag'] = '; '.join(flags) if flags else ('Required' if req else '—')
    d['flagged'] = bool(flags)
    return d

r = 5
counters = {}
for sname, n, row in audit:
    q = row['q']
    d = impacts(row)
    rid = f"{row['option']}|{row['inst_code'] or 'NONE'}|{n:03d}"
    cond = (f"Shown only when {q['showIfId']} = {q['showIfValue']}" if row['source'] == 'site' and q['showIfId'] else 'None')
    vis = ('Visible – Site Questions step (unified form)' if row['source'] == 'site'
           else 'Visible – Site Questions step, embedded checklist section')
    notes_txt = ''
    if row['none_inst']:
        notes_txt = 'MDF: no installation configured; shown only if the board reaches the questions step with no installation.'
    if row['source'] == 'checklist' and row['q']['id'] == 'checklist_remarks':
        notes_txt = 'Additional Site Remarks (optional free text).'
    if row['equiv']:
        notes_txt = (notes_txt + ' ' if notes_txt else '') + 'Equivalent checklist question hidden in the unified form (answered once).'
    vals = [rid, sname, 'Exported (vendor sheet)', row['media_en'], row['media_code'], row['inst_code'] or '—', q['id'], q['id'],
            ', '.join(row['equiv']) or '—', row['source'].title(), q['type'], 'Required' if row['req_flag'] else 'Optional', cond,
            src_ref(row['source'], q['id']), vis, d['validation'], d['measurement'], d['pdf'], d['feas'], d['board'], d['ready'],
            d['feasi'], d['cond'], d['d2'], d['d3'], d['ar'], d['pdf_i'], d['sub'], d['flag'], notes_txt]
    for ci, v in enumerate(vals, 1):
        c = ws.cell(r, ci, v); c.font = f_norm; c.alignment = wrap; c.border = box
        if d['flagged'] and ci == 29: c.fill = fill('FFE0B2')
    r += 1

# non-exported entries (hidden / legacy / presentation-only)
def add_other(kind, media_opt, media_code, inst, qid, canon, equiv, srcname, qtype, req, condtxt, ref, vis, notes_txt, flag='Hidden / not exported'):
    global r
    vals = [f"OTHER|{kind}|{media_code}|{qid}", '—', kind, media_opt, media_code, inst, qid, canon, equiv, srcname, qtype, req, condtxt, ref, vis,
            '—', '—', '—', '—', '—', '—', '—', '—', '—', '—', '—', '—', '—', flag, notes_txt]
    for ci, v in enumerate(vals, 1):
        c = ws.cell(r, ci, v); c.font = f_norm; c.alignment = wrap; c.border = box; c.fill = fill('F5F5F5')
    r += 1

add_other('Presentation-only installation', 'GSB Double Side', 'GSB', 'Hanging Mount (no code)', '—', '—', '—', '—', '—', '—', '—',
          'lib/data/catalog/signage_catalog.dart:gsbDoubleChoices', 'Card visible; selection is never persisted',
          'No backend-supported code and no questions exist. Not a valid exported combination.')
add_other('Active media without installation', 'MDF', 'MDF', '—', '—', '—', '—', '—', '—', '—', '—',
          'lib/data/catalog/signage_catalog.dart (MediaType mdf, installations: [])', 'No installation selectable',
          'MDF has no approved fabrication / installation spec; no checklist definition exists. Only the 4 common Site Questions resolve.')
add_other('Hidden checklist question', 'All active media with checklists', '—', '—', 'site_evidence_photo', 'site_evidence_photo', '—', 'Checklist',
          'photoEvidence', 'Optional', 'None', src_ref('checklist', 'site_evidence_photo'),
          'Hidden in the unified Site Questions step (embedded hideIds); visible only in the advanced Unit Survey checklist tab',
          'Evidence photos are collected in Site Photos & Annotation. Linked to PDF evidence and review.')
for d_ in D['definitions']:
    if d_['id'] in ('wall_branding', 'single_standee', 'double_standee'):
        for q in d_['questions']:
            add_other('Legacy checklist definition', d_['title'], ', '.join(d_['mediaCodes']), (', '.join(q['installations']) if q['installations'] else 'any'),
                      q['id'], q['id'], '—', 'Checklist', q['type'], 'Required' if q['required'] else 'Optional', 'None',
                      src_ref('checklist', q['id']), 'Legacy media only – not offered for new media groups',
                      'Kept so older records stay readable.', flag='Legacy')
for q in D['legacySite']:
    add_other('Legacy / non-selectable media Site Question', q['media'], q['media'], 'any', q['id'], q['id'], '—', 'Site', q['type'],
              'Required' if q['required'] else 'Optional', (f"{q['showIfId']} = {q['showIfValue']}" if q['showIfId'] else 'None'),
              src_ref('site', q['id']), 'Legacy / catalog-only media – not offered for new media groups (selectableCodes)',
              'Not shown to vendors when adding new media.', flag='Legacy')
add_other('Advanced Unit Survey (non-Site-Question)', 'All', '—', '—', 'measurement / electrical forms', '—', '—', 'Other', 'various', '—', '—',
          'lib/features/survey/measurement_form.dart, electrical_form.dart, unit_survey_screen.dart',
          'Advanced survey (opened from the Units screen), not part of the vendor Site Questions step',
          'Measurement fields are mirrored from some Site Questions (see Measurement Dependencies). Not enumerated here.', flag='Advanced only')
last = r - 1
ws.freeze_panes = 'C5'; ws.auto_filter.ref = f'A4:{L(len(AH))}{last}'; ws.sheet_properties.tabColor = '595959'
for rr in range(5, last + 1):
    ws.row_dimensions[rr].height = 62

wb.move_sheet('01_Review_Summary', offset=0)
order = ['00_Instructions', '01_Review_Summary'] + [s for _, s in SHEETS] + ['11_New_Questions', '12_Technical_Audit']
wb._sheets = [wb[n] for n in order] + [s for s in wb._sheets if s.title not in order]
wb.active = 0
os.makedirs(os.path.dirname(OUT), exist_ok=True)
wb.save(OUT)
print('saved', OUT)
print('rows', len(ROWS), 'unique', uniq_overall, 'combos', combos_real)
