"""Which art files are live? (2026-10-20, the art cleanup)

art/ keeps only the source of every image the game uses now (plus the generators in
tools/ and the branding). This finds the rest: it collects every image id the place and
src/ use, downloads Roblox's public thumbnail of each, and matches every PNG / JPG in art/
against them (both cropped to their visible pixels and shrunk to 24 x 24). A file within
3 of a live thumbnail is its source; anything far from all of them is old or unused.

1. In Studio's Edit datamodel, run the Luau below (execute_luau or the command bar) and
   save the comma list it returns to a text file:

       local ids, n = {}, 0
       local function grab(s)
           if type(s) == "string" then for id in s:gmatch("rbxassetid://(%d+)") do ids[id] = true end end
       end
       local props = { ImageLabel = { "Image" }, ImageButton = { "Image" }, Decal = { "Texture" },
           Texture = { "Texture" }, ParticleEmitter = { "Texture" }, Beam = { "Texture" }, Trail = { "Texture" } }
       for _, root in { workspace, game.ReplicatedStorage, game.ServerStorage, game.StarterGui,
               game.StarterPlayer, game.Lighting } do
           for _, d in root:GetDescendants() do
               n += 1 if n % 4000 == 0 then task.wait() end
               for _, p in props[d.ClassName] or {} do pcall(function() grab(d[p]) end) end
               for _, v in d:GetAttributes() do grab(v) end
           end
       end
       local out = {} for id in ids do table.insert(out, id) end
       return table.concat(out, ",")

2. python art_audit.py <repo> <ids.txt> <cache folder>   (needs Pillow; prints one line per
   file: distance, LIVE / near / ----, path, closest id). A thumbnail Roblox is still
   rendering comes back "Pending": run it again a minute later.
"""
import json, os, re, sys, time, urllib.request

from PIL import Image

repo, place_ids_file, cache = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(cache, exist_ok=True)

ids = set(open(place_ids_file).read().replace("\n", ",").split(","))
for root, _, files in os.walk(os.path.join(repo, "src")):
    for f in files:
        t = open(os.path.join(root, f), encoding="utf-8", errors="ignore").read()
        ids.update(re.findall(r"rbxassetid://(\d+)", t))
ids = sorted(i.strip() for i in ids if i.strip().isdigit())
print("live ids:", len(ids), file=sys.stderr)


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


urls = {}
for k in range(0, len(ids), 50):
    batch = ids[k:k + 50]
    for attempt in range(6):
        data = json.loads(fetch("https://thumbnails.roblox.com/v1/assets?assetIds=" + ",".join(batch)
                                + "&returnPolicy=PlaceHolder&size=420x420&format=Png&isCircular=false"))
        for d in data["data"]:
            if d["state"] == "Completed":
                urls[str(d["targetId"])] = d["imageUrl"]
        if not any(d["state"] == "Pending" for d in data["data"]):
            break
        time.sleep(2)


def sig(img):
    img = img.convert("RGBA")
    box = img.split()[3].point(lambda v: 255 if v > 24 else 0).getbbox()
    if box:
        img = img.crop(box)
    bg = Image.new("RGBA", img.size, (128, 128, 128, 255))
    bg.alpha_composite(img)
    return list(bg.convert("RGB").resize((24, 24), Image.BILINEAR).getdata()), img.size[0] / max(1, img.size[1])


live = {}
for i, u in urls.items():
    path = os.path.join(cache, i + ".png")
    try:
        if not os.path.exists(path):
            open(path, "wb").write(fetch(u))
        live[i] = sig(Image.open(path))
    except Exception as e:
        print("skipped", i, e, file=sys.stderr)
print("thumbnails:", len(live), "of", len(ids), file=sys.stderr)


def diff(a, b):
    (pa, ra), (pb, rb) = a, b
    d = sum(abs(x - y) for p, q in zip(pa, pb) for x, y in zip(p, q)) / (24 * 24 * 3)
    return d + (40 if max(ra, rb) / max(1e-6, min(ra, rb)) > 1.25 else 0)  # a different shape


for root, _, files in sorted(os.walk(os.path.join(repo, "art"))):
    for f in sorted(files):
        if not f.lower().endswith((".png", ".jpg")):
            continue
        full = os.path.join(root, f)
        try:
            s = sig(Image.open(full))
        except Exception:
            continue
        d, i = min(((diff(s, v), i) for i, v in live.items()), default=(999.0, None))
        tag = "LIVE" if d < 3 else ("near" if d < 12 else "----")
        print(f"{d:6.1f} {tag} {os.path.relpath(full, repo).replace(os.sep, '/')} {i}")
