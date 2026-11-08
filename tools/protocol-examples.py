"""Writes host/protocol/examples.json as an Elm module, ProtocolExamples, for
elm/tests/ProtocolTest.elm (elm-test can't read files).

    python3 -I tools/protocol-examples.py host/protocol/examples.json OUT.elm
"""
import json, sys

examples = json.load(open(sys.argv[1]))


def elm_list(name, items):
    # json.dumps of the compact JSON text is a valid Elm string literal for ASCII text
    # with \" \\ \n escapes, which is all the examples have.
    lines = [json.dumps(json.dumps(item, separators=(",", ":"))) for item in items]
    for line in lines:
        if not line.isascii():
            sys.exit(f"{sys.argv[1]}: keep the examples ASCII")
    return f"{name} : List String\n{name} =\n    [ " + "\n    , ".join(lines) + "\n    ]\n"


with open(sys.argv[2], "w") as out:
    out.write("module ProtocolExamples exposing (fromHost, render, toHost)\n\n"
              "{-| Written by tools/protocol-examples.py from host/protocol/examples.json. -}\n\n\n")
    out.write(elm_list("toHost", examples["toHost"]))
    out.write("\n\n")
    out.write(elm_list("fromHost", examples["fromHost"]))
    out.write("\n\n")
    out.write(f"render : String\nrender =\n    {json.dumps(examples['render'])}\n")
