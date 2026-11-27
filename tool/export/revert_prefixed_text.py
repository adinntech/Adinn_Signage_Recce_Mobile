import os, re
root = os.path.join(os.path.dirname(__file__), '..', '..', 'lib')
LIT = r"""(?:'(?:[^'\\\n$]|\\.)*'|"(?:[^"\\\n$]|\\.)*")"""
SEQ = r"(?:%s(?:\s*%s)*)" % (LIT, LIT)
rx = re.compile(r"(\b\w+\.Text\(\s*)context\.ui\((%s)\)" % SEQ)
n = 0
for d, _, fs in os.walk(root):
    for f in fs:
        if not f.endswith('.dart'):
            continue
        p = os.path.join(d, f)
        s = open(p, encoding='utf-8').read()
        t, k = rx.subn(lambda m: m.group(1) + m.group(2), s)
        if k:
            n += k
            open(p, 'w', encoding='utf-8', newline='').write(t)
print('reverted', n)
