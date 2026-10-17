"""DiceBattles backpack icon, v4: a real 3D model rendered in cartoon style.

The bag is built from rounded 3D shapes (superquadrics for the body and
pockets, swept tubes for the straps and handle), viewed from above and from
the front corner, the way the user's reference shows a backpack, so the front,
the side, the top and the straps curving round the back all show.

Rendering (PIL only): every surface is a fine mesh; facets are shaded
(soft cel lighting from the upper left), back faces are culled, everything is
drawn far-to-near, contour edges get a dark line, seams / zips / stitching are
3D curves on the surfaces, and a thick outer outline goes round the whole
silhouette. Usage: python backpack3d.py [out.png]
"""
import math
import sys

from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "backpack_icon.png"
SIZE, SS = 512, 3
S = SIZE * SS

# ---------------- tuning ----------------
YAW, PITCH, ROLL = -36, 24, -8          # camera: turn, look-down, lean (degrees)
CAM_DIST = 9.0                          # perspective strength (bigger = flatter)
LIGHT = (-0.55, 0.75, 0.55)             # light direction in camera space
INK = (58, 32, 12)
CONTOUR_W = 3.4                         # contour line width (final px)
OUTER_W = 6                             # outer outline width (final px)

BODY = ((255, 182, 88), (180, 86, 22))
BASE = ((196, 108, 40), (118, 54, 16))
POCKET = ((112, 226, 210), (26, 128, 122))
STRAP = ((196, 112, 50), (104, 50, 16))
GOLD = ((255, 230, 120), (196, 134, 24))


# ---------------- vector helpers ----------------
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def mul(a, k): return (a[0] * k, a[1] * k, a[2] * k)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def norm(a):
    l = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / l, a[1] / l, a[2] / l)


def rotation(yaw, pitch, roll):
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    cr, sr = math.cos(math.radians(roll)), math.sin(math.radians(roll))

    def r(p):
        x, y, z = p
        x, z = x * cy + z * sy, -x * sy + z * cy          # yaw about Y
        y, z = y * cp - z * sp, y * sp + z * cp           # pitch about X (top tips toward camera)
        x, y = x * cr - y * sr, x * sr + y * cr           # roll about Z
        return (x, y, z)
    return r


ROT = rotation(YAW, PITCH, ROLL)
L = norm(LIGHT)
H = norm(add(L, (0, 0, 1)))


def sgnpow(v, m):
    return math.copysign(abs(v) ** m, v)


# ---------------- shapes (model space: x right, y up, z = the bag's front) ----------------
def superquadric(centre, a, b, d, e1, e2, deform=None, orient=None):
    def f(phi, theta):
        cp, sp = math.cos(phi), math.sin(phi)
        ct, st = math.cos(theta), math.sin(theta)
        p = (a * sgnpow(cp, e1) * sgnpow(ct, e2), b * sgnpow(sp, e1), d * sgnpow(cp, e1) * sgnpow(st, e2))
        if deform:
            p = deform(p)
        if orient:
            p = orient(p)
        return add(p, centre)
    return f


def body_deform(p):
    x, y, z = p
    t = y / 1.3
    x *= 1.0 - 0.10 * t                      # a little narrower at the top
    if z > 0:
        z = z * 1.10 + 0.10 * (1 - t * t)    # the front bulges, most in the middle
    else:
        z *= 0.92
    if y < -1.0:                             # sag: the bottom spreads a touch
        x *= 1.0 + 0.06 * (-1.0 - y) / 0.3
    return (x, y, z)


BODY_F = superquadric((0, 0, 0), 1.0, 1.3, 0.62, 0.52, 0.42, body_deform)
POCKET_F = superquadric((-0.02, -0.64, 0.6), 0.74, 0.48, 0.34, 0.5, 0.45)
SIDE_F = superquadric((1.0, -0.6, -0.16), 0.2, 0.4, 0.32, 0.5, 0.5,
                      orient=lambda p: (p[2], p[1], -p[0]))  # its front faces +x


def catmull3(points, steps):
    out = []
    n = len(points)
    for i in range(n - 1):
        p0, p1, p2, p3 = points[max(i - 1, 0)], points[i], points[i + 1], points[min(i + 2, n - 1)]
        for s in range(steps):
            t = s / steps
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t * t * t) for j in range(3)))
    out.append(points[-1])
    return out


