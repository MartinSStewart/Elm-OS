// tools/format: Elm OS's Elm formatter (tools/format/src, compiled to JS by eco), run by node.
//
//   node format.js ELMJS --yes PATH...       format every .elm file under PATH in place
//   node format.js ELMJS --validate PATH...  list the files that aren't formatted; exit 1 if any
//   node format.js ELMJS --stdin             format stdin to stdout
//   node format.js ELMJS --test PATH...      check the formatter on every .elm file under PATH:
//       the output parses, formatting it again changes nothing, it holds the same tokens
//       (comments included) as the input, and its syntax tree is the input's apart from
//       comments, positions and parentheses. With --expect-unchanged, every file must also already
//       be formatted. Files that don't parse are skipped and listed.
//
// ELMJS is the compiled tools/format/cli/FormatCli.elm.
'use strict';
const fs = require('fs');
const path = require('path');

const [elmJs, mode, ...rest] = process.argv.slice(2);
const expectUnchanged = rest.includes('--expect-unchanged');
const paths = rest.filter(a => !a.startsWith('--'));

const { Elm } = require(path.resolve(elmJs));
const app = Elm.FormatCli.init();
let waiting = null;
app.ports.formatResult.subscribe(result => {
  const w = waiting;
  waiting = null;
  w(result);
});
function request(source, syntaxTree) {
  return new Promise(resolve => {
    waiting = resolve;
    app.ports.formatRequest.send({ source, syntaxTree });
  });
}
const format = source => request(source, false);
const syntaxTree = source => request(source, true);

function elmFiles(p) {
  const stat = fs.statSync(p);
  if (stat.isFile()) return [p];
  return fs.readdirSync(p).sort().flatMap(name => {
    if (name === 'elm-stuff' || name === 'eco-stuff' || name.startsWith('.')) return [];
    const full = path.join(p, name);
    return fs.statSync(full).isDirectory() ? elmFiles(full) : name.endsWith('.elm') ? [full] : [];
  });
}

// ---- tokens, for --test: the formatter may move tokens around, never add or drop one

// Splits Elm source into tokens. Whitespace separates tokens and is otherwise ignored; inside a
// comment, every run of whitespace counts as one space. Literals are kept as written, except
// that the escapes the formatter normalizes are decoded first.
function tokens(src) {
  const out = [];
  let i = 0;
  const n = src.length;
  const isIdent = c => /[A-Za-z0-9_]/.test(c);
  const isSymbol = c => /[+\-*\/=<>!&|^%:.~$#@?\\]/.test(c);
  while (i < n) {
    const c = src[i];
    if (/\s/.test(c)) { i++; continue; }
    if (src.startsWith('--', i)) {
      let j = src.indexOf('\n', i);
      if (j === -1) j = n;
      out.push('--' + squash(src.slice(i + 2, j)));
      i = j;
      continue;
    }
    if (src.startsWith('{-', i)) {
      let depth = 0, j = i;
      while (j < n) {
        if (src.startsWith('{-', j)) { depth++; j += 2; }
        else if (src.startsWith('-}', j)) { depth--; j += 2; if (depth === 0) break; }
        else j++;
      }
      // elm-format trims the comment trick: `{-- text` becomes `{--text`
      out.push('{-' + squash(src.slice(i + 2, j - 2)).replace(/^- /, '-') + '-}');
      i = j;
      continue;
    }
    if (src.startsWith('"""', i)) {
      let j = i + 3;
      while (j < n && !src.startsWith('"""', j)) j += src[j] === '\\' ? 2 : 1;
      out.push('"' + decode(src.slice(i + 3, j), true) + '"');
      i = j + 3;
      continue;
    }
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < n && src[j] !== c) j += src[j] === '\\' ? 2 : 1;
      out.push(c + decode(src.slice(i + 1, j), false) + c);
      i = j + 1;
      continue;
    }
    if (src.startsWith('[glsl|', i)) {
      const j = src.indexOf('|]', i);
      out.push(src.slice(i, j + 2));
      i = j + 2;
      continue;
    }
    if (isIdent(c)) {
      let j = i;
      while (j < n && (isIdent(src[j]) || (src[j] === '.' && isIdent(src[j + 1] || '') && /[A-Z]/.test(src[i])))) j++;
      let word = src.slice(i, j);
      if (/^0x/i.test(word)) word = '0x' + word.slice(2).toUpperCase();
      out.push(word);
      i = j;
      continue;
    }
    if (isSymbol(c)) {
      let j = i;
      while (j < n && isSymbol(src[j]) && !src.startsWith('--', j) && !src.startsWith('{-', j)) j++;
      if (j === i) j = i + 1;
      out.push(src.slice(i, j));
      i = j;
      continue;
    }
    out.push(c);
    i++;
  }
  return out;
}

