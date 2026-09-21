#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""拉取王国保卫战风素材：Tiny Swords Free Pack + 整理已有 CraftPix / Kenney iso。"""
from __future__ import annotations

import json
import os
import re
import shutil
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
INCOMING = os.path.join(ROOT, "assets", "_incoming")
OUT_TS = os.path.join(ROOT, "assets", "tinyswords")
OUT_BLD = os.path.join(ROOT, "assets", "buildings")
OUT_UNITS = os.path.join(ROOT, "assets", "units_kr")
UA = {"User-Agent": "Mozilla/5.0 (compatible; delta-force-godot-fetcher)"}


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def fetch_itch_uploads() -> list[dict]:
    html = get("https://pixelfrog-assets.itch.io/tiny-swords").decode("utf-8", "ignore")
    open(os.path.join(INCOMING, "itch_page.html"), "w", encoding="utf-8").write(html)
    game_ids = re.findall(r'data-game_id="(\d+)"', html)
    upload_ids = re.findall(r'data-upload_id="(\d+)"', html)
    # Also parse embedded JSON blobs
    for m in re.finditer(r'(\{[^{}]*"uploads"[^{}]*\})', html):
        pass
    # itch pages often embed uploads in window.itch data
    m = re.search(r'"uploads"\s*:\s*(\[[^\]]+\])', html)
    uploads = []
    if m:
        try:
            uploads = json.loads(m.group(1))
        except Exception:
            uploads = []
    print("game_ids", game_ids[:5], "upload_ids", upload_ids[:10], "json_uploads", len(uploads))
    # Collect named files from HTML
    names = re.findall(r'>([^<>]*Tiny Swords[^<>]*\.zip)<', html, re.I)
    names += re.findall(r'>([^<>]*TS_old[^<>]*\.zip)<', html, re.I)
    names += re.findall(r'>([^<>]*Free Pack[^<>]*\.zip)<', html, re.I)
    print("names", names)
    return [{"id": uid, "name": n} for uid, n in zip(upload_ids, names)] or [
        {"id": uid} for uid in upload_ids
    ]


def try_download_upload(upload_id: str, dest: str) -> bool:
    # itch free download endpoint (no payment)
    candidates = [
        f"https://pixelfrog-assets.itch.io/tiny-swords/file/{upload_id}",
        f"https://pixelfrog-assets.itch.io/tiny-swords/file/{upload_id}?source=game_download",
    ]
    for url in candidates:
        try:
            req = urllib.request.Request(url, headers={**UA, "Referer": "https://pixelfrog-assets.itch.io/tiny-swords"})
            with urllib.request.urlopen(req, timeout=180) as r:
                data = r.read()
                ctype = r.headers.get("Content-Type", "")
                print("GET", url, "ctype", ctype, "len", len(data))
                if len(data) < 10000:
                    # likely HTML interstitial
                    text = data.decode("utf-8", "ignore")
                    open(os.path.join(INCOMING, f"itch_{upload_id}.html"), "w", encoding="utf-8").write(text)
                    # look for direct CDN link
                    m = re.search(r'https://[^"\']+\.zip', text)
                    if m:
                        print("follow", m.group(0)[:120])
                        data = get(m.group(0))
                    else:
                        continue
                if data[:2] == b"PK" or data[:4] == b"\x50\x4b\x03\x04":
                    with open(dest, "wb") as f:
                        f.write(data)
                    print("saved", dest, len(data))
                    return True
        except Exception as e:
            print("fail", url, e)
    return False


def copy_stone_towers() -> None:
    src = os.path.join(INCOMING, "extracted", "stone_towers", "PNG")
    os.makedirs(OUT_BLD, exist_ok=True)
    # CraftPix pack: larger PNGs tend to be assembled towers
    files = []
    for f in os.listdir(src):
        if f.lower().endswith(".png"):
            p = os.path.join(src, f)
            files.append((os.path.getsize(p), f, p))
    files.sort(reverse=True)
    # Keep top assembled-looking sprites + a few mid ones
    keep = files[:18]
    for i, (sz, f, p) in enumerate(keep):
        dst = os.path.join(OUT_BLD, f"stone_{i:02d}.png")
        shutil.copy2(p, dst)
        print("building", f, "->", os.path.basename(dst), sz)


def copy_kenney_iso_parts() -> None:
    """Copy complete-looking iso towers / landscape / trees for decoration."""
    base = os.path.join(INCOMING, "extracted", "kenney_td_iso", "PNG")
    dst_dir = os.path.join(ROOT, "assets", "kenney_iso")
    mapping = {
        "Towers (brown)": "tower_brown",
        "Towers (grey)": "tower_grey",
        "Towers (red)": "tower_red",
        "Details": "detail",
        "Landscape": "land",
    }
    for folder, prefix in mapping.items():
        src = os.path.join(base, folder)
        if not os.path.isdir(src):
            continue
        out = os.path.join(dst_dir, prefix)
        os.makedirs(out, exist_ok=True)
        for f in sorted(os.listdir(src)):
            if f.lower().endswith(".png"):
                shutil.copy2(os.path.join(src, f), os.path.join(out, f))
        print("kenney_iso", prefix, len(os.listdir(out)))


