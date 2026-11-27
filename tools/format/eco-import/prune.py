"""Copy the parts of eco's compiler reachable from given roots into a new source dir.
usage: prune.py ECO_SRC OUT_SRC Module.name ...
Top-level declarations not reachable (by token over-approximation) are dropped."""
import re, os, sys
src, out, roots = sys.argv[1], sys.argv[2], sys.argv[3:]
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*")

def path(m):
    p = os.path.join(src, m.replace('.', '/') + '.elm')
    return p if os.path.exists(p) else None

def strip_strings_comments(t):
    # remove string literals, char literals and comments, for token scanning
    t = re.sub(r'"""(?:.|\n)*?"""', '""', t)
    t = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', t)
    t = re.sub(r"'(?:\\.|[^'\\\n])+'", "' '", t)
    t = re.sub(r'--[^\n]*', '', t)
    # nested block comments
    while True:
        n = re.sub(r'\{-(?:(?!\{-|-\}).|\n)*-\}', '', t)
        if n == t: break
        t = n
    return t

def strip_strings_only(l):
    l = re.sub(r'"(?:\\.|[^"\\])*"', '""', l)
    l = re.sub(r"'(?:\\.|[^'\\])+'", "' '", l)
    return re.sub(r'--.*', '', l) if '{-' not in l.split('--')[0] else l

class Mod:
    pass

mods = {}
def load(name):
    if name in mods: return mods[name]
    p = path(name)
    if not p: mods[name] = None; return None
    m = Mod(); m.name = name; m.text = open(p).read(); mods[name] = m
    lines = m.text.split('\n')
    # header ends after last import line block
    i = 0; header_end = None
    # find 'module' declaration end and imports
    imports = []
    idx = 0; n = len(lines)
    # locate first top-level decl after imports: scan for import lines
    last_import = -1
    d0 = 0
    for k, l in enumerate(lines):
        if d0 == 0 and l.startswith('import '): last_import = k
        if d0 == 0 and l and not l[0].isspace() and re.match(r'(type |port |infix |[a-z_]\w*\s*(:|[^\n]*=))', l) and not l.startswith('import ') and not l.startswith('module ') and not l.startswith('port module') and not l.startswith('effect module'): break
        sl = strip_strings_only(l)
        d0 += len(re.findall(r'\{-', sl)) - len(re.findall(r'-\}', sl)); d0 = max(d0, 0)
    # header = everything up to last_import (plus continuation lines)
    k = last_import + 1
    while k < n and (lines[k].startswith(' ') ):
        k += 1
    if last_import == -1:
        # no imports: header is module line + exposing + module doc comment
        # find end of module doc comment
        txt = m.text
        mm = re.match(r'(?:port |effect )?module[^\n]*(?:\n[ ][^\n]*)*\n', txt)
        k = txt[:mm.end()].count('\n')
        rest = '\n'.join(lines[k:])
        dm = re.match(r'\s*\{-\|(?:.|\n)*?-\}\n', rest)
        if dm: k += rest[:dm.end()].count('\n')
    hdr = []
    for l in lines[:k]:
        if hdr and hdr[-1].startswith('import ') and l.startswith(' ') and l.strip():
            hdr[-1] = hdr[-1] + ' ' + l.strip()
        else:
            hdr.append(l)
    m.header = [re.sub(r'\(\s+', '(', re.sub(r'\s+\)', ')', l)) if l.startswith('import ') else l for l in hdr]
    for l in m.header:
        im = re.match(r'import\s+([\w.]+)(?:\s+as\s+(\w+))?(?:\s+exposing\s+\((.*)\))?', l)
        if im:
            imports.append((im.group(1), im.group(2) or im.group(1), im.group(3)))
    m.imports = imports
    # split body into chunks at column-0 non-space lines, attaching preceding comments
    body = lines[k:]
    chunks = []; cur = []; pending = []; curd = 0
    depth = 0
    DECL = re.compile(r'(type |port |infix |[a-z_]\w*\b)')
    for l in body:
        if depth == 0 and l and not l[0].isspace() and (l.startswith('{-') or l.startswith('--')):
            if cur and not pending:
                chunks.append((curd, cur)); cur = []
            pending.append(l)
        elif depth == 0 and l and not l[0].isspace() and DECL.match(l):
            nm = re.match(r'([a-z_]\w*)', l)
            if cur and not pending and nm and re.match(r'([a-z_]\w*)\s*:', cur[curd]) and re.match(r'([a-z_]\w*)', cur[curd]).group(1) == nm.group(1):
                cur.append(l)
            else:
                if cur: chunks.append((curd, cur))
                curd = len(pending); cur = pending + [l]; pending = []
        else:
            (pending if pending else cur).append(l)
        sl = strip_strings_only(l)
        depth += len(re.findall(r'\{-', sl)) - len(re.findall(r'-\}', sl))
        depth = max(depth, 0)
    if cur: chunks.append((curd, cur))
    if pending: chunks.append((None, pending))
    m.chunks = []
    for d, c in chunks:
        code = '\n'.join(x for x in c)
        first = c[d] if d is not None else ''
        names = set()
        mt = re.match(r'type\s+alias\s+(\w+)', first) or None
        if mt: names.add(mt.group(1))
        elif first.startswith('type '):
            tn = re.match(r'type\s+(\w+)', first).group(1); names.add(tn)
            s = strip_strings_comments(code)
            for cm in re.finditer(r'(?:=|\|)\s*([A-Z]\w*)', s): names.add(cm.group(1))
        elif first.startswith('port '):
            names.add(re.match(r'port\s+(\w+)', first).group(1))
        elif first.startswith('infix '):
            mi = re.search(r'\((\S+)\)\s*=\s*(\w+)', first); names.add('(' + mi.group(1) + ')'); names.add('INFIX')
        else:
            mf = re.match(r'([a-z_]\w*)', first)
            if mf: names.add(mf.group(1))
        m.chunks.append({'names': names, 'lines': c, 'tokens': set(IDENT.findall(strip_strings_comments(code))) if names else set(), 'keep': not names})
    m.defs = {}
    for ch in m.chunks:
        for nm in ch['names']: m.defs[nm] = ch
    return m