def tube(path, w, t, ref=(0, 0, 1), steps=10):
    """A swept tube along `path`: half-width `w` and half-thickness `t`."""
    pts = catmull3(path, steps)
    frames = []
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
        T = norm(sub(b, a))
        B1 = norm(cross(T, ref))
        B2 = norm(cross(T, B1))
        frames.append((p, B1, B2))
    n_along = len(pts) - 1

    def f(u, v):  # u in [0,1] along, v angle
        i = min(int(u * n_along + 1e-6), n_along)
        p, B1, B2 = frames[i]
        return add(p, add(mul(B1, w * math.cos(v)), mul(B2, t * math.sin(v))))
    return f, n_along


# ---------------- meshing ----------------
layers = {}  # name -> [(depth, kind, data)]
LAYER_ORDER = ["straps", "body", "side", "pocket", "handle"]
items = None


def layer(name):
    """Send everything queued from now on to this part's layer."""
    global items
    items = layers.setdefault(name, [])


def to_cam(p):
    return ROT(p)


def project(c):
    k = CAM_DIST / (CAM_DIST - c[2])
    return (c[0] * k, -c[1] * k)


def shade(n, colours, extra=0.0):
    light, dark = colours
    diffuse = max(0.0, dot(n, L))
    s = 0.28 + 0.72 * diffuse
    s = s * s * (3 - 2 * s)                 # soft cel ramp
    s = min(1.0, s + extra)
    col = tuple(dark[i] + (light[i] - dark[i]) * s for i in range(3))
    spec = max(0.0, dot(n, H)) ** 40
    col = tuple(min(255, c + 255 * 0.35 * spec) for c in col)
    rim = (1 - max(0.0, n[2])) ** 3 * 0.18   # a little light on the turning edges
    return tuple(int(min(255, c + 255 * rim)) for c in col)


def mesh(f, nu, nv, u_range, v_range, colour_fn, wrap_v=True, closed_u=False):
    """Mesh a surface f(u, v); queue its visible facets and contour edges."""
    us = [u_range[0] + (u_range[1] - u_range[0]) * i / nu for i in range(nu + 1)]
    vs = [v_range[0] + (v_range[1] - v_range[0]) * j / nv for j in range(nv + (0 if wrap_v else 1))]
    nvv = len(vs)
    P = [[to_cam(f(u, v)) for v in vs] for u in us]
    model = [[f(u, v) for v in vs] for u in us]
    facing = {}
    quads = {}
    for i in range(nu):
        for j in range(nvv if wrap_v else nvv - 1):
            jn = (j + 1) % nvv
            a, b, c, d = P[i][j], P[i][jn], P[i + 1][jn], P[i + 1][j]
            n = norm(cross(sub(c, a), sub(b, d)))
            centre = mul(add(add(a, b), add(c, d)), 0.25)
            view = norm(sub((0, 0, CAM_DIST), centre))
            front = dot(n, view)
            if abs(dot(n, n) - 1) > 0.5:
                front = 0
            facing[(i, j)] = front > 0
            quads[(i, j)] = (a, b, c, d, n, centre, model[i][j])
    for (i, j), (a, b, c, d, n, centre, mp) in quads.items():
        if not facing[(i, j)]:
            continue
        if dot(n, norm(sub((0, 0, CAM_DIST), centre))) < 0:
            n = mul(n, -1)
        colour = shade(n, colour_fn(mp))
        items.append((centre[2], "poly", ([project(a), project(b), project(c), project(d)], colour)))
        # contour edges: shared with a neighbour that faces away
        jn = (j + 1) % nvv
        for (ni, nj), edge in (((i, j - 1 if wrap_v else j - 1), (a, d)), ((i, jn if wrap_v else j + 1), (b, c)),
                               ((i - 1, j), (a, b)), ((i + 1, j), (d, c))):
            if wrap_v:
                nj %= nvv
            neighbour = facing.get((ni, nj))
            if neighbour is False or (neighbour is None and not (ni < 0 or ni >= nu) is False and not closed_u):
                items.append((centre[2] + 0.002, "line", ([project(edge[0]), project(edge[1])], CONTOUR_W, INK)))


def curve_on(f, params, colour=INK, width=2.4, dash=False, lift=0.012):
    """A seam / zip / stitch line along surface points f(u, v) for (u, v) in params."""
    pts = []
    for u, v in params:
        p = f(u, v)
        q = f(u + 1e-3, v)
        r = f(u, v + 1e-3)
        n = norm(cross(sub(q, p), sub(r, p)))
        if dot(n, sub(p, (0, 0, 0))) < 0:
            n = mul(n, -1)
        pts.append(to_cam(add(p, mul(n, lift))))
    for k in range(len(pts) - 1):
        if dash and k % 2:
            continue
        a, b = pts[k], pts[k + 1]
        items.append(((a[2] + b[2]) / 2 + 0.004, "line", ([project(a), project(b)], width, colour)))


