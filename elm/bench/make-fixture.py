# Writes an Elm module with the HTML fixtures as String constants, so the benchmark
# (Bench.elm) needs no file reading.  usage: python3 -I make-fixture.py OUT TOP.gz ITEM.gz
import gzip, os, re, sys


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
    f.write("module Fixture exposing (itemId, item, top)\n\n\n")
    f.write("itemId : String\nitemId =\n    " + elm_string(item_id) + "\n\n\n")
    for name, path in (("top", top), ("item", item)):
        text = gzip.open(path, "rb").read().decode("utf-8")
        f.write(name + " : String\n" + name + " =\n    " + elm_string(text) + "\n\n\n")