function squash(text) {
  return text.trim().replace(/\s+/g, ' ');
}

// Decodes the escapes a formatter may rewrite: \u{...}, \n in a """ string, \" and \'.
function decode(text, triple) {
  return text.replace(/\\u\{([0-9A-Fa-f]+)\}|\\(.)|\t/g, (m, hex, ch) => {
    if (hex) return String.fromCodePoint(parseInt(hex, 16));
    if (m === '\t') return '\\t';
    if (ch === 'n' && triple) return '\n';
    if (ch === '"' || ch === "'") return ch;
    return m;
  });
}

// Parentheses aren't compared: the formatter adds and removes some, and sameTree checks the
// grouping they express.
function sameTokens(a, b) {
  const notParen = t => t !== '(' && t !== ')';
  const ta = tokens(a).filter(notParen), tb = tokens(b).filter(notParen);
  if (ta.length === tb.length && ta.every((t, k) => t === tb[k])) return null;
  // imports and exposing lists may be reordered: compare as multisets
  const count = ts => ts.reduce((m, t) => m.set(t, (m.get(t) || 0) + 1), new Map());
  const ca = count(ta), cb = count(tb);
  const problems = [];
  for (const [t, k] of ca) if ((cb.get(t) || 0) !== k) problems.push(`${JSON.stringify(t)}: ${k} -> ${cb.get(t) || 0}`);
  for (const [t, k] of cb) if (!ca.has(t)) problems.push(`${JSON.stringify(t)}: 0 -> ${k}`);
  return problems.length ? problems.slice(0, 10).join('\n    ') : null;
}

// ---- syntax trees, for --test: formatting must not change what the code means

// Reads the Debug.toString of an Elm value: constructors with arguments, records, lists, tuples,
// strings, chars and numbers.
function readElmValue(text) {
  let i = 0;
  const ws = () => { while (/\s/.test(text[i])) i++; };
  const fail = () => { throw new Error(`can't read the syntax tree at ${i}: ${text.slice(i, i + 40)}`); };
  function quoted(q) {
    let j = i + 1, out = '';
    while (text[j] !== q) {
      if (text[j] !== '\\') { out += text[j++]; continue; }
      const u = /^\\u\{([0-9A-Fa-f]+)\}/.exec(text.slice(j, j + 12));
      if (u) { out += String.fromCodePoint(parseInt(u[1], 16)); j += u[0].length; continue; }
      const e = text[j + 1];
      out += e === 'n' ? '\n' : e === 't' ? '\t' : e === 'r' ? '\r' : e;
      j += 2;
    }
    i = j + 1;
    return out;
  }
  function sequence(close) {
    const items = [];
    ws();
    if (text[i] === close) { i++; return items; }
    for (;;) {
      items.push(value());
      ws();
      if (text[i] === ',') { i++; continue; }
      if (text[i] === close) { i++; return items; }
      fail();
    }
  }
  function atom() {
    ws();
    const c = text[i];
    if (c === '"') return { s: quoted('"') };
    if (c === "'") return { ch: quoted("'") };
    if (c === '[') { i++; return { l: sequence(']') }; }
    if (c === '(') { i++; const items = sequence(')'); return items.length === 1 ? items[0] : { t: items }; }
    if (c === '<') { const j = text.indexOf('>', i); const v = { opaque: text.slice(i, j + 1) }; i = j + 1; return v; }
    if (c === '{') {
      i++;
      const r = {};
      ws();
      if (text[i] === '}') { i++; return { r }; }
      for (;;) {
        ws();
        const m = /^[a-z][A-Za-z0-9_]*/.exec(text.slice(i, i + 100)) || fail();
        i += m[0].length;
        ws();
        if (text[i] !== '=') fail();
        i++;
        r[m[0]] = value();
        ws();
        if (text[i] === ',') { i++; continue; }
        if (text[i] === '}') { i++; return { r }; }
        fail();
      }
    }
    const m = /^(-?[0-9][0-9.e+\-]*|-?Infinity|NaN|[A-Z][A-Za-z0-9_.]*)/.exec(text.slice(i, i + 100)) || fail();
    i += m[0].length;
    if (/^[A-Z]/.test(m[0]) && m[0] !== 'Infinity' && m[0] !== 'NaN') return { c: m[0], a: [] };
    return { n: m[0] };
  }
  function value() {
    const v = atom();
    if (v.c === undefined) return v;
    for (;;) {
      ws();
      if (i >= text.length || /[,)\]}]/.test(text[i])) return v;
      v.a.push(atom());
    }
  }
  const v = value();
  ws();
  if (i < text.length) fail();
  return v;
}

