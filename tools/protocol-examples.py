"""Writes host/protocol/examples.json, with each message's bytes on the wire, as an Elm
module, ProtocolExamples, for elm/tests/ProtocolTest.elm (elm-test can't read files).
The bytes come from the host's own encoder: `cargo run -p protocol --bin
protocol-examples` prints them as {"toHost": [hex, ...], "fromHost": [hex, ...]}.

    python3 -I tools/protocol-examples.py host/protocol/examples.json HEX.json OUT.elm
"""
import json, sys

examples = json.load(open(sys.argv[1]))
wire = json.load(open(sys.argv[2]))


def elm_list(name, direction):
    # json.dumps of the compact JSON text is a valid Elm string literal for ASCII text
    # with \" \\ \n escapes, which is all the examples have.
    items = []
    for item, hex in zip(examples[direction], wire[direction], strict=True):
        text = json.dumps(json.dumps(item, separators=(",", ":")))
        if not text.isascii():
            sys.exit(f"{sys.argv[1]}: keep the examples ASCII")
        items.append(f"( {text}, {json.dumps(hex)} )")
    return (f"{name} : List ( String, String )\n{name} =\n    [ " + "\n    , ".join(items) + "\n    ]\n")


with open(sys.argv[3], "w") as out:
    out.write("module ProtocolExamples exposing (fromHost, toHost)\n\n"
              "{-| Written by tools/protocol-examples.py from host/protocol/examples.json: each\n"
              "example as JSON, and its bytes on the wire in hex. -}\n\n\n")
    out.write(elm_list("toHost", "toHost"))
    out.write("\n\n")
    out.write(elm_list("fromHost", "fromHost"))