def resolve(m, tok):
    """yield (module, name) a token may refer to"""
    parts = tok.split('.')
    res = []
    for cut in range(len(parts) - 1, 0, -1):
        q = '.'.join(parts[:cut]); nm = parts[cut]
        for (im, alias, exp) in m.imports:
            if alias == q or im == q: res.append((im, nm))
    nm = parts[0]
    if nm in m.defs: res.append((m.name, nm))
    for (im, alias, exp) in m.imports:
        if exp is not None: res.append((im, nm))
    for p in parts: res.append((None, p))
    return res

keep = set(); work = []
def mark(mn, nm):
    if (mn, nm) in keep: return
    mm = load(mn)
    if not mm or nm not in mm.defs: return
    ch = mm.defs[nm]
    for x in ch['names']: keep.add((mn, x))
    ch['keep'] = True
    work.append((mn, ch))

for r in roots:
    mn, nm = r.rsplit('.', 1); load(mn); mark(mn, nm)
# operators: keep infix decls of loaded modules
used_mods = set()
while work:
    mn, ch = work.pop()
    mm = mods[mn]; used_mods.add(mn)
    for (im, a, e) in mm.imports:
        load(im)
    for tok in ch['tokens']:
        for (tm, nm) in resolve(mm, tok):
            if tm: mark(tm, nm)
    # infix operators used: keep all infix decls of imported modules (cheap)
    for (im, a, e) in mm.imports:
        x = mods.get(im)
        if x:
            for c in x.chunks:
                if 'INFIX' in c['names'] and not c['keep']:
                    c['keep'] = True; used_mods.add(im)
                    tgt = re.search(r'=\s*(\w+)', c['lines'][-1] if c['lines'] else '')
                    for l in c['lines']:
                        t2 = re.search(r'\)\s*=\s*(\w+)', l)
                        if t2: mark(im, t2.group(1))

total = 0
for mn in sorted(used_mods):
    mm = mods[mn]
    hdr = '\n'.join(mm.header)
    # filter exposing list in module line
    def fix_exposing(h):
        mm2 = re.match(r'((?:port |effect )?module\s+[\w.]+\s+exposing\s*)\(', h)
        start = mm2.end() - 1; depth = 0
        for k in range(start, len(h)):
            if h[k] == '(': depth += 1
            elif h[k] == ')':
                depth -= 1
                if depth == 0: end = k; break
        inner = h[start+1:end]
        if inner.strip() == '..': return h
        items = []
        for it in re.split(r',(?![^(]*\))', strip_strings_comments(inner)):
            it = it.strip()
            if not it: continue
            base = it.split('(')[0].strip() if not it.startswith('(') else it
            if (mn, base) in keep: items.append(it)
        if not items: items = ['..']
        return h[:start] + '(' + ', '.join(items) + ')' + h[end+1:]
    hdr = fix_exposing(hdr)
    hl = [l for l in hdr.split('\n') if not (l.startswith('import ') and re.match(r'import\s+([\w.]+)', l).group(1) not in used_mods and path(re.match(r'import\s+([\w.]+)', l).group(1)))]
    body = []
    for c in mm.chunks:
        if c['keep']: body += c['lines']
    btoks = set(IDENT.findall(strip_strings_comments('\n'.join(body))))
    def import_used(l):
        im = re.match(r'import\s+([\w.]+)(?:\s+as\s+(\w+))?(?:\s+exposing\s+\((.*)\))?', l)
        alias = im.group(2) or im.group(1)
        if any(t.startswith(alias + '.') for t in btoks): return True
        if im.group(3):
            if im.group(3).strip() == '..': return True
            for it in im.group(3).split(','):
                nm = it.strip().split('(')[0].strip()
                if nm in btoks: return True
                if '(..)' in it and nm in mods.get(im.group(1), Mod()).__dict__.get('defs', {}):
                    ctors = mods[im.group(1)].defs[nm]['names']
                    if ctors & btoks: return True
        return False
    hl = [l for l in hl if not l.startswith('import ') or import_used(l)]
    text = '\n'.join(hl + body)
    text = re.sub(r'\n{4,}', '\n\n\n', text)
    op = os.path.join(out, mn.replace('.', '/') + '.elm')
    os.makedirs(os.path.dirname(op), exist_ok=True)
    open(op, 'w').write(text)
    total += text.count('\n')
print(len(used_mods), 'modules', total, 'lines', file=sys.stderr)
