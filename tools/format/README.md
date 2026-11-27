# tools/format: an Elm formatter written in Elm

Elm OS formats Elm code with this instead of the elm-format binary, so the Code app can
format on the device. Its syntax tree keeps every comment in place (not in a side list),
so it is also the base for later editor actions that need the whole tree.

It is not wired into `make format` or the Code app yet; see "Status".

## Where the code comes from

`src/` is a copy of part of the eco compiler (eco-lang/eco-compiler, `compiler/src`,
commit 208a501d81ddf3aab19d8bbe21bd1f8123b785f3, 2026-11-09):

- `Compiler/Parse/*`, `Compiler/Lexer/*`, `Compiler/IR/Source.elm`: eco's own parser and
  source syntax tree. Comments are part of the tree (`Src.C1`, `Src.C2`, `Src.FComment`),
  as in elm-format, whose design eco's parser took over from Guida.
- `Common/Format/*`: eco's port of elm-format 0.8's printer.

`eco-import/prune.py` copied only the declarations reachable from `Common.Format.format`,
and `eco-import/localize.py` replaced what needs eco's own kernel modules or other
packages (`Extra/*` replaces the elm-community helpers). Since then the copy has been
edited here, so running those scripts again would lose the fixes below; they are kept
to show how the copy was made, and for copying a later parser fix by hand.

The licences: `LICENSE-eco-compiler` (eco, from Elm and Guida) and `LICENSE-elm-format`.

## Differences from eco's copy

- Doc comments are kept exactly as written. eco's port re-prints their Markdown (as
  elm-format does), and got it wrong: it reordered lines. Not touching them can't change
  what they say.
- `Common.Format.Box.rowLength` no longer renders a row to measure it, which made
  formatting take time exponential in how deeply rows nest.
- String and char literals: escapes are read properly (eco's parser writes `\u{XXXX}` as
  `\uXXXX`, which the printer copied out, and the output didn't parse).
- Block comments are indented like elm-format does it.
- A function call's first argument counts as on the next line only if it *starts* there.

## Testing

    make test-format

formats every Elm file in the repo and checks that the output parses, that formatting
the output again changes nothing, and that it holds the same tokens as the input,
comments included (so nothing was dropped). `node tools/format/format.js build/format.js
--test --expect-unchanged PATH` also fails when an already formatted file changes.

## Status

Known differences from elm-format still being fixed: end-of-line comments in record
types and custom types move to the next line, comments after a module's last
declaration are dropped, multi-line strings in lists, record fields whose value is on
the next line.
