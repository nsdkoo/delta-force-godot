#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""批量下载 Kenney CC0 素材到 Godot 项目（jsdelivr 直连）"""
import os, sys, urllib.request, time

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
B = "https://cdn.jsdelivr.net/gh/ETdoFresh/kenney.nl"
CH = B + "/topdown-shooter/PNG"
TK = B + "/kenney_topdowntanksredux/PNG/Default%20size"
PT = B + "/particlePack_1.1/PNG%20(Transparent)"

FILES = [
    # 干员
    (CH + "/Soldier%201/soldier1_gun.png",      "operators/soldier_rifle.png"),
    (CH + "/Soldier%201/soldier1_machine.png",  "operators/soldier_lmg.png"),
    (CH + "/Soldier%201/soldier1_reload.png",   "operators/soldier_reload.png"),
    (CH + "/Man%20Blue/manBlue_gun.png",        "operators/operator_blue.png"),
    (CH + "/Survivor%201/survivor1_gun.png",    "operators/operator_survivor.png"),
    (CH + "/Hitman%201/hitman1_gun.png",        "operators/operator_agent.png"),
    (CH + "/Woman%20Green/womanGreen_gun.png",  "operators/operator_green.png"),
    # 载具
    (TK + "/tankBody_sand.png",    "vehicles/tank_body_sand.png"),
    (TK + "/tankSand_barrel1.png", "vehicles/tank_turret_sand.png"),
    (TK + "/tankBody_dark.png",    "vehicles/tank_body_dark.png"),
    (TK + "/tankDark_barrel1.png", "vehicles/tank_turret_dark.png"),
    (TK + "/tankBody_blue.png",    "vehicles/apc_body_blue.png"),
    (TK + "/tankBlue_barrel2.png", "vehicles/apc_turret_blue.png"),
    (TK + "/tankBody_red.png",     "vehicles/apc_body_red.png"),
    (TK + "/tankRed_barrel2.png",  "vehicles/apc_turret_red.png"),
    # 地物
    (TK + "/tileSand1.png",       "tiles/sand_1.png"),
    (TK + "/tileSand2.png",       "tiles/sand_2.png"),
    (TK + "/sandbagBeige.png",    "tiles/sandbag_beige.png"),
    (TK + "/sandbagBrown.png",    "tiles/sandbag_brown.png"),
    (TK + "/crateWood.png",       "tiles/crate_wood.png"),
    (TK + "/crateMetal.png",      "tiles/crate_metal.png"),
    (TK + "/barricadeMetal.png",  "tiles/barricade.png"),
    (TK + "/wireStraight.png",    "tiles/wire.png"),
    (TK + "/treeBrown_large.png", "tiles/tree_dry.png"),
    (TK + "/barrelRust_top.png",  "tiles/barrel_rust.png"),
    (TK + "/barrelGreen_top.png", "tiles/barrel_green.png"),
    (TK + "/tracksSmall.png",     "tiles/tracks.png"),
    (TK + "/oilSpill_small.png",  "tiles/oil_spill.png"),
    # 特效
    (PT + "/muzzle_01.png", "fx/muzzle.png"),
    (PT + "/muzzle_03.png", "fx/muzzle_2.png"),
    (PT + "/smoke_05.png",  "fx/smoke.png"),
    (PT + "/smoke_02.png",  "fx/smoke_dark.png"),
    (PT + "/fire_01.png",   "fx/fire.png"),
    (PT + "/flame_03.png",  "fx/flame.png"),
    (PT + "/spark_03.png",  "fx/spark.png"),
    (PT + "/scorch_01.png", "fx/scorch.png"),
    (PT + "/trace_03.png",  "fx/trace.png"),
]

ok = fail = 0
for url, rel in FILES:
    dst = os.path.join(ROOT, rel.replace("/", os.sep))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.exists(dst) and os.path.getsize(dst) > 200:
        print("skip  %-32s" % rel); ok += 1; continue
    for attempt in range(3):
        try:
            urllib.request.urlretrieve(url, dst)
            print("ok    %-32s %d B" % (rel, os.path.getsize(dst)))
            ok += 1
            break
        except Exception as e:
            if attempt == 2:
                print("FAIL  %-32s %s" % (rel, e)); fail += 1
            else:
                time.sleep(0.6)
print("\n完成: %d 成功 / %d 失败" % (ok, fail))
sys.exit(1 if fail else 0)