def blob_at(p, r, colours):
    c = to_cam(p)
    items.append((c[2] + 0.02, "dot", (project(c), r * CAM_DIST / (CAM_DIST - c[2]), colours)))


rad = math.radians

# ---- body ----
layer("body")
mesh(BODY_F, 90, 140, (rad(-90), rad(90)), (rad(-180), rad(180)),
     lambda p: BASE if p[1] < -1.02 else BODY, closed_u=True)
# front panel piping, the domed top zip, and the base seam
for theta in (38, 142):
    curve_on(BODY_F, [(rad(phi), rad(theta)) for phi in range(-70, 76, 4)], width=2.6)
    curve_on(BODY_F, [(rad(phi), rad(theta + (8 if theta < 90 else -8))) for phi in range(-64, 70, 3)],
             colour=(255, 226, 170), width=1.6, dash=True)
zip_path = [(10, 168), (40, 150), (64, 128), (78, 100), (80, 90), (78, 80), (64, 52), (40, 30), (10, 12)]
zp = []
for (pa, ta), (pb, tb) in zip(zip_path, zip_path[1:]):
    for s in range(6):
        t = s / 6
        zp.append((rad(pa + (pb - pa) * t), rad(ta + (tb - ta) * t)))
curve_on(BODY_F, zp, colour=(92, 44, 14), width=5.0)
curve_on(BODY_F, zp, colour=(232, 170, 90), width=1.6, dash=True, lift=0.02)
curve_on(BODY_F, [(rad(-57), rad(t)) for t in range(-178, 181, 4)], width=2.4)

# ---- front pocket ----
layer("pocket")
mesh(POCKET_F, 60, 96, (rad(-90), rad(90)), (rad(-180), rad(180)), lambda p: POCKET, closed_u=True)
for theta in (58, 90, 122):
    curve_on(POCKET_F, [(rad(phi), rad(theta)) for phi in range(-62, 50, 3)], colour=(18, 94, 90), width=2.2)
curve_on(POCKET_F, [(rad(54), rad(t)) for t in range(18, 163, 3)], colour=(14, 78, 74), width=4.6)
curve_on(POCKET_F, [(rad(54), rad(t)) for t in range(18, 163, 3)], colour=(150, 236, 224), width=1.4, dash=True, lift=0.02)

# ---- side pocket ----
layer("side")
mesh(SIDE_F, 28, 48, (rad(-90), rad(90)), (rad(-180), rad(180)), lambda p: POCKET, closed_u=True)
curve_on(SIDE_F, [(rad(48), rad(t)) for t in range(20, 161, 4)], colour=(14, 78, 74), width=3.4)

# ---- straps on the back, looping over the top and down ----
layer("straps")
for x0 in (-0.5, 0.5):
    path = [(x0 * 0.8, 0.98, -0.22), (x0 * 0.85, 1.12, -0.30), (x0 * 0.98, 1.34, -0.70), (x0 * 1.12, 0.95, -1.16),
            (x0 * 1.2, 0.2, -1.22), (x0 * 1.16, -0.6, -1.12), (x0 * 1.02, -1.12, -0.86), (x0 * 0.9, -1.25, -0.55), (x0 * 0.85, -1.1, -0.3)]
    f, n_along = tube(path, 0.17, 0.075, ref=(0, 0, 1), steps=18)
    mesh(f, n_along, 24, (0, 1), (0, 2 * math.pi), lambda p: STRAP)
    curve_on(f, [(u / 40, 0.0) for u in range(1, 40)], colour=(232, 170, 110), width=1.4, dash=True, lift=0.01)
# ---- carry loop on top ----
layer("handle")
hf, hn = tube([(-0.26, 1.18, -0.12), (-0.22, 1.46, -0.12), (0, 1.58, -0.12), (0.22, 1.46, -0.12), (0.26, 1.18, -0.12)],
              0.075, 0.075, ref=(0, 0, 1))
mesh(hf, hn, 14, (0, 1), (0, 2 * math.pi), lambda p: STRAP)

