"""Real-sprite pictures of maps through SpacemanDMM's dmm-tools (the copy tools/mapviewer downloads).

render(dmm_path, out_png, region=(x1,y1,x2,y2)) renders with the game's own icons from hippiestation.dme.
sheet(...) lays several pictures side by side with captions, for before/after reviews.
"""
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DME = os.path.join(ROOT, "hippiestation.dme")
sys.path.insert(0, os.path.join(ROOT, "tools", "mapviewer"))
# "pretty": what a player sees at roundstart (window spawners become grille + smoothed glass, random spawners roll,
# landmarks and mapping helpers hidden). "mapping": everything as written in the file, helpers shown.
MODES = {"pretty": ["icon-smoothing-2016", "icon-smoothing", "hide-space"],  # smoothing done by forge/smooth.py
         "mapping": ["icon-smoothing-2016", "hide-space", "hide-invisible", "random", "spawners"]}
DISABLE = MODES["pretty"]
PREVIEWS = os.path.join(ROOT, "data", "previews", "mapforge")


def dmm_tools():
    import mapviewer
    return mapviewer.get_dmm_tools()


def shade_with_light(img, snapshot, region):
    """Shade a region render with a lighting snapshot (data/mapforge/light_<name>.txt from run_zone_check.sh), the way
    the client multiplies its lighting overlay: each tile's gradient icon tinted by its four corner colours."""
    import numpy as np
    sys.path.insert(0, os.path.join(ROOT, "tools", "lighting_bench"))
    import render as lb  # tools/lighting_bench/render.py
    xs, ys, corners = lb.load_snapshot(snapshot)
    weights = lb.gradient_weights()
    x1, y1, x2, y2 = region
    tile = img.width // (x2 - x1 + 1)
    light = np.ones((img.height, img.width, 3), dtype=np.float32)  # no lighting object (space): unshaded
    keep = (xs >= x1) & (xs <= x2) & (ys >= y1) & (ys <= y2)
    if keep.any():
        blocks = np.einsum("hwc,ncr->nhwr", weights, corners[keep])
        for x, y, block in zip(xs[keep], ys[keep], blocks):
            top, left = (y2 - y) * 32, (x - x1) * 32
            light[top:top + 32, left:left + 32] = block
    if tile != 32:
        light = np.asarray(Image.fromarray((np.clip(light, 0, 1) * 255).astype(np.uint8)).resize((img.width, img.height))) / 255.0
    out = np.asarray(img).astype(np.float32) * np.clip(light, 0, 1)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def render(dmm_path, out_png, region=None, z=1, scale=1.0, disable=None, mode=None, light=None):
    mode = mode or ("pretty" if disable is None else None)
    if mode:
        disable = MODES[mode]
    tmp = tempfile.mkdtemp()
    try:
        text = open(dmm_path, encoding="utf-8", errors="replace").read()
        text = text.replace("/turf/template_noop", "/turf/open/floor/plating")
        src = os.path.join(tmp, "m.dmm")
        with open(src, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        if mode == "pretty":
            from forge import dmm, smooth
            m = dmm.read(src)
            smooth.prepare(m)
            dmm.write(m, src)
        cmd = [dmm_tools(), "-e", DME, "minimap", "-o", tmp, "--disable", ",".join(disable or DISABLE)]
        if region:
            cmd += ["--min", "%d,%d,%d" % (region[0], region[1], z), "--max", "%d,%d,%d" % (region[2], region[3], z)]
        r = subprocess.run(cmd + [src], cwd=ROOT, capture_output=True, text=True)
        produced = os.path.join(tmp, "m-%d.png" % z)
        if not os.path.exists(produced):
            raise RuntimeError("dmm-tools failed:\n" + r.stdout[-3000:] + r.stderr[-3000:])
        img = Image.open(produced).convert("RGB")
        if light and region:
            img = shade_with_light(img, light, region)
        if scale != 1.0:
            img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
        os.makedirs(os.path.dirname(os.path.abspath(out_png)), exist_ok=True)
        img.save(out_png)
        return out_png
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _font(size):
    for f in ("arial.ttf", "segoeui.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def sheet(images, captions, out_png, title=None, pad=16):
    ims = [Image.open(p).convert("RGB") if isinstance(p, str) else p for p in images]
    f = _font(22)
    top = 44 if title else 0
    w = sum(i.width for i in ims) + pad * (len(ims) + 1)
    h = max(i.height for i in ims) + pad * 2 + 34 + top
    out = Image.new("RGB", (w, h), (24, 26, 32))
    d = ImageDraw.Draw(out)
    if title:
        d.text((pad, 10), title, fill=(235, 235, 240), font=_font(26))
    x = pad
    for im, cap in zip(ims, captions):
        d.text((x, top + pad), cap, fill=(200, 205, 215), font=f)
        out.paste(im, (x, top + pad + 34))
        x += im.width + pad
    out.save(out_png)
    return out_png
