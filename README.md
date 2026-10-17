# hakoniwa-godot-rover — 月面ローバの Godot 軽量ビューア

[hakoniwa-godot](https://github.com/hakoniwalab/hakoniwa-godot)（他者のリポジトリ）を**無改変の submodule**として使い、
月面ローバに要る**追加機能だけ**をこのリポジトリで持つ Godot プロジェクトです。

- 物理は [hakoniwa-mujoco-rover](https://github.com/hako-community/hakoniwa-mujoco-rover)（PLANT `rover_sim`）。このリポジトリは**絵だけ**。
- 作りは hakoniwa-humanoid の Godot ビューア・hakoniwa-godot-robot と同じ考え方
  （hakoniwa-godot の addon はビルド済み SDK / submodule から入れる生成物。リポジトリには入れない）。
- 主ビューア（高品質な月面の映像・操縦訓練）は `hakoniwa-unreal-rover`。こちらは物理の開発者向け・CI・ヘッドレス撮影用。

**状態（2026-10-17）**: 箱庭の PLANT（`rover_sim`）につないで、ローバの位置・姿勢・車輪・操舵・懸架を実時間で描ける。
月面の空と光、試験コース（物理と同じ配置表から）、追従カメラ、HUD。

---

## 使い方（Windows）

```powershell
git -c core.longpaths=true clone --recurse-submodules https://github.com/hako-community/hakoniwa-godot-rover.git
cd hakoniwa-godot-rover
copy scripts\windows\config.example.ps1 scripts\windows\config.local.ps1   # 場所を書き換える

# 1) hakoniwa-godot（GDExtension）をビルド：third_party の外へ書き出してビルドする（初回は数分）
powershell -ExecutionPolicy Bypass -File scripts\windows\build_addon.ps1
# 2) addon をプロジェクトへ入れる（hakoniwa・hakoniwa_msgs・hakoniwa_robot_sync）
powershell -ExecutionPolicy Bypass -File scripts\windows\install_addons.ps1
# 3) 一度インポートしておく（class_name の登録）
<Godot>_console.exe --headless --path project --import

# 箱庭なしで表示だけ（形・地形・光の確認）
<Godot>.exe --path project -- --offline
# 箱庭につなぐ：hakoniwa-mujoco-rover 側から（マスタ → PLANT → このビューア → hako-cmd start）
#   powershell -ExecutionPolicy Bypass -File scripts\windows\run_sim.ps1 -Seconds 60 -CmdVel "0.97,0" -Godot
```

- GLB・コースの配置表・質量表は **hakoniwa-mujoco-rover から実行時に読む**（このリポジトリには入れない）。場所は `project/config/rover_viewer.json`。
- 引数：`--offline`（箱庭なし）、`--shot <png> --shot-after <秒>`（画面を保存）、`--quit-after <秒>`、
  `--world-visual <json>`（地形の配置表。hakoniwa-mujoco-rover の `run_sim.ps1 -World` が渡す）、
  `--terrain-check <csv>`（検査点に真上からレイを当てて高さを書き出す。mujoco-rover の `tools/check_terrain.py --godot` で物理・DEM と比べる）。

## 構成

```
third_party/hakoniwa-godot/        ★submodule（無改変・commit 固定）。読むだけ
project/                           Godot プロジェクト（Godot 4.7 / Forward+）
├── main.gd / main.tscn            ビューア本体（設定 → 月面 → 地形 → GLB → 関節の対応表 → 箱庭 → カメラ・HUD）
├── config/                        rover_viewer.json（場所・太陽・反射率）、箱庭の endpoint（SHM poll）・PDU 定義
├── addons/hakoniwa/               ← build_addon / install_addons で入れる  ※git 管理外
├── addons/hakoniwa_msgs/          ← 同上                                     ※git 管理外
├── addons/hakoniwa_robot_sync/    ← submodule の GDScript をコピー           ※git 管理外
└── addons/hakoniwa_rover/         ★このリポジトリの追加機能（正本）
scripts/windows/                   build_addon.ps1・install_addons.ps1・config.example.ps1
```

## 追加機能（`project/addons/hakoniwa_rover/scripts/`）

| スクリプト | 中身 |
|---|---|
| `frames.gd` | 座標変換を 1 か所に（FLU → Godot：(x, y, z) → (−y, z, −x)） |
| `lunar_environment.gd` | 黒い空・環境光ほぼ 0・霧なし・太陽を方位と高度で置く・視直径 0.53° の影 |
| `world_visual_loader.gd` | hakoniwa-mujoco-rover の `tools/export_world_visual.py` の配置表から地形・岩を組む（**物理と同じ配置**）。DEM の HField は MuJoCo が使う高さそのものから三角形のメッシュを作る（物理との差 1 mm 以下を確認） |
| `rover_sync_controller.gd` | `hakoniwa_robot_sync` を継承し、直動関節（懸架の上下）の反映を足したもの |

- 関節の対応表（robot_sync の profile）は、GLB のノード名（`susp_*`・`steer_*`・`wheel_*`）から実行時に作る。
  名前の約束は image2sim の生成器・hakoniwa-mujoco-rover の MJCF と共通。
- addon の codec には `geometry_msgs`（車体の姿勢）と `sensor_msgs`（関節）が要る（`build_addon.ps1` の既定）。

## これから

| 項目 | 内容 |
|---|---|
| 照り返し・カメラ | 間接光・カメラモデルは主ビューア（Unreal）で。ここは軽量のまま |
| 地形 | DEM の 1 タイルは読める（ROV-16）。車両まわりのタイル切替・岩のインスタンス配置 |
| CI | `--offline --shot` で絵の回帰（ヘッドレスでは描画されないので窓ありで撮る） |

## ライセンス

[MIT License](./LICENSE)（Copyright (c) 2026 Hakoniwa Community）。submodule の hakoniwa-godot も MIT です。
