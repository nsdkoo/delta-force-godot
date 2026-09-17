# -*- coding: utf-8 -*-
"""
烬区地表烘焙器 v2
============================================================================
把 ambientCG 的真实 PBR 材质按地图数据混成世界级地表贴图（Color + Normal），
交给 Godot 当作带 normal map 的 Sprite，配合 DirectionalLight2D 得到真实凹凸。

v2 相对 v1 的关键修正：
  · 纹理周期按真实物理尺度重算 —— v1 把 1K 沙地贴图拉伸到 22 米，细节全糊了。
    现在以「1 米 ≈ 152 输出像素」为基准，沙地主层覆盖约 6 米。
  · 三个空间尺度叠加（6m / 2m / 0.6m），单一尺度的平铺必然显得假。
  · 人工痕迹全部用噪声切边，去掉规则圆形与硬矩形。
  · 末尾加一层沙尘侵蚀，把所有「崭新」的痕迹都压旧 —— 战场不可能干净。
  · 补足碎石 / 坑洼 / 杂物，空地需要视觉噪声才不会显得空。
"""
import os, io, json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = r"D:\素材存储\delta-force-godot"
TEX = os.path.join(ROOT, "assets", "textures")   # 源 PBR 材质（Godot 不导入，见 .gdignore）
TER = os.path.join(ROOT, "assets", "terrain")    # 烘焙产物（Godot 导入）
OUT_W, OUT_H = 2048, 1400
os.makedirs(TER, exist_ok=True)

d = json.load(io.open(os.path.join(ROOT, "_map_dump.json"), encoding="utf-8"))
WW, WH = d["world"]
S = OUT_W / float(WW)
SY = OUT_H / float(WH)

# 物理尺度基准：一个成年士兵约 44 世界像素 ≈ 0.5 米 → 1 米 ≈ 88 世界像素
# 输出缩放 0.5389 → 1 米 ≈ 47 输出像素
PX_PER_M = 47.0
print("世界 %.0fx%.0f → %dx%d | 1 米 ≈ %.0f 输出像素" % (WW, WH, OUT_W, OUT_H, PX_PER_M))

def load(name, kind):
    return np.asarray(Image.open(os.path.join(TEX, "%s_%s.jpg" % (name, kind)))
                      .convert("RGB"), dtype=np.float32) / 255.0

def tiled(tex, period_px, ox=0.0, oy=0.0):
    th, tw = tex.shape[:2]
    yy = ((np.arange(OUT_H, dtype=np.float64) / period_px * th).astype(np.int64) + int(oy)) % th
    xx = ((np.arange(OUT_W, dtype=np.float64) / period_px * tw).astype(np.int64) + int(ox)) % tw
    return np.ascontiguousarray(tex[np.ix_(yy, xx)])

def fbm(base=4, octaves=5, seed=0, persist=0.5):
    rng = np.random.default_rng(seed)
    total = np.zeros((OUT_H, OUT_W), np.float32); amp = 1.0; norm = 0.0
    for o in range(octaves):
        gh = max(2, base * (2 ** o)); gw = max(2, int(gh * OUT_W / float(OUT_H)))
        g = (rng.random((gh, gw)) * 255).astype(np.uint8)
        up = np.asarray(Image.fromarray(g).resize((OUT_W, OUT_H), Image.BICUBIC), np.float32) / 255.0
        total += up * amp; norm += amp; amp *= persist
    return total / norm

def streaks(seed, rows, cols, blur=0.0):
    """方向性条带噪声：低分辨率噪声沿一个轴拉伸，得到风成沙纹那种细长纹路。"""
    rng = np.random.default_rng(seed)
    g = (rng.random((max(2, rows), max(2, cols))) * 255).astype(np.uint8)
    im = Image.fromarray(g).resize((OUT_W, OUT_H), Image.BICUBIC)
    if blur > 0:
        im = im.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(im, dtype=np.float32) / 255.0