// eco's parser keeps a literal's escapes, writing \u{...} as \uXXXX (UTF-16).
function decodeParsed(text) {
  return text.replace(/\\u([0-9A-Fa-f]{4})|\\u\{([0-9A-Fa-f]+)\}|\\(.)/g, (m, utf16, hex, ch) =>
    utf16 ? String.fromCharCode(parseInt(utf16, 16)) :
    hex ? String.fromCodePoint(parseInt(hex, 16)) :
    ({ n: '\n', t: '\t', r: '\r' })[ch] || ch);
}

// What formatting may change: comments, positions, parentheses, how a number is written,
// line-break choices, and the order of imports and exposing lists.
const isComment = v => v && (v.c === 'BlockComment' || v.c === 'LineComment');
const isCommentSlot = v =>
  v === null || (v.l && v.l.length === 0) || (v.c === 'Nothing' && v.a.length === 0) ||
  (v.c === 'Just' && v.a.length === 1 && v.a[0].s !== undefined) || (v.t && v.t.every(isCommentSlot));
const PARENS = ['Parens', 'PParens', 'TParens'];
function normalize(v) {
  if (v.l) {
    const items = v.l.filter(x => !isComment(x)).map(normalize);
    return { l: items };
  }
  if (v.t) {
    const items = v.t.map(normalize);
    // C1, C2 and the end-of-line variants: the comment slots go, the value stays
    if (items.slice(0, -1).every(isCommentSlot)) return items[items.length - 1];
    return { t: items };
  }
  if (v.r) {
    const r = {};
    for (const k of Object.keys(v.r).sort()) r[k] = normalize(v.r[k]);
    if (r.imports && r.imports.l) r.imports.l.sort(byText);
    return { r };
  }
  if (v.c === undefined) return v;
  if (v.c === 'Snippet' && v.a[0] && v.a[0].r) {
    // a doc comment: its text, not the whole file it points into
    const r = v.a[0].r;
    const start = Number(r.offset.n);
    return { c: 'Snippet', a: [{ s: r.fptr.s.slice(start, start + Number(r.length.n)) }] };
  }
  if (v.c === 'Region' || v.c === 'Position' || v.c === 'ForceMultiline') return null;
  if (['Str', 'PStr', 'Chr', 'PChr'].includes(v.c) && v.a[0].s !== undefined)
    return { c: v.c, a: [{ s: decodeParsed(v.a[0].s) }] };
  if ((v.c === 'Int' || v.c === 'Float' || v.c === 'PInt') && v.a.length === 2) return { c: v.c, a: [v.a[0]] };
  const a = v.a.map(normalize);
  if (PARENS.includes(v.c) && a.length === 1) return a[0];
  if (v.c === 'At' && a.length === 2 && a[1] && a[1].c === 'At') return a[1]; // was At r (Parens (At r' x))
  if (v.c === 'Negate' && a[0] && a[0].c === 'At' && a[0].a[1].c === 'Int' || v.c === 'Negate' && a[0] && a[0].c === 'At' && a[0].a[1].c === 'Float') {
    const lit = a[0].a[1];
    return { c: 'At', a: [null, { c: lit.c, a: [{ n: String(-Number(lit.a[0].n)) }] }] };
  }
  if (v.c === 'Explicit' && a.length === 1 && a[0].c === 'At' && a[0].a[1].l) a[0].a[1].l.sort(byText);
  return { c: v.c, a };
}
function byText(x, y) {
  const a = JSON.stringify(x), b = JSON.stringify(y);
  return a < b ? -1 : a > b ? 1 : 0;
}
async function sameTree(a, b) {
  const [ta, tb] = [await syntaxTree(a), await syntaxTree(b)];
  if (!ta.ok || !tb.ok) return 'one of them does not parse';
  const [na, nb] = [JSON.stringify(normalize(readElmValue(ta.text))), JSON.stringify(normalize(readElmValue(tb.text)))];
  if (na === nb) return null;
  let k = 0;
  while (na[k] === nb[k]) k++;
  return `the syntax trees differ:\n    before: ...${na.slice(Math.max(0, k - 150), k + 150)}\n    after:  ...${nb.slice(Math.max(0, k - 150), k + 150)}`;
}

