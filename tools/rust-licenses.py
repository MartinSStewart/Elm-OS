# Write the license files of every Rust crate built into Elm OS's own programs (/init
# and the GPU renderer) into one text file, for /usr/share/licenses in the initramfs.
#
#   usage: python3 -I tools/rust-licenses.py OUT_FILE
#
# Follows only normal (not build or dev) dependencies of elmos-host and elmos-gpu for
# the musl target, skipping proc-macro crates (they run in the compiler and nothing of
# them is in the binaries) and our own crates (they're under LICENSE). OUT_FILE lists
# each crate with its declared license, then each distinct LICENSE*, COPYING*, NOTICE*
# or COPYRIGHT* text once, headed by the crates that ship it.
import json, os, subprocess, sys

out = sys.argv[1]
host = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "host")
meta = json.loads(subprocess.run(
    ["cargo", "metadata", "--format-version", "1", "--locked",
     "--filter-platform", "x86_64-unknown-linux-musl"],
    cwd=host, check=True, capture_output=True).stdout)
pkgs = {p["id"]: p for p in meta["packages"]}
nodes = {n["id"]: n for n in meta["resolve"]["nodes"]}
todo = [i for i, p in pkgs.items() if p["name"] in ("elmos-host", "elmos-gpu")]
seen = set()
while todo:
    i = todo.pop()
    if i in seen:
        continue
    seen.add(i)
    if any("proc-macro" in t["kind"] for t in pkgs[i]["targets"]):
        continue
    for d in nodes[i]["deps"]:
        if any(k["kind"] is None for k in d["dep_kinds"]):
            todo.append(d["pkg"])

lines, texts = [], {}
for p in sorted((pkgs[i] for i in seen if pkgs[i]["source"]
                 and not any("proc-macro" in t["kind"] for t in pkgs[i]["targets"])),
                key=lambda p: (p["name"], p["version"])):
    src = os.path.dirname(p["manifest_path"])
    name = f'{p["name"]} {p["version"]}'
    files = sorted(f for f in os.listdir(src)
                   if f.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE", "COPYRIGHT"))
                   and os.path.isfile(os.path.join(src, f)))
    for f in files:
        with open(os.path.join(src, f), encoding="utf-8", errors="replace") as h:
            texts.setdefault(h.read().strip(), []).append(f"{name} ({f})")
    lines.append(f'{name}: {p["license"] or "?"}' + ("" if files else " (the crate ships no license file)"))
with open(out + ".tmp", "w") as f:
    f.write("Rust crates built into /init and /usr/bin/elmos-gpu, with their declared licenses.\n"
            "Their license texts follow, each once.\n\n" + "\n".join(lines) + "\n")
    for text, users in texts.items():
        f.write("\n" + "=" * 72 + "\n" + "\n".join(users) + "\n" + "=" * 72 + "\n\n" + text + "\n")
os.replace(out + ".tmp", out)