def grain(seed, cells, blur=0.6):
    """锐利的逐像素颗粒。用最近邻放大 —— BICUBIC 会把砂砾感整个磨平。"""
    rng = np.random.default_rng(seed)
    g = rng.random((cells, cells)).astype(np.float32)
    fy = int(np.ceil(OUT_H / float(cells))); fx = int(np.ceil(OUT_W / float(cells)))
    up = np.repeat(np.repeat(g, fy, axis=0), fx, axis=1)[:OUT_H, :OUT_W]
    if blur > 0:
        up = np.asarray(Image.fromarray((up * 255).astype(np.uint8))
                        .filter(ImageFilter.GaussianBlur(blur)), np.float32) / 255.0
    return up

print("生成噪声 …")
N_MACRO = fbm(base=3, octaves=6, seed=11)      # 宏观土质分区
N_EDGE  = fbm(base=6, octaves=5, seed=22)      # 区域边界扰动
N_FINE  = fbm(base=30, octaves=3, seed=33)     # 细部斑驳 / 侵蚀
N_SPECK = fbm(base=90, octaves=2, seed=37)     # 碎石颗粒
N_BIG   = fbm(base=2, octaves=3, seed=44)      # 全局明暗

def blend(a, b, w):
    m = w[..., None]
    return a * (1.0 - m) + b * m

# ============================================================ 1 地基
print("铺设基底 …")
sand_c = load("sand", "color"); sand_n = load("sand", "normal")
dirt_c = load("dirt", "color"); dirt_n = load("dirt", "normal")
grav_c = load("gravel", "color"); grav_n = load("gravel", "normal")

# 烬区是砾石戈壁而不是成片沙丘：以砾石为主调，干裂土与沙地按噪声分区覆盖。
# 每类材质都用两个互不成整数比的周期叠加，压掉可辨认的平铺重复。
GRAV_C = tiled(grav_c, 2.30 * PX_PER_M, 55, 301) * 0.58 + tiled(grav_c, 0.79 * PX_PER_M, 611, 97) * 0.42
GRAV_N = tiled(grav_n, 2.30 * PX_PER_M, 55, 301) * 0.58 + tiled(grav_n, 0.79 * PX_PER_M, 611, 97) * 0.42
SAND_C = tiled(sand_c, 5.20 * PX_PER_M, 0, 0) * 0.62 + tiled(sand_c, 1.87 * PX_PER_M, 131, 77) * 0.38
SAND_N = tiled(sand_n, 5.20 * PX_PER_M, 0, 0) * 0.62 + tiled(sand_n, 1.87 * PX_PER_M, 131, 77) * 0.38
DIRT_C = tiled(dirt_c, 3.40 * PX_PER_M, 211, 93) * 0.66 + tiled(dirt_c, 1.13 * PX_PER_M, 733, 429) * 0.34
DIRT_N = tiled(dirt_n, 3.40 * PX_PER_M, 211, 93) * 0.66 + tiled(dirt_n, 1.13 * PX_PER_M, 733, 429) * 0.34

w_g = np.clip(0.34 + (N_MACRO - 0.44) * 1.7, 0.06, 0.92)
w_s = np.clip((0.50 - N_MACRO) * 1.9, 0.0, 0.70) * (1.0 - w_g)
w_d = np.clip(1.0 - w_g - w_s, 0.0, 1.0)

col = GRAV_C * w_g[..., None] + SAND_C * w_s[..., None] + DIRT_C * w_d[..., None]
nrm = GRAV_N * w_g[..., None] + SAND_N * w_s[..., None] + DIRT_N * w_d[..., None]

