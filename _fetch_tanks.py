# -*- coding: utf-8 -*-
"""拉取 Kenney Topdown Tanks Redux 的坦克素材（车体 / 炮塔 / 炮管三层分离），CC0。"""
import os, urllib.parse, urllib.request, concurrent.futures
from PIL import Image

ROOT = r"D:\素材存储\delta-force-godot"
OUT = os.path.join(ROOT, "assets", "tanks")
os.makedirs(OUT, exist_ok=True)

BASE = "https://cdn.jsdelivr.net/gh/ETdoFresh/kenney.nl/kenney_topdowntanksredux/PNG/Default%20size/"

BODIES = ["tankBody_sand", "tankBody_dark", "tankBody_green", "tankBody_blue",
          "tankBody_red", "tankBody_huge", "tankBody_darkLarge", "tankBody_bigRed"]
TURRETS = ["tank_sand", "tank_dark", "tank_green", "tank_blue",
           "tank_red", "tank_huge", "tank_darkLarge", "tank_bigRed"]
BARRELS = ["tankSand_barrel1", "tankSand_barrel2", "tankSand_barrel3",
           "tankDark_barrel1", "tankDark_barrel2", "tankDark_barrel3",
           "tankGreen_barrel1", "tankGreen_barrel2", "tankGreen_barrel3",
           "tankBlue_barrel1", "tankBlue_barrel2", "tankBlue_barrel3",
           "tankRed_barrel1", "tankRed_barrel2", "tankRed_barrel3",
           "specialBarrel1", "specialBarrel2", "specialBarrel3", "specialBarrel5"]

WANT = [("body", n) for n in BODIES] + [("turret", n) for n in TURRETS] + [("barrel", n) for n in BARRELS]

def fetch(item):
    kind, name = item
    url = BASE + urllib.parse.quote(name + ".png")
    dst = os.path.join(OUT, "%s__%s.png" % (kind, name))
    for _ in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=45) as r:
                data = r.read()
            if len(data) < 300:
                continue
            with open(dst, "wb") as f:
                f.write(data)
            return (name, "OK", len(data))
        except Exception as e:
            err = str(e)[:50]
    return (name, "FAIL", err if 'err' in dir() else "?")

print(">>> 下载坦克素材 %d 个" % len(WANT))
ok = 0
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
    for name, st, info in ex.map(fetch, WANT):
        if st == "OK":
            ok += 1
        else:
            print("  失败:", name, info)
print(">>> 成功 %d / %d" % (ok, len(WANT)))

# 尺寸与锚点分析
print()
print("=== 尺寸清单 ===")
files = sorted(os.listdir(OUT))
for f in files:
    im = Image.open(os.path.join(OUT, f))
    print("  %-34s %dx%d" % (f, im.width, im.height))

# 拼图预览：按 车体 / 炮塔 / 炮管 分组
def sheet(names, out_name, scale=1.0):
    ims = []
    for n in names:
        p = os.path.join(OUT, n)
        if os.path.exists(p):
            ims.append((n, Image.open(p).convert("RGBA")))
    if not ims:
        return
    W = sum(i.width for _, i in ims) + 14 * (len(ims) + 1)
    H = max(i.height for _, i in ims) + 28
    out = Image.new("RGBA", (W, H), (46, 44, 40, 255))
    x = 14
    for n, i in ims:
        out.paste(i, (x, 14), i)
        x += i.width + 14
    if scale != 1.0:
        out = out.resize((int(W * scale), int(H * scale)), Image.NEAREST)
    out.convert("RGB").save(os.path.join(ROOT, out_name), "JPEG", quality=92)
    print("  预览 →", out_name, out.size)

sheet(["body__tankBody_sand.png", "body__tankBody_dark.png", "body__tankBody_green.png",
       "body__tankBody_darkLarge.png", "body__tankBody_huge.png", "body__tankBody_bigRed.png"],
      "_tk_bodies.jpg", 1.4)
sheet(["turret__tank_sand.png", "turret__tank_dark.png", "turret__tank_green.png",
       "turret__tank_darkLarge.png", "turret__tank_huge.png", "turret__tank_bigRed.png"],
      "_tk_turrets.jpg", 1.4)
sheet(["barrel__tankSand_barrel1.png", "barrel__tankSand_barrel2.png", "barrel__tankSand_barrel3.png",
       "barrel__specialBarrel1.png", "barrel__specialBarrel2.png", "barrel__specialBarrel5.png"],
      "_tk_barrels.jpg", 1.4)
print(">>> 完成")