def slice_tinyswords_atlas_fallback() -> None:
    """
    Fallback: TheEnigmaThatIsMe repo ships a packed atlas used by their game.
    We use it only if itch download fails, slicing obvious large opaque blobs
    into buildings/units with a simple connected-component crop.
    """
    try:
        from PIL import Image
    except ImportError:
        print("PIL missing; skip atlas slice")
        return
    atlas_path = os.path.join(
        INCOMING, "extracted", "tiny_swords_repo", "tiny_swords-main", "assets", "atlas-0.png"
    )
    if not os.path.isfile(atlas_path):
        # preview copy
        atlas_path = os.path.join(INCOMING, "preview", "big_0_atlas-0.png")
    if not os.path.isfile(atlas_path):
        print("no atlas")
        return
    img = Image.open(atlas_path).convert("RGBA")
    w, h = img.size
    px = img.load()
    visited = [[False] * h for _ in range(w)]
    blobs = []

    def flood(x0, y0):
        stack = [(x0, y0)]
        minx = maxx = x0
        miny = maxy = y0
        count = 0
        while stack:
            x, y = stack.pop()
            if x < 0 or y < 0 or x >= w or y >= h or visited[x][y]:
                continue
            a = px[x, y][3]
            if a < 16:
                visited[x][y] = True
                continue
            visited[x][y] = True
            count += 1
            minx = min(minx, x)
            maxx = max(maxx, x)
            miny = min(miny, y)
            maxy = max(maxy, y)
            stack.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
        return minx, miny, maxx, maxy, count

    step = 4
    for y in range(0, h, step):
        for x in range(0, w, step):
            if visited[x][y]:
                continue
            if px[x, y][3] < 16:
                visited[x][y] = True
                continue
            box = flood(x, y)
            if box[4] >= 800:
                blobs.append(box)
    blobs.sort(key=lambda b: -(b[2] - b[0] + 1) * (b[3] - b[1] + 1))
    os.makedirs(OUT_TS, exist_ok=True)
    os.makedirs(OUT_UNITS, exist_ok=True)
    os.makedirs(OUT_BLD, exist_ok=True)
    # Classify by size: large = buildings, medium = units
    bi = ui = 0
    for minx, miny, maxx, maxy, count in blobs[:80]:
        bw = maxx - minx + 1
        bh = maxy - miny + 1
        crop = img.crop((minx, miny, maxx + 1, maxy + 1))
        area = bw * bh
        if area >= 12000 and bh >= 80:
            path = os.path.join(OUT_BLD, f"ts_build_{bi:02d}.png")
            crop.save(path)
            bi += 1
        elif 1800 <= area <= 20000 and 40 <= bh <= 160 and 30 <= bw <= 140:
            path = os.path.join(OUT_UNITS, f"ts_unit_{ui:02d}.png")
            crop.save(path)
            ui += 1
        if bi >= 24 and ui >= 24:
            break
    print(f"atlas slice buildings={bi} units={ui}")


def main() -> None:
    os.makedirs(INCOMING, exist_ok=True)
    uploads = fetch_itch_uploads()
    got = False
    for u in uploads:
        uid = str(u.get("id"))
        dest = os.path.join(INCOMING, f"tinyswords_{uid}.zip")
        if try_download_upload(uid, dest):
            out = os.path.join(INCOMING, "extracted", f"tinyswords_{uid}")
            os.makedirs(out, exist_ok=True)
            with zipfile.ZipFile(dest) as z:
                z.extractall(out)
            print("extracted to", out)
            # copy useful png tree into assets/tinyswords
            os.makedirs(OUT_TS, exist_ok=True)
            n = 0
            for root, _dirs, files in os.walk(out):
                for f in files:
                    if f.lower().endswith(".png"):
                        rel = os.path.relpath(os.path.join(root, f), out)
                        dst = os.path.join(OUT_TS, rel.replace("\\", os.sep))
                        os.makedirs(os.path.dirname(dst), exist_ok=True)
                        shutil.copy2(os.path.join(root, f), dst)
                        n += 1
            print("copied tinyswords pngs", n)
            got = True
            break
    if not got:
        print("itch download failed; using atlas fallback + CraftPix/Kenney")
        slice_tinyswords_atlas_fallback()
    copy_stone_towers()
    copy_kenney_iso_parts()
    print("DONE")


if __name__ == "__main__":
    main()
