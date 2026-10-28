# expand F32(expr) into Veltkamp's rounding; usage: expand.py in.tpl out.sql
import sys, re
s = open(sys.argv[1]).read()
def expand(s):
    out = []; i = 0
    while True:
        j = s.find('F32(', i)
        if j < 0: out.append(s[i:]); break
        out.append(s[i:j]); k = j + 4; depth = 1
        while depth:
            if s[k] == '(': depth += 1
            elif s[k] == ')': depth -= 1
            k += 1
        e = expand(s[j+4:k-1]).strip()
        a = e if re.fullmatch(r'[\w.]+', e) else f'({e})'
        # parenthesised unless it is the whole of a SELECT item or argument
        before = s[:j].rstrip()[-1:] ; after = s[k:].lstrip()[:2]
        bare = before in (',', '(', '') or s[:j].rstrip().upper().endswith(('SELECT', 'THEN', 'ELSE', 'WHEN'))
        bare = bare and (after[:1] in (',', ')') or after.upper().startswith('AS') or after[:1] == '')
        r = f'{a} * 536870913.0 - ({a} * 536870913.0 - {a})'
        out.append(r if bare else f'({r})')
        i = k
    return ''.join(out)
open(sys.argv[2], 'w').write(expand(s))
