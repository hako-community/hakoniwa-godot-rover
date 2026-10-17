# hakoniwa-godot-rover — 月面ローバの Godot 軽量ビューア

[hakoniwa-godot](https://github.com/hakoniwalab/hakoniwa-godot)（他者のリポジトリ）を**無改変の submodule**として使い、
月面ローバに要る**追加機能だけ**をこのリポジトリで持つ Godot プロジェクトです。

- 物理は [hakoniwa-mujoco-rover](https://github.com/hako-community/hakoniwa-mujoco-rover)（PLANT `rover_sim`）。このリポジトリは**絵だけ**。
- 作りは hakoniwa-humanoid の Godot ビューア・hakoniwa-godot-robot と同じ考え方
  （hakoniwa-godot の addon はビルド済み SDK / submodule から入れる生成物。リポジトリには入れない）。
- 主ビューア（高品質な月面の映像・操縦訓練）は `hakoniwa-unreal-rover`。こちらは物理の開発者向け・CI・ヘッドレス撮影用。

**状態（2026-10-17）**: 雛形（構成と submodule の固定だけ）。シーンと追加機能はこれから。

---

## 構成

```
third_party/hakoniwa-godot/        ★submodule（無改変・commit 固定）。読むだけ
project/                           Godot プロジェクト（Godot 4.7 mono / Forward+ を予定）
├── addons/hakoniwa/               ← 入れる（SDK のビルド済み addon）      ※git 管理外
├── addons/hakoniwa_msgs/          ← 入れる（同上）                         ※git 管理外
├── addons/hakoniwa_robot_sync/    ← 入れる（submodule の GDScript をコピー）※git 管理外
├── addons/hakoniwa_rover/         ★このリポジトリの追加機能（正本）
├── config/                        robot_sync.profile.json・endpoint（hakoniwa-mujoco-rover の forge で生成して置く）
└── scenes/                        ローバのシーン
scripts/windows/                   addon を入れるスクリプト・起動スクリプト
```

## 追加機能（`project/addons/hakoniwa_rover/`）の予定

| 機能 | 中身 | 手本 |
|---|---|---|
| 月面の空と光 | 黒い空・散乱光ゼロ・太陽を方位と高度で置く（位置暦は PLANT か環境アセットから）・自動露出なし | hakoniwa-godot-drone の `planet_environment.gd`（考え方のみ） |
| 仮のローバ | GLB ができるまで、MJCF の body 名（chassis / susp_* / steer_* / wheel_*）と同じ名前の箱・円柱を組む | — |
| 直動関節の同期 | 懸架（slide）を `hakoniwa_robot_sync`（回転関節前提）の外で反映する | hakoniwa-godot の `robot_sync_controller.gd` |
| 地形と岩 | 共通標高格子のタイル・岩の配置表（物理と同じもの）を読む | hakoniwa-simenv-data の `obb2godot` |
| 撮影 | ヘッドレスで定点・追従カメラの PNG を出す（CI の絵の確認） | hakoniwa-godot-drone の `FlightShotRecorder` |

## これからの手順

1. `scripts/windows/install_addons.ps1`：SDK のビルド済み addon（`hakoniwa`・`hakoniwa_msgs`）と、
   submodule の `hakoniwa_robot_sync` の GDScript を `project/addons/` へ入れる
   （hakoniwa-humanoid の `install_godot_addon.ps1` と同じ。codec_manifest は建てた型だけに絞る）
2. hakoniwa-mujoco-rover の `bodies/lunar_cruiser/config/godot_sync.yaml` から forge で
   `robot_sync.profile.json` と endpoint を作り、`project/config/` に置く
3. `scenes/rover_viewer.tscn`：HakoniwaSimNode・RobotSyncController・仮のローバ・月面の光
4. 起動順：マスタ → PLANT → **Godot** → hako-cmd start（hakoniwa-mujoco-rover の `run_sim.ps1` に Godot を足す）

## ライセンス

未定。submodule の hakoniwa-godot は MIT。
