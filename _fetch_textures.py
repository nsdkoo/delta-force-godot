# -*- coding: utf-8 -*-
"""Fetch CC0 PBR textures from ambientCG, extract Color + NormalGL, downsize to 1024, save to assets/textures/"""
import os, io, sys, zipfile, urllib.request, concurrent.futures

ROOT = r"D:\素材存储\delta-force-godot"
TMP = os.path.join(ROOT, "_tex_tmp")
OUT = os.path.join(ROOT, "assets", "textures")
os.makedirs(TMP, exist_ok=True)
os.makedirs(OUT, exist_ok=True)

from PIL import Image

# (ambientCG assetId, 输出名)
WANT = [
    ("Ground054",        "sand"),        # 沙地
    ("Ground080",        "dirt"),        # 干裂土 / 荒地
    ("Gravel043",        "gravel"),      # 砾石
    ("Asphalt033",       "asphalt"),     # 沥青路面
    ("Concrete034",      "concrete"),    # 混凝土
    ("Plaster001",       "plaster"),     # 灰泥墙
    ("CorrugatedSteel009","corrugated"), # 波纹钢
    ("Metal063",         "rustmetal"),   # 锈蚀金属
    ("RoofingTiles012A", "rooftile"),    # 瓦屋顶
    ("Road007",          "road"),        # 土路
]

def fetch(item):
    aid, name = item
    zp = os.path.join(TMP, aid + ".zip")
    if not os.path.exists(zp) or os.path.getsize(zp) < 100000:
        url = "https://ambientcg.com/get?file=%s_1K-JPG.zip" % aid
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=120) as r, open(zp, "wb") as f:
                f.write(r.read())
        except Exception as e:
            return (name, "DL_FAIL", str(e)[:60])
    try:
        zf = zipfile.ZipFile(zp)
        names = zf.namelist()
        col = [n for n in names if n.endswith("_Color.jpg")]
        nrm = [n for n in names if n.endswith("_NormalGL.jpg")]
        if not col:
            return (name, "NO_COLOR", str(names[:4]))
        img = Image.open(io.BytesIO(zf.read(col[0]))).convert("RGB")
        w0, h0 = img.size
        if w0 > 1024:
            img = img.resize((1024, 1024), Image.LANCZOS)
        img.save(os.path.join(OUT, name + "_color.jpg"), "JPEG", quality=88, optimize=True)
        got = []
        if nrm:
            n = Image.open(io.BytesIO(zf.read(nrm[0]))).convert("RGB")
            if n.size[0] > 1024:
                n = n.resize((1024, 1024), Image.LANCZOS)
            n.save(os.path.join(OUT, name + "_normal.jpg"), "JPEG", quality=88, optimize=True)
            got.append("normal")
        zf.close()
        return (name, "OK", "%dx%d %s" % (w0, h0, "+".join(got)))
    except Exception as e:
        return (name, "ERR", str(e)[:70])

print(">>> 下载 %d 套 PBR 材质（ambientCG / CC0）" % len(WANT))
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as ex:
    for name, st, info in ex.map(fetch, WANT):
        print("  %-12s %-8s %s" % (name, st, info))

# 清理 ZIP
tot = 0
for f in os.listdir(TMP):
    p = os.path.join(TMP, f)
    try:
        tot += os.path.getsize(p)
        os.remove(p)
    except Exception:
        pass
try:
    os.rmdir(TMP)
except Exception:
    pass
print(">>> 已清理 ZIP，回收 %.1f MB" % (tot / 1048576.0))

# 联系图（供人眼检查）
files = sorted([f for f in os.listdir(OUT) if f.endswith("_color.jpg")])
if files:
    TH = 200
    cols = 5
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * TH, rows * TH), (30, 30, 32))
    for i, f in enumerate(files):
        im = Image.open(os.path.join(OUT, f)).convert("RGB").resize((TH, TH), Image.LANCZOS)
        sheet.paste(im, ((i % cols) * TH, (i // cols) * TH))
    sheet.save(os.path.join(ROOT, "_tex_preview.jpg"), "JPEG", quality=90)
    print(">>> 预览图 _tex_preview.jpg (%d 张)" % len(files))

sz = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT)) / 1048576.0
print(">>> assets/textures 共 %.1f MB" % sz)
