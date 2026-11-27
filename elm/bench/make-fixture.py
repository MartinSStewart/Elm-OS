# Writes an Elm module with the HTML fixtures as String constants, so the benchmark
# (Bench.elm) needs no file reading.  usage: python3 -I make-fixture.py OUT TOP.gz ITEM.gz
import gzip, html, os, re, sys


def elm_string(s):
    out = []
    for c in s:
        if c == "\\":
            out.append("\\\\")
        elif c == '"':
            out.append('\\"')
        elif c == "\n":
            out.append("\\n")
        elif c == "\r":
            out.append("\\r")
        elif c == "\t":
            out.append("\\t")
        elif ord(c) < 32 or 0xD800 <= ord(c) <= 0xDFFF:
            out.append("\\u{%04X}" % ord(c))
        else:
            out.append(c)
    return '"' + "".join(out) + '"'


out, top, item = sys.argv[1:4]
item_id = re.search(r"item-(\d+)", os.path.basename(item)).group(1)
with open(out, "w", encoding="utf-8") as f:
    f.write("module Fixture exposing (itemId, item, prose, top)\n\n\n")
    f.write("itemId : String\nitemId =\n    " + elm_string(item_id) + "\n\n\n")
    for name, path in (("top", top), ("item", item)):
        text = gzip.open(path, "rb").read().decode("utf-8")
        f.write(name + " : String\n" + name + " =\n    " + elm_string(text) + "\n\n\n")
    # The first 100,000 characters of the item page's comments as plain text, a paragraph
    # a line: prose for timing word wrap in Noto Sans.
    page = gzip.open(item, "rb").read().decode("utf-8")
    comments = re.findall(r'<div class="commtext[^"]*">(.*?)</div>', page, re.S)
    prose = "\n".join(html.unescape(re.sub(r"<[^>]+>", "", re.sub(r"<p>", "\n", c))) for c in comments)
    f.write("prose : String\nprose =\n    " + elm_string(prose[:100000]) + "\n")
