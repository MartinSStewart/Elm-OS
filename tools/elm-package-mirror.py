# Minimal package.elm-lang.org stand-in for sandboxes where it is blocked.
# usage: python3 -I mirror.py PORT author/pkg@ver ...
import hashlib, http.server, json, os, shutil, subprocess, sys, tempfile, zipfile
port = int(sys.argv[1]); root = os.path.dirname(os.path.abspath(__file__)) + "/data"
os.makedirs(root, exist_ok=True)
pkgs = {}
for spec in sys.argv[2:]:
    name, ver = spec.split("@")
    d = f"{root}/{name}/{ver}"
    if not os.path.exists(d + "/pkg.zip"):
        os.makedirs(d, exist_ok=True)
        src = tempfile.mkdtemp()
        subprocess.run(["git", "clone", "-q", "--depth", "1", "--branch", ver, f"https://github.com/{name}", src], check=True)
        shutil.rmtree(src + "/.git")
        top = name.split("/")[1] + "-" + ver
        with zipfile.ZipFile(d + "/pkg.zip", "w") as z:
            z.writestr(top + "/", "")
            for dp, ds, fs in os.walk(src):
                ds.sort()
                for sub in ds:
                    z.writestr(top + "/" + os.path.relpath(os.path.join(dp, sub), src) + "/", "")
                for f in sorted(fs):
                    full = os.path.join(dp, f)
                    z.write(full, top + "/" + os.path.relpath(full, src))
        shutil.copy(src + "/elm.json", d + "/elm.json")
    pkgs.setdefault(name, []).append(ver)
class H(http.server.BaseHTTPRequestHandler):
    def send(self, body, ctype="application/json"):
        self.send_response(200); self.send_header("content-type", ctype)
        self.send_header("content-length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_POST(self): self.do_GET()
    def do_GET(self):
        p = self.path.split("?")[0]
        if p.startswith("/all-packages/since/"):
            return self.send(b"[]")
        if p == "/all-packages":
            return self.send(json.dumps(pkgs).encode())
        parts = p.strip("/").split("/")  # packages/author/pkg/ver/file
        if len(parts) == 5 and parts[0] == "packages":
            d = f"{root}/{parts[1]}/{parts[2]}/{parts[3]}"
            if parts[4] == "elm.json":
                return self.send(open(d + "/elm.json", "rb").read())
            if parts[4] == "endpoint.json":
                h = hashlib.sha1(open(d + "/pkg.zip", "rb").read()).hexdigest()
                return self.send(json.dumps({"url": f"http://127.0.0.1:{port}/zip/{parts[1]}/{parts[2]}/{parts[3]}", "hash": h}).encode())
        if len(parts) == 4 and parts[0] == "zip":
            return self.send(open(f"{root}/{parts[1]}/{parts[2]}/{parts[3]}/pkg.zip", "rb").read(), "application/zip")
        self.send_response(404); self.end_headers()
http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
