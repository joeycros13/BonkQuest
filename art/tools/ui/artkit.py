"""Shared helpers for the DiceBattles icon and UI scripts (PIL only, no numpy).

Everything is drawn on a supersampled RGBA canvas through masks:
  canvas.fill(mask, color)                 flat colour inside a mask
  canvas.vgrad(mask, box, top, bottom)     vertical gradient inside a mask
  canvas.hgrad(mask, box, left, right)     horizontal gradient inside a mask
  canvas.radial(mask, centre, r, inner, outer)  radial gradient inside a mask
  canvas.glow(mask, color, blur)           a soft (blurred) shape: shadows, highlights
Masks come from rrect / ellipse / shape(...) and combine with mask_and/or/sub.
Coordinates are in final-image pixels; the canvas scales them by `ss`.
Canvas(w) is square; Canvas(w, h=...) is a w x h rectangle.
"""
import math
from PIL import Image, ImageDraw, ImageFilter, ImageChops


class Canvas:
    def __init__(self, size=512, ss=3, h=None):
        self.w, self.h = size, (h or size)
        self.size = size  # (kept for older scripts: square canvases)
        self.ss = ss
        self.W, self.H = self.w * ss, self.h * ss
        self.S = self.W
        self.img = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))

    # ---- masks ----
    def blank(self, value=0):
        return Image.new("L", (self.W, self.H), value)

    def shape(self, draw):
        """draw(d, k) draws white shapes on an L image; k scales image px to canvas px."""
        m = self.blank()
        draw(ImageDraw.Draw(m), self.ss)
        return m

    def rrect(self, box, r, grow=0):
        k = self.ss
        x0, y0, x1, y1 = box
        return self.shape(lambda d, k=k: d.rounded_rectangle(
            [(x0 - grow) * k, (y0 - grow) * k, (x1 + grow) * k, (y1 + grow) * k], radius=max(0, r + grow) * k, fill=255))

    def ellipse(self, box, grow=0):
        k = self.ss
        x0, y0, x1, y1 = box
        return self.shape(lambda d, k=k: d.ellipse([(x0 - grow) * k, (y0 - grow) * k, (x1 + grow) * k, (y1 + grow) * k], fill=255))

    def polygon(self, points):
        k = self.ss
        return self.shape(lambda d, k=k: d.polygon([(x * k, y * k) for x, y in points], fill=255))

    def everything(self):
        return self.blank(255)

    def blob(self, points, steps=14):
        """A smooth closed shape through `points` (Catmull-Rom spline)."""
        return self.polygon(spline(points, True, steps))

    def stroke(self, points, width, steps=14, smooth=True):
        """A thick smooth curve through `points`, with round ends."""
        k = self.ss
        pts = spline(points, False, steps) if smooth and len(points) > 2 else list(points)

        def draw(d, k=k):
            d.line([(x * k, y * k) for x, y in pts], fill=255, width=int(width * k), joint="curve")
            r = width * k / 2
            for x, y in (pts[0], pts[-1]):
                d.ellipse([x * k - r, y * k - r, x * k + r, y * k + r], fill=255)
        return self.shape(draw)

    def dilate(self, mask, px):
        """Grow a mask by about `px` image pixels (for outlines around any shape)."""
        grown = mask.filter(ImageFilter.GaussianBlur(px * self.ss * 0.55))
        # a short ramp around the threshold keeps the new edge crisp but smooth
        return grown.point(lambda v: 0 if v < 8 else (255 if v >= 32 else int((v - 8) * 255 / 24)))

    @staticmethod
    def mask_and(a, b):
        return ImageChops.multiply(a, b)

    @staticmethod
    def mask_or(a, b):
        return ImageChops.lighter(a, b)

    @staticmethod
    def mask_sub(a, b):
        return ImageChops.subtract(a, b)

    def ring(self, box, r, width):
        """A rounded-rectangle ring `width` px thick, inside `box`."""
        return self.mask_sub(self.rrect(box, r), self.rrect(box, r, -width))

    def shift(self, mask, dx, dy):
        return ImageChops.offset(mask, int(dx * self.ss), int(dy * self.ss))

    def blur(self, mask, radius):
        return mask.filter(ImageFilter.GaussianBlur(radius * self.ss))

    # ---- painting ----
    def _paint(self, layer, mask, opacity=1.0):
        if opacity < 1:
            mask = mask.point(lambda v: int(v * opacity))
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
        self.img = Image.alpha_composite(self.img, layer)

    def solid(self, color):
        return Image.new("RGBA", (self.W, self.H), color)

    @staticmethod
    def _pair(a, b):
        """Fading to fully transparent should keep the other end's colour, or
        the blend passes through black and leaves a grey halo."""
        if len(a) == 4 and a[3] == 0:
            a = (b[0], b[1], b[2], 0)
        if len(b) == 4 and b[3] == 0:
            b = (a[0], a[1], a[2], 0)
        return a, b

    def fill(self, mask, color, opacity=1.0):
        self._paint(self.solid(color), mask, opacity)

    def _grad(self, mask, box, a, b, vertical, opacity):
        k = self.ss
        x0, y0, x1, y1 = [int(v * k) for v in box]
        g = Image.linear_gradient("L")  # 0 at the top -> 255 at the bottom
        if not vertical:
            g = g.rotate(90, expand=True)  # 0 at the left -> 255 at the right
        g = g.resize((max(1, x1 - x0), max(1, y1 - y0)))
        full = self.blank()
        if vertical:
            full.paste(255, (0, y1, self.W, self.H))
        else:
            full.paste(255, (x1, 0, self.W, self.H))
        full.paste(g, (x0, y0))
        a, b = self._pair(a, b)
        layer = Image.composite(self.solid(b), self.solid(a), full)
        self._paint(layer, mask, opacity)

    def vgrad(self, mask, box, top, bottom, opacity=1.0):
        self._grad(mask, box, top, bottom, True, opacity)

    def hgrad(self, mask, box, left, right, opacity=1.0):
        self._grad(mask, box, left, right, False, opacity)

    def radial(self, mask, centre, radius, inner, outer, opacity=1.0):
        """Radial gradient: `inner` at the centre fading to `outer` at `radius`."""
        k = self.ss
        # PIL's radial gradient is 256x256 with 0 at the centre and value ~1.41x
        # the distance (181 at the edge midpoint). Size it 2*radius across, then
        # stretch the values so 255 lands exactly on `radius` (the square's edge),
        # leaving no hard edge where the pasted square ends.
        d = max(2, int(radius * 2 * k))
        g = Image.radial_gradient("L").resize((d, d)).point(lambda v: min(255, int(v * 255 / 181)))
        full = self.blank(255)
        cx, cy = int(centre[0] * k), int(centre[1] * k)
        full.paste(g, (cx - d // 2, cy - d // 2))
        inner, outer = self._pair(inner, outer)
        layer = Image.composite(self.solid(outer), self.solid(inner), full)
        self._paint(layer, mask, opacity)

    def glow(self, mask, color, blur, opacity=1.0, clip=None):
        m = self.blur(mask, blur)
        if clip is not None:
            m = self.mask_and(m, clip)
        self.fill(m, color, opacity)

    def save(self, path):
        out = self.img.resize((self.w, self.h), Image.LANCZOS)
        out.save(path)
        return out


# ---- curves ----

def spline(points, closed=True, steps=14):
    """Catmull-Rom curve through `points`, as a list of (x, y)."""
    n = len(points)
    out = []
    count = n if closed else n - 1
    for i in range(count):
        p0 = points[(i - 1) % n] if closed else points[max(i - 1, 0)]
        p1 = points[i]
        p2 = points[(i + 1) % n] if closed else points[i + 1]
        p3 = points[(i + 2) % n] if closed else points[min(i + 2, n - 1)]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(
                0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                       + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in (0, 1)))
    if not closed:
        out.append(tuple(points[-1]))
    return out


# ---- small motifs ----

def die_mask(c, cx, cy, size, angle_deg, face):
    """A rounded die outline with `face` pips, rotated, as (outline_mask, pips_mask)."""
    a = math.radians(angle_deg)
    ca, sa = math.cos(a), math.sin(a)

    def rot(x, y):
        return (cx + x * ca - y * sa, cy + x * sa + y * ca)

    half = size / 2
    # an approximately rounded square: an octagon-ish polygon with cut corners
    cut = size * 0.22
    pts = [(-half + cut, -half), (half - cut, -half), (half, -half + cut), (half, half - cut),
           (half - cut, half), (-half + cut, half), (-half, half - cut), (-half, -half + cut)]
    outer = c.polygon([rot(x, y) for x, y in pts])
    inset = size * 0.12
    pts2 = [((x * (half - inset) / half), (y * (half - inset) / half)) for x, y in pts]
    inner = c.polygon([rot(x, y) for x, y in pts2])
    outline = c.mask_sub(outer, inner)
    spots = {
        1: [(0, 0)],
        2: [(-1, -1), (1, 1)],
        3: [(-1, -1), (0, 0), (1, 1)],
        4: [(-1, -1), (1, -1), (-1, 1), (1, 1)],
        5: [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)],
        6: [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1)],
    }[face]
    pip_r = size * 0.085
    step = size * 0.24
    pips = c.blank()
    for sx, sy in spots:
        px, py = rot(sx * step, sy * step)
        pips = c.mask_or(pips, c.ellipse((px - pip_r, py - pip_r, px + pip_r, py + pip_r)))
    return outline, pips
