import glob, re, json, sys
sys.path.insert(0, 'tool/export')
exec(open('tool/export/localization_audit.py', encoding='utf-8').read().split('rows, missing')[0])  # DICT, keys()
files = ['measurement_fields', 'site_survey', 'enums', 'media_reference', 'ar_scene_controller', 'signage_spec']
out = {}
for f in files:
    p = glob.glob('lib/**/%s.dart' % f, recursive=True)[0]
    t = open(p, encoding='utf-8').read()
    for m in re.finditer(r"(?:=>|label:|hint:|description:)\s*'((?:[^'\\\n]|\\.)*)'", t):
        s = m.group(1).replace("\\'", "'")
        if re.search(r'[A-Za-z]{3}', s) and '$' not in s and s not in DICT and not re.fullmatch(r'[a-z_0-9]+', s):
            out[s] = f
json.dump(out, open('build/export/enum_missing.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
print(len(out)); print('\n'.join(out))
