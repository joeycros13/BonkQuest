"""Hotbar slot background for DiceBattles: a soft, see-through glossy bubble.

Frosted face (lighter on top), soft drop shadow, thin soft outline, bright
inner rim along the top and a gloss highlight. Uses artkit.py.
Usage: python slot_bg.py [out.png]
"""
import sys
from artkit import Canvas

OUT = sys.argv[1] if len(sys.argv) > 1 else "slot_bg.png"
c = Canvas(512, 3)

FACE_BOX = (52, 44, 460, 452)
face = c.ellipse(FACE_BOX)

# soft drop shadow, a little below -- only OUTSIDE the face, so the see-through
# face shows the world behind it, not a shadow
shadow = c.blur(c.shift(c.ellipse((60, 60, 452, 452)), 0, 16), 14)
c.fill(c.mask_sub(shadow, c.ellipse(FACE_BOX, 2)), (20, 14, 30, 255), 0.45)
# thin soft outline: a RING around the face (a filled disc would grey the face)
c.glow(c.mask_sub(c.ellipse(FACE_BOX, 7), c.ellipse(FACE_BOX)), (40, 30, 46, 255), 1.5, 0.75)
# frosted face: brighter at the top, a touch warmer and darker at the bottom
c.vgrad(face, FACE_BOX, (255, 252, 246, 150), (240, 232, 226, 90))
# depth: darken toward the bottom edge inside the face
c.vgrad(face, (52, 280, 460, 452), (0, 0, 0, 0), (60, 46, 70, 255), 0.18)
# bright inner rim, strongest on top
rim = c.mask_sub(c.ellipse(FACE_BOX), c.ellipse((64, 56, 448, 440)))
c.vgrad(rim, FACE_BOX, (255, 255, 255, 255), (255, 255, 255, 0), 0.9)
# gloss highlight across the upper face
gloss = c.ellipse((104, 66, 408, 236))
c.vgrad(c.blur(gloss, 3), (104, 66, 408, 236), (255, 255, 255, 255), (255, 255, 255, 0), 0.55)

c.save(OUT)
print("saved", OUT)
