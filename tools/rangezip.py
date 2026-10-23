import io, sys, zipfile, urllib.request
class HttpFile(io.RawIOBase):
    def __init__(s, url):
        s.url = url; s.pos = 0
        r = urllib.request.urlopen(urllib.request.Request(url, method="HEAD"))
        s.size = int(r.headers["Content-Length"]); s.url = r.geturl()
    def seekable(s): return True
    def readable(s): return True
    def tell(s): return s.pos
    def seek(s, off, whence=0):
        s.pos = off if whence == 0 else s.pos + off if whence == 1 else s.size + off
        return s.pos
    def read(s, n=-1):
        if n < 0: n = s.size - s.pos
        if n == 0 or s.pos >= s.size: return b""
        end = min(s.size, s.pos + n) - 1
        req = urllib.request.Request(s.url, headers={"Range": f"bytes={s.pos}-{end}"})
        data = urllib.request.urlopen(req).read()
        s.pos += len(data); return data
    def readinto(s, b):
        d = s.read(len(b)); b[:len(d)] = d; return len(d)
url, out, *names = sys.argv[1:]
z = zipfile.ZipFile(io.BufferedReader(HttpFile(url), 1 << 20))
for n in z.namelist():
    if any(x in n for x in names) or n.endswith("version.txt"):
        print("extract", n); z.extract(n, out)