# 风成沙纹：只落在沙地区域，砾石地不长这种纹路
RIP = streaks(7, OUT_H // 2, 22, blur=0.8) * 0.55 + streaks(13, 26, OUT_W // 2, blur=0.8) * 0.45
col = col * (1.0 + (RIP - 0.5) * 0.34 * w_s)[..., None]

# 逐像素砂砾：这是近距离看地面时唯一能提供的「实感」，绝不能省
GR = grain(99, 620)
col = col * (0.900 + GR[..., None] * 0.200)
GR2 = grain(101, 340)
nrm = nrm.copy()
nrm[..., 0] = np.clip(nrm[..., 0] + (GR2 - 0.5) * 0.16, 0.0, 1.0)
nrm[..., 1] = np.clip(nrm[..., 1] + (grain(103, 340) - 0.5) * 0.16, 0.0, 1.0)

# ============================================================ 2 软边遮罩
def stamp_soft(target, rect, soft, noise_amp, weight=1.0, power=1.3):
    """在世界坐标盖一个噪声软边矩形，取最大值叠加。"""
    x, y, w, h = rect
    m = max(float(soft), 1.0)
    x0 = max(0, int((x - m * SY) * S)); x1 = min(OUT_W, int((x + w + m) * S) + 2)
    y0 = max(0, int((y - m) * S)); y1 = min(OUT_H, int((y + h + m) * S) + 2)
    if x1 <= x0 or y1 <= y0:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    wx = xx.astype(np.float32) / S; wy = yy.astype(np.float32) / S
    dist = np.maximum(np.maximum(x - wx, wx - (x + w)),
                      np.maximum(y - wy, wy - (y + h)))
    if noise_amp:
        dist = dist + (N_EDGE[y0:y1, x0:x1] - 0.5) * noise_amp
        dist = dist + (N_FINE[y0:y1, x0:x1] - 0.5) * noise_amp * 0.42
    a = np.clip(0.5 - dist / m, 0.0, 1.0) ** power * weight
    target[y0:y1, x0:x1] = np.maximum(target[y0:y1, x0:x1], a)

def blob(target, cx_w, cy_w, r_w, weight=1.0, rough=0.62, noise=None, power=1.5):
    """噪声切边的不规则斑块 —— 污渍 / 焦痕必须是不规则的，圆斑一眼假。"""
    cx, cy, r = cx_w * S, cy_w * SY, max(r_w * S, 2.0)
    pad = r * 1.7
    x0 = max(0, int(cx - pad)); x1 = min(OUT_W, int(cx + pad) + 1)
    y0 = max(0, int(cy - pad)); y1 = min(OUT_H, int(cy + pad) + 1)
    if x1 <= x0 or y1 <= y0:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    dd = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    if noise is not None:
        dd = dd + (noise[y0:y1, x0:x1] - 0.5) * rough
    a = np.clip(1.0 - dd, 0.0, 1.0) ** power * weight
    target[y0:y1, x0:x1] = np.maximum(target[y0:y1, x0:x1], a)

# ============================================================ 3 道路
print("铺设道路 …")
road_mask = np.zeros((OUT_H, OUT_W), np.float32)
for r in d["roads"]:
    stamp_soft(road_mask, (r["x"], r["y"], r["w"], r["h"]), 96.0, 70.0, 1.0, 1.15)
# 路缘的碎石堆积
shoulder = np.clip(road_mask * 1.35 - 0.42, 0.0, 1.0) * np.clip((N_SPECK - 0.52) * 2.6, 0, 1)

# 不要用 Road007 那套：它自带车道虚线，平铺后会变成一屏规则白线。
# 纯沥青打底，掺细砾石做出被履带碾碎的路面。
road_c = (tiled(load("asphalt", "color"), 1.9 * PX_PER_M, 7, 19) * 0.66 +
          tiled(load("gravel", "color"), 1.1 * PX_PER_M, 401, 233) * 0.34)
road_n = (tiled(load("asphalt", "normal"), 1.9 * PX_PER_M, 7, 19) * 0.66 +
          tiled(load("gravel", "normal"), 1.1 * PX_PER_M, 401, 233) * 0.34)
col = blend(col, road_c, road_mask)
nrm = blend(nrm, road_n, road_mask)
# 沙漠里的路会被流沙埋边：路肩盖一层沙，破掉路面生硬的边界
col = blend(col, tiled(sand_c, 4.4 * PX_PER_M, 907, 61), np.clip(shoulder, 0, 1) * 0.60)

# ============================================================ 4 场院
print("铺设建筑场院 …")
heavy = np.zeros((OUT_H, OUT_W), np.float32)
light = np.zeros((OUT_H, OUT_W), np.float32)
HEAVY = {"block", "tower", "warehouse", "bunker"}
ch = cl = 0
for b in d["buildings"]:
    t = b["type"]
    if t in ("wall", "fence"):
        continue
    out = 96.0 if t in HEAVY else 52.0
    rect = (b["x"] - out * 0.5, b["y"] - out * 0.5, b["w"] + out, b["h"] + out)
    if t in HEAVY:
        stamp_soft(heavy, rect, 96.0, 84.0, 0.54, 1.5); ch += 1
    else:
        stamp_soft(light, rect, 82.0, 70.0, 0.46, 1.6); cl += 1
print("  重型场院 %d / 民房场院 %d" % (ch, cl))

cap = np.zeros((OUT_H, OUT_W), np.float32)
for cx, cy in [(960, 660), (960, 1940), (1900, 620), (1900, 1980), (2900, 700), (2900, 1900)]:
    stamp_soft(cap, (cx - 230, cy - 230, 460, 460), 190.0, 96.0, 0.58, 1.7)

col = blend(col, tiled(load("dirt", "color"), 2.6 * PX_PER_M, 171, 39), light)
nrm = blend(nrm, tiled(load("dirt", "normal"), 2.6 * PX_PER_M, 171, 39), light)
col = blend(col, tiled(load("dirt", "color"), 2.2 * PX_PER_M, 313, 87) * 0.95, cap)
nrm = blend(nrm, tiled(load("dirt", "normal"), 2.2 * PX_PER_M, 313, 87), cap)
# 混凝土压到接近沙色：中东的场院都是被沙盖住的旧水泥，不该有白框
col = blend(col, tiled(load("concrete", "color"), 3.3 * PX_PER_M, 33, 71) * 0.72, heavy)
nrm = blend(nrm, tiled(load("concrete", "normal"), 3.3 * PX_PER_M, 33, 71), heavy)

occ = np.clip(road_mask + light + cap + heavy, 0.0, 1.0)

# ============================================================ 5 痕量贴花
print("绘制贴花 …")

# 履带：两条负重轮压痕 + 中间的扰动带
track = np.zeros((OUT_H, OUT_W), np.float32)
for t in d["tracks"]:
    x0, y0 = t["x0"] * S, t["y0"] * SY
    x1, y1 = t["x1"] * S, t["y1"] * SY
    a = math.atan2(y1 - y0, x1 - x0)
    px, py = -math.sin(a), math.cos(a)
    n = max(2, int(math.hypot(x1 - x0, y1 - y0) / 6.0))
    for i in range(n):
        f = i / float(n)
        bx, by = x0 + (x1 - x0) * f, y0 + (y1 - y0) * f
        for sgn in (-1, 1):
            blob(track, (bx + px * 0.62 * sgn) / S, (by + py * 0.62 * sgn) / SY,
                 2.6, 0.55, 0.9, N_FINE, 1.2)
track *= np.clip(0.35 + N_FINE * 1.15, 0, 1)

# 油污：暗而油亮；焦痕：更暗且边缘碎裂
oil = np.zeros((OUT_H, OUT_W), np.float32)
scorch = np.zeros((OUT_H, OUT_W), np.float32)
for s in d["stains"]:
    if s["kind"] == "oil":
        for k in range(4):
            ang = s["rot"] + k * 1.9
            r = s["size"] * (0.5 + 0.42 * ((k * 7) % 4) / 4.0)
            blob(oil, s["x"] + math.cos(ang) * r * 0.42, s["y"] + math.sin(ang) * r * 0.42,
                 r, 0.30, 0.75, N_FINE, 1.6)
    else:
        for k in range(5):
            ang = s["rot"] + k * 1.27
            r = s["size"] * (0.46 + 0.40 * ((k * 5) % 4) / 4.0)
            blob(scorch, s["x"] + math.cos(ang) * r * 0.5, s["y"] + math.sin(ang) * r * 0.5,
                 r, 0.34, 0.95, N_EDGE, 1.7)

# 碎石与坑洼：程序化铺满，空地需要视觉噪声才不显空
spec = np.zeros((OUT_H, OUT_W), np.float32)
holes = np.zeros((OUT_H, OUT_W), np.float32)
rng = np.random.default_rng(20260529)
for _ in range(2600):
    x = rng.random() * WW; y = rng.random() * WH
    r = 0.10 + rng.random() * 0.34
    blob(spec, x, y, r * PX_PER_M, 0.34 + rng.random() * 0.34, 0.85, N_SPECK, 1.2)
for _ in range(420):
    x = rng.random() * WW; y = rng.random() * WH
    r = 0.5 + rng.random() * 1.5
    blob(holes, x, y, r * PX_PER_M, 0.20 + rng.random() * 0.24, 0.9, N_FINE, 1.5)

DARK_OIL = np.array([0.075, 0.070, 0.062], np.float32)
DARK_SCORCH = np.array([0.085, 0.074, 0.064], np.float32)
DARK_HOLE = np.array([0.145, 0.125, 0.100], np.float32)

col = col * (1.0 - oil[..., None] * 0.44) + DARK_OIL * oil[..., None] * 0.44
col = col * (1.0 - scorch[..., None] * 0.54) + DARK_SCORCH * scorch[..., None] * 0.54
col = col * (1.0 - holes[..., None] * 0.40) + DARK_HOLE * holes[..., None] * 0.40
col = col * (1.0 - track[..., None] * 0.16) + np.array([0.235, 0.205, 0.165], np.float32) * track[..., None] * 0.16
# 碎石偏亮偏冷，让地面有颗粒感
col = col * (1.0 - spec[..., None] * 0.22) + np.array([0.66, 0.63, 0.58], np.float32) * spec[..., None] * 0.22

# ============================================================ 6 沙尘侵蚀 + 分级
print("沙尘侵蚀与分级 …")
# 战场不可能干净：所有痕迹都被风沙盖一层
dust = np.clip(N_MACRO * 1.25 - 0.18, 0.0, 1.0) * 0.30
col = blend(col, tiled(sand_c, 5.2 * PX_PER_M, 733, 127), dust)

# 大尺度明暗：沉积与湿度差异
col = col * (0.86 + N_BIG * 0.30)[..., None]
# 细部斑驳
col = col * (0.945 + N_FINE[..., None] * 0.115)
# 暖色统一，并抬一点对比去掉灰蒙感
col = col * np.array([1.032, 1.002, 0.943], np.float32)
# 地面必须先暗下去，太阳光打上来才有地方可以亮。
# 这是整条光照链路能不能出效果的前提 —— 天光照明下的地表不该接近纯白。
col = col * 0.80
col = (col - 0.335) * 1.24 + 0.330
col = np.clip(col, 0.0, 1.0)

# 法线重归一化
nx = nrm[..., 0] * 2.0 - 1.0
ny = nrm[..., 1] * 2.0 - 1.0
nz = np.maximum(nrm[..., 2] * 2.0 - 1.0, 0.22)
ln = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-6
nrm_out = np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5], axis=2)

cimg = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
nimg = Image.fromarray((np.clip(nrm_out, 0, 1) * 255).astype(np.uint8), "RGB")
cimg.save(os.path.join(TER, "ground_color.jpg"), "JPEG", quality=91, optimize=True)
nimg.save(os.path.join(TER, "ground_normal.jpg"), "JPEG", quality=91, optimize=True)

# 两块 1:1 裁片供检查真实观感（缩略图会骗人）
cimg.crop((300, 200, 1300, 900)).save(os.path.join(ROOT, "_bake_preview.jpg"), "JPEG", quality=92)
cimg.resize((1024, 700), Image.LANCZOS).save(os.path.join(ROOT, "_bake_full.jpg"), "JPEG", quality=90)
for f in ("ground_color.jpg", "ground_normal.jpg"):
    print("  %-20s %.2f MB" % (f, os.path.getsize(os.path.join(TER, f)) / 1048576.0))
print("完成。")