// ---- modes

(async () => {

if (mode === '--tree') {
  const r = await syntaxTree(fs.readFileSync(0, 'utf8'));
  process.stdout.write(rest.includes('--normalized') ? JSON.stringify(normalize(readElmValue(r.text))) + '\n' : r.text + '\n');
} else if (mode === '--stdin') {
  const r = await format(fs.readFileSync(0, 'utf8'));
  if (!r.ok) { process.stderr.write(r.text + '\n'); process.exit(1); }
  process.stdout.write(r.text);
} else if (mode === '--yes' || mode === '--validate') {
  let bad = 0;
  for (const f of paths.flatMap(elmFiles)) {
    const src = fs.readFileSync(f, 'utf8');
    const r = await format(src);
    if (!r.ok) { console.error(`${f}: doesn't parse: ${r.text}`); bad++; continue; }
    if (r.text === src) continue;
    if (mode === '--yes') fs.writeFileSync(f, r.text);
    else { console.error(`${f} isn't formatted`); bad++; }
  }
  process.exit(bad ? 1 : 0);
} else if (mode === '--test') {
  const files = paths.flatMap(elmFiles);
  const failures = [];
  let skipped = 0, changed = 0;
  for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');
    const once = await format(src);
    if (!once.ok) { skipped++; console.log(`skipped (doesn't parse): ${f}`); continue; }
    const twice = await format(once.text);
    if (!twice.ok) { failures.push(`${f}: the formatted file doesn't parse: ${twice.text.slice(0, 300)}`); continue; }
    if (twice.text !== once.text) failures.push(`${f}: formatting the formatted file changes it again`);
    const lost = sameTokens(src, once.text);
    if (lost) failures.push(`${f}: tokens differ:\n    ${lost}`);
    const changedTree = await sameTree(src, once.text);
    if (changedTree) failures.push(`${f}: ${changedTree}`);
    if (once.text !== src) {
      changed++;
      if (expectUnchanged) failures.push(`${f}: changed, but it should already be formatted`);
    }
  }
  for (const failure of failures) console.log(failure);
  console.log(`${files.length} files, ${changed} changed, ${skipped} skipped, ${failures.length} problems`);
  process.exit(failures.length ? 1 : 0);
} else {
  console.error('usage: node format.js ELMJS (--yes|--validate|--test) PATH... | --stdin');
  process.exit(2);
}
})();
