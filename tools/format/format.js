// tools/format: Elm OS's Elm formatter (tools/format/src, compiled to JS by eco), run by node.
//
//   node format.js ELMJS --yes PATH...       format every .elm file under PATH in place
//   node format.js ELMJS --validate PATH...  list the files that aren't formatted; exit 1 if any
//   node format.js ELMJS --stdin             format stdin to stdout
//   node format.js ELMJS --test PATH...      check the formatter on every .elm file under PATH:
//       the output parses, formatting it again changes nothing, and it holds the same tokens
//       (comments included) as the input. With --expect-unchanged, every file must also already
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
function format(source) {
  return new Promise(resolve => {
    waiting = resolve;
    app.ports.formatRequest.send(source);
  });
}

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
      out.push('{-' + squash(src.slice(i + 2, j - 2)) + '-}');
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

// Tokens the formatter is allowed to add or remove: parentheses and commas around
// reordered exposing lists, and the `(..)` it drops from @docs lines.
function sameTokens(a, b) {
  const ta = tokens(a), tb = tokens(b);
  if (ta.length === tb.length && ta.every((t, k) => t === tb[k])) return null;
  // imports and exposing lists may be reordered: compare as multisets
  const count = ts => ts.reduce((m, t) => m.set(t, (m.get(t) || 0) + 1), new Map());
  const ca = count(ta), cb = count(tb);
  const problems = [];
  for (const [t, k] of ca) if ((cb.get(t) || 0) !== k) problems.push(`${JSON.stringify(t)}: ${k} -> ${cb.get(t) || 0}`);
  for (const [t, k] of cb) if (!ca.has(t)) problems.push(`${JSON.stringify(t)}: 0 -> ${k}`);
  return problems.length ? problems.slice(0, 10).join('\n    ') : null;
}

// ---- modes

(async () => {

if (mode === '--stdin') {
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