# ---- zip pulls ----
layer("body")
blob_at(BODY_F(rad(40), rad(150)), 0.075, GOLD)
layer("pocket")
blob_at(POCKET_F(rad(54), rad(140)), 0.07, GOLD)


# ---------------- draw ----------------
def frame_transform():
    xs, ys = [], []
    for _, kind, data in [it for name in LAYER_ORDER for it in layers.get(name, [])]:
        pts = data[0] if kind != "dot" else [data[0]]
        for x, y in pts:
            xs.append(x)
            ys.append(y)
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    margin = 40
    scale = min((SIZE - 2 * margin) / (x1 - x0), (SIZE - 2 * margin - 30) / (y1 - y0)) * SS
    ox = S / 2 - (x0 + x1) / 2 * scale
    oy = (S - 30 * SS) / 2 - (y0 + y1) / 2 * scale
    return lambda p: (p[0] * scale + ox, p[1] * scale + oy), scale, (y1 * scale + oy)


xf, scale, bottom = frame_transform()


def grow(mask, px):
    return mask.filter(ImageFilter.GaussianBlur(px * SS * 0.55)).point(
        lambda v: 0 if v < 8 else (255 if v >= 32 else int((v - 8) * 255 / 24)))


def render(part_items):
    layer_img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer_img)
    ordered = sorted(part_items, key=lambda it: it[0])
    for _, kind, data in ordered:
        if kind == "poly":
            pts, colour = data
            q = [xf(p) for p in pts]
            d.polygon(q, fill=colour + (255,), outline=colour + (255,))
    # soften facet-to-facet steps in the shading, keeping the silhouette crisp
    alpha = layer_img.getchannel("A")
    soft = layer_img.filter(ImageFilter.GaussianBlur(1.4 * SS))
    solid = alpha.point(lambda v: 255 if v == 255 else 0).filter(ImageFilter.MinFilter(5))
    layer_img = Image.composite(soft, layer_img, solid)
    layer_img.putalpha(alpha)
    d = ImageDraw.Draw(layer_img)
    for _, kind, data in ordered:
        if kind == "poly":
            continue
        if kind == "_unused":
            pts, colour = data
            q = [xf(p) for p in pts]
            d.polygon(q, fill=colour + (255,), outline=colour + (255,))
        elif kind == "line":
            pts, width, colour = data
            q = [xf(p) for p in pts]
            w = int(width * SS)
            d.line(q, fill=colour + (255,), width=w)
            r = w / 2
            for x, y in q:
                d.ellipse([x - r, y - r, x + r, y + r], fill=colour + (255,))
        elif kind == "dot":
            p, r, colours = data
            x, y = xf(p)
            r = r * scale
            o = CONTOUR_W * SS
            d.ellipse([x - r - o, y - r - o, x + r + o, y + r + o], fill=INK + (255,))
            d.ellipse([x - r, y - r, x + r, y + r], fill=colours[1] + (255,))
            d.ellipse([x - r * 0.85, y - r * 0.95, x + r * 0.55, y + r * 0.45], fill=colours[0] + (255,))
    return layer_img


ink_full = Image.new("RGBA", (S, S), INK + (255,))
clear = Image.new("RGBA", (S, S), (0, 0, 0, 0))
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
for name in LAYER_ORDER:
    part = render(layers.get(name, []))
    # every part gets its own dark outline, so it reads over the parts behind it
    img = Image.alpha_composite(img, Image.composite(ink_full, clear, grow(part.getchannel("A"), CONTOUR_W)))
    img = Image.alpha_composite(img, part)

# outer outline + soft ground shadow, behind everything
alpha = img.getchannel("A")
grown = alpha.filter(ImageFilter.GaussianBlur(OUTER_W * SS * 0.55)).point(lambda v: 0 if v < 8 else (255 if v >= 32 else int((v - 8) * 255 / 24)))
out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
shadow = Image.new("L", (S, S), 0)
cx = S / 2
ImageDraw.Draw(shadow).ellipse([cx - 150 * SS, bottom - 18 * SS, cx + 150 * SS, bottom + 22 * SS], fill=110)
shadow = shadow.filter(ImageFilter.GaussianBlur(12 * SS))
out.paste((50, 24, 4, 255), mask=shadow)
ink = Image.new("RGBA", (S, S), INK + (255,))
out = Image.alpha_composite(out, Image.composite(ink, Image.new("RGBA", (S, S), (0, 0, 0, 0)), grown))
out = Image.alpha_composite(out, img)
out.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
print("saved", OUT, {k: len(v) for k, v in layers.items()})
