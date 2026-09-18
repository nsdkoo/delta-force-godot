# 素材与参考来源

本项目为个人练习作品。这里记录每一份外部素材 / 参考项目的来源，
方便日后追溯，也方便需要公开发布时补齐署名。

---

## 美术素材

| 来源 | 内容 | 授权 |
|---|---|---|
| [Kenney](https://kenney.nl) — **Top-down Tanks Redux** | 载具车体与炮塔（含 `*_outline` 描边版）、树木、灌木、岩石、油桶、木箱、拒马、沙袋、铁丝网、栅栏、油污、履带痕迹、爆炸 5 帧序列、爆炸烟 5 帧序列、曳光贴片、草地/沙地道路砖 | CC0 1.0 |
| [Kenney](https://kenney.nl) — **Tower Defense (top-down)** | 工事用的塔与炮位（碉堡/炮位/炮塔）、俯视飞行器、火焰图标、地面散落物 | CC0 1.0 |
| [Kenney](https://kenney.nl) — **Topdown Shooter** | 干员贴图（`assets/operators/`） | CC0 1.0 |
| [ambientCG](https://ambientcg.com) | 地表 PBR 材质（沙地 / 沥青 / 混凝土等），由 `_bake_terrain.py` 烘焙成 `assets/terrain/`。**当前默认关闭**（`jinqiu_map.gd` 的 `USE_BAKED_GROUND = false`）—— 照片质感的地表和卡通平涂的风格不兼容，文件保留备切换 | CC0 |

CC0 允许商用、免署名。

## 参考的开源项目

这三个项目是在做美术与架构调研时拉下来的，用来对照"别人怎么组织同类游戏"。
**没有把它们的代码或素材复制进本项目** —— 参考的是结构与做法。

| 项目 | 看了什么 | 授权 |
|---|---|---|
| [SakuyaCN/TowDownGame](https://github.com/SakuyaCN/TowDownGame) | Godot 4 完整俯视射击的目录组织：`autoload/` 放全局单例、`game/` 放玩法、`sprites/`+`shader/` 分离表现层 | GPL-3.0（仅阅读） |
| [jgenard/Tanks-of-Freedom](https://github.com/jgenard/Tanks-of-Freedom) | 回合制战术的据点/单位数据结构、地图编辑器思路 | MIT |
| [YumiNoona/Onslaught](https://github.com/YumiNoona/Onslaught) | 数据驱动武器（`WeaponData` 资源 + `.tres` 配置）、信号解耦、web 导出的坑 | 未复制内容 |

## 音频

全部由 `autoload/audio_manager.gd` 在启动时用数学合成（噪声包络 + 一阶低通 + 纯音），
**零外部音频文件**。
