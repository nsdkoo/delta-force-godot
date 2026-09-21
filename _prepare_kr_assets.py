#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""离线整理王国保卫战风素材到 assets/buildings、units_kr、decor_kr。"""
from __future__ import annotations

import os
import shutil

from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
INC = os.path.join(ROOT, "assets", "_incoming", "extracted")
OUT_B = os.path.join(ROOT, "assets", "buildings")
OUT_U = os.path.join(ROOT, "assets", "units_kr")
OUT_D = os.path.join(ROOT, "assets", "decor_kr")


def ensure(*dirs: str) -> None:
    for d in dirs:
        os.makedirs(d, exist_ok=True)


def copy_stone() -> None:
    src = os.path.join(INC, "stone_towers", "PNG")
    files = []
    for f in os.listdir(src):
        if f.lower().endswith(".png"):
            p = os.path.join(src, f)
            files.append((os.path.getsize(p), f, p))
    files.sort(reverse=True)
    for i, (_sz, _f, p) in enumerate(files[:20]):
        shutil.copy2(p, os.path.join(OUT_B, f"stone_{i:02d}.png"))
    print("stone", min(20, len(files)))


def copy_iso() -> None:
    iso = os.path.join(INC, "kenney_td_iso", "PNG")
    det = os.path.join(iso, "Details")
    for f in os.listdir(det):
        if f.startswith(("trees", "rocks", "crystals")):
            shutil.copy2(os.path.join(det, f), os.path.join(OUT_D, f))
    print("decor", len(os.listdir(OUT_D)))
    for color in ("brown", "grey", "red"):
        folder = os.path.join(iso, f"Towers ({color})")
        items = []
        for f in os.listdir(folder):
            p = os.path.join(folder, f)
            with Image.open(p) as im:
                items.append((im.size[0] * im.size[1], f, p))
        items.sort(reverse=True)
        for i, (_a, _f, p) in enumerate(items[:8]):
            shutil.copy2(p, os.path.join(OUT_B, f"iso_{color}_{i:02d}.png"))
    print("buildings after iso", len(os.listdir(OUT_B)))


def slice_atlas() -> None:
    atlas = os.path.join(INC, "tiny_swords_repo", "tiny_swords-main", "assets", "atlas-0.png")
    if not os.path.isfile(atlas):
        atlas = os.path.join(ROOT, "assets", "_incoming", "preview", "big_0_atlas-0.png")
    img = Image.open(atlas).convert("RGBA")
    w, h = img.size
    print("atlas", w, h)
    cell = 8
    gw, gh = w // cell, h // cell
    px = img.load()
    occ = bytearray(gw * gh)
    for gy in range(gh):
        for gx in range(gw):
            x = gx * cell + cell // 2
            y = gy * cell + cell // 2
            if x < w and y < h and px[x, y][3] > 20:
                occ[gy * gw + gx] = 1
    seen = bytearray(gw * gh)
    comps: list[tuple[int, int, int, int, int]] = []
    for gy in range(gh):
        for gx in range(gw):
            start = gy * gw + gx
            if seen[start] or not occ[start]:
                continue
            stack = [start]
            count = 0
            minx = maxx = gx
            miny = maxy = gy
            while stack:
                i = stack.pop()
                if seen[i]:
                    continue
                seen[i] = 1
                if not occ[i]:
                    continue
                x = i % gw
                y = i // gw
                count += 1
                if x < minx:
                    minx = x
                if x > maxx:
                    maxx = x
                if y < miny:
                    miny = y
                if y > maxy:
                    maxy = y
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < gw and 0 <= ny < gh:
                        ni = ny * gw + nx
                        if not seen[ni]:
                            stack.append(ni)
            if count >= 6:
                comps.append((minx, miny, maxx, maxy, count))
    comps.sort(key=lambda c: -((c[2] - c[0] + 1) * (c[3] - c[1] + 1)))
    print("comps", len(comps))
    bi = ui = 0
    for minx, miny, maxx, maxy, _cnt in comps[:150]:
        x0 = max(0, minx * cell - 2)
        y0 = max(0, miny * cell - 2)
        x1 = min(w, (maxx + 1) * cell + 2)
        y1 = min(h, (maxy + 1) * cell + 2)
        crop = img.crop((x0, y0, x1, y1))
        bb = crop.getbbox()
        if not bb:
            continue
        crop = crop.crop(bb)
        bw, bh = crop.size
        area = bw * bh
        if area >= 14000 and bh >= 90 and bw >= 70:
            crop.save(os.path.join(OUT_B, f"ts_build_{bi:02d}.png"))
            bi += 1
        elif 2000 <= area <= 18000 and 45 <= bh <= 150 and 28 <= bw <= 130:
            crop.save(os.path.join(OUT_U, f"ts_unit_{ui:02d}.png"))
            ui += 1
        if bi >= 30 and ui >= 30:
            break
    print("sliced buildings", bi, "units", ui)


def main() -> None:
    ensure(OUT_B, OUT_U, OUT_D)
    # clear previous slice outputs only
    for d in (OUT_B, OUT_U, OUT_D):
        for f in os.listdir(d):
            os.remove(os.path.join(d, f))
    copy_stone()
    copy_iso()
    slice_atlas()
    print(
        "DONE buildings=%d units=%d decor=%d"
        % (len(os.listdir(OUT_B)), len(os.listdir(OUT_U)), len(os.listdir(OUT_D)))
    )


if __name__ == "__main__":
    main()
