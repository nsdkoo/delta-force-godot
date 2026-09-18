# 素材与参考来源

本项目为个人练习作品。这里记录每一份外部素材 / 参考项目的来源，
方便日后追溯，也方便需要公开发布时补齐署名。

---

## 美术素材

| 来源 | 内容 | 授权 |
|---|---|---|
| [Kenney](https://kenney.nl) — **Top-down Tanks Redux** + **Tower Defense** | 载具、工事、箱体、沙袋；**当前默认建筑主视觉**（军事俯视，替代 Tiny Swords 中世纪塔楼） | CC0 1.0 |
| [Tiny Swords](https://pixelfrog-assets.itch.io/tiny-swords) — **Pixel Frog** | 建筑/装饰备用资源（仍保留在 `assets/buildings`、`assets/decor_kr`） | 可商用；禁止再分发素材包；建议署名 |
| [Kenney](https://kenney.nl) — **Tower Defense (isometric)** | 等距塔件与地景细节（备用） | CC0 1.0 |
| [CraftPix](https://craftpix.net) — **Stone Tower Game Assets** | 石塔/工事局部（备用） | Royalty-free |
| [ambientCG](https://ambientcg.com) | 地表 PBR 材质（沙地 / 沥青 / 混凝土等），由 `_bake_terrain.py` 烘焙成 `assets/terrain/`。**当前默认关闭**（`jinqiu_map.gd` 的 `USE_BAKED_GROUND = false`）—— 照片质感的地表和卡通平涂的风格不兼容，文件保留备切换 | CC0 |

CC0 / Tiny Swords 许可均允许商用；Tiny Swords 建议署名 Pixel Frog，且不得把素材包原样再分发。

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
