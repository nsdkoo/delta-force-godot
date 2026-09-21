#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""按 atlas-data.js 从 Tiny Swords atlas 切出建筑/单位/装饰。"""
from __future__ import annotations

import json
import os
import re
import shutil

from PIL import Image, ImageEnhance, ImageOps

ROOT = os.path.dirname(os.path.abspath(__file__))
ATLAS = os.path.join(ROOT, "assets", "_incoming", "extracted", "tiny_swords_repo", "tiny_swords-main", "assets", "atlas-0.png")
DATA_JS = os.path.join(ROOT, "assets", "_incoming", "atlas-data.js")
OUT_B = os.path.join(ROOT, "assets", "buildings")
OUT_U = os.path.join(ROOT, "assets", "units_kr")
OUT_D = os.path.join(ROOT, "assets", "decor_kr")
OUT_TS = os.path.join(ROOT, "assets", "tinyswords")


def load_atlas_data() -> dict:
    js = open(DATA_JS, encoding="utf-8").read()
    m = re.search(r"const TS_ATLAS = (\{.*\});", js, re.S)
    return json.loads(m.group(1))


def frame0(sheet: dict) -> tuple[int, int, int, int]:
    """Return atlas rect (ax, ay, w, h) for first frame."""
    if "u" in sheet:
        ax, ay, w, h = sheet["u"]
        return int(ax), int(ay), int(w), int(h)
    t = sheet["t"]
    # t = [trimX, trimY, w, h, atlasX, atlasY] * n
    return int(t[4]), int(t[5]), int(t[2]), int(t[3])


def tint(im: Image.Image, rgb: tuple[float, float, float]) -> Image.Image:
    """Multiply RGB while keeping alpha — used to fake red faction buildings."""
    out = im.copy().convert("RGBA")
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            px[x, y] = (
                min(255, int(r * rgb[0])),
                min(255, int(g * rgb[1])),
                min(255, int(b * rgb[2])),
                a,
            )
    return out


def main() -> None:
    for d in (OUT_B, OUT_U, OUT_D, OUT_TS):
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(d):
            os.remove(os.path.join(d, f))

    data = load_atlas_data()
    sheets = data["sheets"]
    img = Image.open(ATLAS).convert("RGBA")

    # ---- Buildings (blue originals + tinted variants) ----
    building_keys = {
        "castle": "castle_blue",
        "tower": "tower_blue",
        "house": "house1_blue",
        "house_b": "house2_blue",
    }
    for name, key in building_keys.items():
        ax, ay, w, h = frame0(sheets[key])
        crop = img.crop((ax, ay, ax + w, ay + h))
        crop.save(os.path.join(OUT_B, f"{name}.png"))
        crop.save(os.path.join(OUT_TS, f"{name}.png"))
        # warm / cool variants for visual variety on the map
        tint(crop, (1.15, 0.85, 0.75)).save(os.path.join(OUT_B, f"{name}_warm.png"))
        tint(crop, (0.85, 0.9, 1.1)).save(os.path.join(OUT_B, f"{name}_cool.png"))
        tint(crop, (1.05, 0.95, 0.7)).save(os.path.join(OUT_B, f"{name}_sand.png"))
        print("building", name, w, h)

    # warehouse / block / bunker aliases from castle/tower
    shutil.copy2(os.path.join(OUT_B, "castle.png"), os.path.join(OUT_B, "warehouse.png"))
    shutil.copy2(os.path.join(OUT_B, "castle_warm.png"), os.path.join(OUT_B, "block.png"))
    shutil.copy2(os.path.join(OUT_B, "tower.png"), os.path.join(OUT_B, "bunker.png"))
    shutil.copy2(os.path.join(OUT_B, "tower_sand.png"), os.path.join(OUT_B, "wall.png"))
    # fence: use a rock strip scaled later; keep a small rock as fence marker
    ax, ay, w, h = frame0(sheets["rock4"])
    rock = img.crop((ax, ay, ax + w, ay + h))
    rock.save(os.path.join(OUT_B, "fence.png"))

    # ---- Units: idle frame 0 for blue/red warriors + pawns + archers ----
    unit_map = [
        ("warrior_blue", "warrior_blue_idle"),
        ("warrior_red", "warrior_red_idle"),
        ("warrior_black", "warrior_black_idle"),
        ("pawn_red", "pawn_red_idle"),
        ("pawn_black", "pawn_black_idle"),
        ("archer_red", "archer_red_idle"),
        ("archer_black", "archer_black_idle"),
    ]
    for name, key in unit_map:
        ax, ay, w, h = frame0(sheets[key])
        crop = img.crop((ax, ay, ax + w, ay + h))
        crop.save(os.path.join(OUT_U, f"{name}.png"))
        crop.save(os.path.join(OUT_TS, f"{name}.png"))
        print("unit", name, w, h)

    # operator aliases used by GameConfig sprites
    aliases = {
        "soldier_rifle": "warrior_blue.png",
        "soldier_lmg": "warrior_black.png",
        "soldier_reload": "pawn_black.png",
        "operator_blue": "warrior_blue.png",
        "operator_survivor": "pawn_red.png",
        "operator_agent": "archer_black.png",
        "operator_green": "archer_red.png",
    }
    for dst, src in aliases.items():
        shutil.copy2(os.path.join(OUT_U, src), os.path.join(OUT_U, dst + ".png"))
        # also overwrite operators/ so AssetDB old paths keep working if pointed there
        op_dst = os.path.join(ROOT, "assets", "operators", dst + ".png")
        shutil.copy2(os.path.join(OUT_U, src), op_dst)
        print("alias", dst)

    # ---- Decor ----
    for i in range(1, 5):
        for kind in ("tree", "bush", "rock"):
            key = f"{kind}{i}"
            if key not in sheets:
                continue
            ax, ay, w, h = frame0(sheets[key])
            crop = img.crop((ax, ay, ax + w, ay + h))
            crop.save(os.path.join(OUT_D, f"{key}.png"))
            crop.save(os.path.join(OUT_TS, f"{key}.png"))
    print(
        "DONE buildings=%d units=%d decor=%d"
        % (len(os.listdir(OUT_B)), len(os.listdir(OUT_U)), len(os.listdir(OUT_D)))
    )


if __name__ == "__main__":
    main()
