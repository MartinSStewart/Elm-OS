# Download Mesa (EGL, GLES2, GBM and the Gallium GPU drivers) and everything it
# links against from Alpine Linux, and unpack it into a directory.
#
#   usage: python3 -I tools/fetch-mesa.py OUT_DIR
#          python3 -I tools/fetch-mesa.py OUT_DIR PACKAGE...   just those packages
#
# alpine.lock (next to this repo's Makefile, committed) pins the exact package
# versions and their SHA-256s, so every machine unpacks the same files. When it has
# no entry for this set of packages, the newest versions in Alpine's index are used
# and added to it. `make refresh` empties it. Alpine keeps only the newest build of
# each package, so a pin can disappear upstream: then this stops and asks for a
# refresh (machines that already downloaded the files keep working from their cache).
#
# Alpine is built on musl, like the rest of Elm OS, and its Mesa package carries
# the drivers for virtio-gpu (virgl), Intel (iris, crocus), AMD (radeonsi), and
# llvmpipe, a CPU fallback. We only take the packages' files: no install scripts.
import fcntl, hashlib, io, os, sys, tarfile, urllib.error, urllib.request

ALPINE = os.environ.get("ALPINE_MIRROR", "https://dl-cdn.alpinelinux.org/alpine") + "/v3.22"
REPOS = ["main", "community"]
WANT = ["musl", "mesa-egl", "mesa-gles", "mesa-gbm", "mesa-dri-gallium", "libdrm"]
# Pulled in by Mesa for X11/Wayland window systems we never use, but the
# libraries must still resolve, so they stay. Headers are needed to compile
# the renderer: they come from these -dev packages.
DEV = ["mesa-dev", "libdrm-dev"]

out = os.path.abspath(sys.argv[1])
if sys.argv[2:]:  # e.g. linux-firmware-i915 for the USB stick
    WANT, DEV = sys.argv[2:], []
cache = os.path.join(os.path.dirname(out), "apk-cache")
LOCK = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "alpine.lock")
group = ",".join(WANT + DEV)
os.makedirs(cache, exist_ok=True)


def fetch(url, path):
    if not os.path.exists(path):
        print("fetch", url, file=sys.stderr)
        try:
            with urllib.request.urlopen(url) as r:
                data = r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404 and url.endswith(".apk"):
                sys.exit(f"{url}: Alpine no longer has this version, which alpine.lock pins. "
                         "Run `make refresh` to move to the newest versions.")
            raise
        with open(path + ".tmp", "wb") as f:
            f.write(data)
        os.rename(path + ".tmp", path)
    return path



def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def read_lock():
    """This package set's pins: [(repo, name, version, sha256)], or None."""
    try:
        lines = open(LOCK).read().splitlines()
    except FileNotFoundError:
        return None
    pins = [l.split()[1:] for l in lines if l.split() and l.split()[0] == group]
    return pins or None


def resolve_from_index():
    pkgs, provides = {}, {}
    for repo in REPOS:
        idx = fetch(f"{ALPINE}/{repo}/x86_64/APKINDEX.tar.gz", f"{cache}/APKINDEX-{repo}.tar.gz")
        with tarfile.open(idx) as t:
            text = t.extractfile("APKINDEX").read().decode()
        for block in text.split("\n\n"):
            f = {}
            for line in block.splitlines():
                if len(line) > 2 and line[1] == ":":
                    f[line[0]] = line[2:]
            if "P" not in f:
                continue
            f["repo"] = repo
            pkgs.setdefault(f["P"], f)
            for p in f.get("p", "").split():
                provides.setdefault(p.split("=")[0], f["P"])

    def resolve(dep):
        dep = dep.split("=")[0].split(">")[0].split("<")[0].split("~")[0]
        if dep.startswith("!"):
            return None
        if dep in pkgs:
            return dep
        return provides.get(dep)

    chosen, todo = [], list(WANT)
    while todo:
        name = resolve(todo.pop())
        if not name or name in chosen:
            continue
        chosen.append(name)
        todo += pkgs[name].get("D", "").split()
    chosen += [d for d in DEV if d not in chosen]
    return [(pkgs[n]["repo"], n, pkgs[n]["V"]) for n in sorted(chosen)]


pins = read_lock()
if pins is None:
    pins = []
    for repo, name, version in resolve_from_index():
        apk = fetch(f"{ALPINE}/{repo}/x86_64/{name}-{version}.apk", f"{cache}/{name}-{version}.apk")
        pins.append((repo, name, version, sha256(apk)))
    with open(LOCK, "a") as f:  # several of these can run at once under make -j
        fcntl.flock(f, fcntl.LOCK_EX)
        f.writelines(f"{group} {' '.join(p)}\n" for p in pins)
    print(f"alpine.lock: pinned {len(pins)} packages for {group}; commit it", file=sys.stderr)

os.makedirs(out, exist_ok=True)
for repo, name, version, digest in pins:
    apk = fetch(f"{ALPINE}/{repo}/x86_64/{name}-{version}.apk", f"{cache}/{name}-{version}.apk")
    if sha256(apk) != digest:
        os.remove(apk)
        sys.exit(f"{apk} doesn't match its SHA-256 in alpine.lock")
    # An .apk is three gzip streams glued together (signature, control, data);
    # tarfile reads through all of them as one archive.
    with tarfile.open(apk, "r:gz") as t:
        for m in t.getmembers():
            if m.name.startswith("."):
                continue
            t.extract(m, out, filter="tar")
    print(f"{name} {version}", file=sys.stderr)
print(f"{len(pins)} packages", file=sys.stderr)
