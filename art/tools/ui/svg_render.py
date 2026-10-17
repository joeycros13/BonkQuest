"""Render SVG icons to transparent PNGs through a browser (no cairo needed).

The icons are designed as inline SVGs on a Claude Design canvas artboard; every
<svg data-export="name"> in that .dc.html is an exportable icon. This script:
  1. pulls those SVGs out of the artboard file,
  2. serves a page that draws each one onto a <canvas> at SIZE px,
  3. receives the PNGs back (POST /save/<name>.png) and writes them to OUT.

Usage: python svg_render.py <artboard.dc.html> <out_dir> [size] [port]
Then open http://127.0.0.1:<port>/render.html in a browser (the built-in
browser pane works); the page shows each render and "done" when finished.
"""
import http.server
import os
import re
import sys

SRC, OUT = sys.argv[1], sys.argv[2]
SIZE = int(sys.argv[3]) if len(sys.argv) > 3 else 512
PORT = int(sys.argv[4]) if len(sys.argv) > 4 else 8770
os.makedirs(OUT, exist_ok=True)


def exports():
    html = open(SRC, encoding="utf-8").read()
    found = {}
    for m in re.finditer(r'<svg\b[^>]*data-export="([^"]+)"[^>]*>.*?</svg>', html, re.S):
        svg = m.group(0)
        head_end = svg.index(">") + 1
        # only the outer <svg> tag's size/style is the artboard's; inner rects keep theirs
        head = re.sub(r'\s(width|height|style)="[^"]*"', "", svg[:head_end])
        # keep the viewBox's shape: the longer side gets SIZE pixels
        vb = re.search(r'viewBox="\s*[-\d.]+\s+[-\d.]+\s+([\d.]+)\s+([\d.]+)"', head)
        vw, vh = (float(vb.group(1)), float(vb.group(2))) if vb else (1.0, 1.0)
        w, h = (SIZE, round(SIZE * vh / vw)) if vw >= vh else (round(SIZE * vw / vh), SIZE)
        head = head.replace("<svg ", f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" ', 1)
        svg = head + svg[head_end:]
        found[m.group(1)] = {"svg": svg, "w": w, "h": h}
    return found


PAGE = """<!doctype html><meta charset="utf-8"><title>render</title>
<body style="background:#333;color:#fff;font:14px sans-serif">
<div id="log"></div><script>
const SVGS = %s, SIZE = %d;
(async () => {
  for (const [name, item] of Object.entries(SVGS)) {
    const img = new Image();
    img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(item.svg);
    await img.decode();
    const c = document.createElement("canvas"); c.width = item.w; c.height = item.h;
    c.getContext("2d").drawImage(img, 0, 0, item.w, item.h);
    const blob = await new Promise(r => c.toBlob(r, "image/png"));
    await fetch("/save/" + name + ".png", {method: "POST", body: blob});
    c.style.cssText = "width:96px;height:96px;margin:4px;background:#5a8";
    document.body.appendChild(c);
    log.textContent += name + " ";
  }
  log.textContent += " done";
  document.title = "done";
})();
</script>"""


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        import json
        body = (PAGE % (json.dumps(exports()), SIZE)).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        name = os.path.basename(self.path.split("/save/", 1)[-1])
        data = self.rfile.read(int(self.headers["Content-Length"]))
        with open(os.path.join(OUT, name), "wb") as f:
            f.write(data)
        print("saved", name, len(data), flush=True)
        self.send_response(204)
        self.end_headers()


print("serving", list(exports()), "on", PORT, flush=True)
http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
