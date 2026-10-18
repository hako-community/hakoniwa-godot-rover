extends "res://addons/hakoniwa/scripts/hakoniwa_simulation_node.gd"
## 箱庭のアセットの時刻の扱いを hakoniwa-godot-drone の HakoAsset にそろえたもの（K53）。
##   hakoniwa-godot-drone（d520021）の Scripts/hakoniwa-sim/sim/HakoAsset.cs（_PhysicsProcess）と
##   core/impl/HakoAssetImpl.cs（Execute）：物理のフレームの時間を 1 ms ずつ刻み、刻みごとに
##   ①世界の時刻を自分の時刻として報告（heartbeat）②イベントを見て ③世界の時刻を超えない範囲で 1 ms 進めて PDU を読む。
## hakoniwa-godot の addon（無改変）は物理の 1 ティックで delta_time_usec（既定は物理の周期）だけ進め、
## 描画が遅れてティックが詰まると自分の時刻が世界から遅れ続けて、世界の時刻ごと PLANT を止めた（2 つのビューアの同時表示）。
## イベント・PDU・同期モードの扱いは addon の _tick_internal をそのまま使う。

const STEP_SEC := 0.001   # drone と同じ 1 ms
var _accumulated_sec := 0.0

func _init() -> void:
	delta_time_usec = 1000
	auto_sync_delta_time_with_physics = false

func _physics_process(delta: float) -> void:
	if _sync_state == SYNC_STATE_UNINITIALIZED or _sync_state == SYNC_STATE_TERMINATED or _sync_state == SYNC_STATE_ERROR:
		return
	_accumulated_sec += delta
	while _accumulated_sec >= STEP_SEC:
		# drone の Execute の先頭と同じ heartbeat（登録の後なので失敗しない）
		_core_asset.notify_simtime(_core_asset.get_world_time_usec())
		_tick_internal(true)
		_accumulated_sec -= STEP_SEC
