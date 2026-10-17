"""Measure how far a button's contents sit from the middle of its face.

Studio's screen_capture is SCALED DOWN from the real viewport (e.g. 2278 wide
-> 1920), so pixel errors read off a screenshot are not real pixels. This tool
takes rects in real viewport pixels (GuiObject.AbsolutePosition / AbsoluteSize,
from a ScreenGui with IgnoreGuiInset = true, or add the 58 px inset yourself)
and converts.

The FACE is the coloured part of a chunky button, not the image box: the dark
ink outline and the bottom lip are left out. It is found from a column near the
left edge (FACE_COLUMN of the width): the longest run of rows lighter than
--dark. CONTENT is every near-white pixel (text fill, white icons) inside the
face, optionally limited to an x range so text and icon can be checked apart.

usage:
  python ui_center_check.py SHOT.jpg VIEWPORT_W  NAME x y w h [ts] [NAME x y w h [ts] ...]
options (before the shot):
  --dark 90       luma below this is ink/lip, not face
  --white 205     all channels above this count as content
  --xfrom 0.0 --xto 1.0   content x range, as fractions of the rect width
  --col 0.06      where to look for the face, as a fraction of the width (move it
                  past rounded corners on short pills)
  --box 1         treat the whole rect as the face (plain text in its label box)
prints, per rect: face rows, content box, and dx / dy (content centre minus
face centre, in real px; + = right / low), plus dy / ts when ts is given.
"""

import sys
from PIL import Image

FACE_COLUMN = 0.06


def luma(p):
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def main(argv):
    opts = {"--dark": 90.0, "--white": 205.0, "--xfrom": 0.0, "--xto": 1.0, "--col": FACE_COLUMN, "--box": 0.0}
    while argv and argv[0] in opts:
        opts[argv[0]] = float(argv[1])
        argv = argv[2:]
    shot, vw, rest = argv[0], float(argv[1]), argv[2:]
    im = Image.open(shot).convert("RGB")
    px = im.load()
    s = im.size[0] / vw
    while rest:
        name, x, y, w, h = rest[0], *map(float, rest[1:5])
        rest = rest[5:]
        ts = None
        if rest and not rest[0][0].isalpha():
            ts = float(rest[0])
            rest = rest[1:]
        X0, Y0, X1, Y1 = int(x * s), int(y * s), int((x + w) * s), int((y + h) * s)
        # face rows: longest light run down a column near the left edge
        col = X0 + max(2, int((X1 - X0) * opts["--col"]))
        best, run = (0, 0), None
        for yy in range(Y0, Y1):
            if luma(px[col, yy]) >= opts["--dark"]:
                run = run if run is not None else yy
                if yy - run > best[1] - best[0]:
                    best = (run, yy)
            else:
                run = None
        fy0, fy1 = best
        if opts["--box"]:
            fy0, fy1 = Y0, Y1 - 1
        cx0 = X0 + int((X1 - X0) * opts["--xfrom"])
        cx1 = X0 + int((X1 - X0) * opts["--xto"])
        xs, ys = [], []
        for yy in range(fy0, fy1 + 1):
            for xx in range(cx0, cx1):
                r, g, b = px[xx, yy]
                if min(r, g, b) > opts["--white"]:
                    xs.append(xx)
                    ys.append(yy)
        if not xs:
            print(f"{name}: no content found")
            continue
        face_cy = (fy0 + fy1) / 2 / s
        face_cx = (X0 + X1) / 2 / s
        cy = (min(ys) + max(ys)) / 2 / s
        cx = (min(xs) + max(xs)) / 2 / s
        line = (f"{name}: face y {fy0 / s - y:.1f}..{fy1 / s - y:.1f} of {h:.0f}  "
                f"content x {min(xs) / s - x:.1f}..{max(xs) / s - x:.1f} y {min(ys) / s - y:.1f}..{max(ys) / s - y:.1f}  "
                f"dx {cx - face_cx:+.1f}px  dy {cy - face_cy:+.1f}px")
        if ts:
            line += f"  (dy {(cy - face_cy) / ts:+.3f} ts)"
        print(line)


if __name__ == "__main__":
    main(sys.argv[1:])
