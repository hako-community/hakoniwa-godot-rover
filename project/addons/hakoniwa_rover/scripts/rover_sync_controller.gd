extends "res://addons/hakoniwa_robot_sync/scripts/robot_sync_controller.gd"
## hakoniwa_robot_sync（回転関節だけ）に、直動関節（懸架の上下）の反映を足したもの。
## profile に "slide_mappings": [{joint_name, node_path, axis, sign}] を書く。axis はノードのローカル軸。
## ★ hakoniwa-godot（他者のリポジトリ）は変えずに、継承でこのリポジトリ側に足す。

const _JointMapper = preload("res://addons/hakoniwa_robot_sync/scripts/joint_state_mapper.gd")
const _TfConverter = preload("res://addons/hakoniwa_robot_sync/scripts/transform_converter.gd")

var _initial_pos_by_path: Dictionary = {}
var last_base_pose: Dictionary = {}       # HUD 用（linear / angular）
var last_joint_states: Dictionary = {}    # 確認用（--dump-joints）


## 関節名 → ノードが初期の向きからどれだけ回ったか [deg]（profile の軸まわり）。描画が受信値どおりかの確認用
func rendered_joint_deg(joint_name: String) -> float:
	for m in _profile.get("joint_mappings", []):
		if str(m["joint_name"]) != joint_name:
			continue
		var path := str(m["node_path"])
		var node := _target_root.get_node_or_null(NodePath(path)) as Node3D
		if node == null or not _initial_basis_by_path.has(path):
			return NAN
		var rel: Basis = (_initial_basis_by_path[path] as Basis).inverse() * node.transform.basis
		var e := rel.get_euler()
		var ax := str(m.get("axis", "x"))
		var v := e.x if ax == "x" else (e.y if ax == "y" else e.z)
		return rad_to_deg(v) * float(m.get("sign", 1.0))
	return NAN


func _prepare_on_ready() -> void:
	super._prepare_on_ready()
	if not _ready_ok:
		return
	for m in _profile.get("slide_mappings", []):
		var node := _target_root.get_node_or_null(NodePath(str(m["node_path"])))
		if node is Node3D:
			_initial_pos_by_path[str(m["node_path"])] = (node as Node3D).position


func _on_simulation_step(_simtime_usec: int, _world_time_usec: int) -> void:
	if not _enabled or _endpoint == null or _base_link_endpoint == null or _joint_states_endpoint == null:
		return
	_endpoint.process_recv_events()
	var base: Dictionary = _base_link_endpoint.recv_dict()
	if apply_base_pose and not base.is_empty():
		last_base_pose = base
		_TfConverter.apply_base_pose(_target_root, _target_root_initial, base, _profile.get("coordinate_system", {}))
	var js: Dictionary = _joint_states_endpoint.recv_dict()
	if apply_joint_states and not js.is_empty():
		last_joint_states = js
		_JointMapper.apply_joint_states(_target_root, _profile, _initial_basis_by_path, js)
		_apply_slides(js)


func _apply_slides(js: Dictionary) -> void:
	var names: Array = js.get("name", [])
	var positions: Array = js.get("position", [])
	var lookup := {}
	for i in range(min(names.size(), positions.size())):
		lookup[str(names[i])] = float(positions[i])
	for m in _profile.get("slide_mappings", []):
		var jn := str(m["joint_name"])
		var path := str(m["node_path"])
		if not lookup.has(jn) or not _initial_pos_by_path.has(path):
			continue
		var node := _target_root.get_node_or_null(NodePath(path)) as Node3D
		var axis := Vector3.UP if str(m.get("axis", "y")) == "y" else (Vector3.RIGHT if str(m["axis"]) == "x" else Vector3.BACK)
		node.position = _initial_pos_by_path[path] + axis * float(m.get("sign", 1.0)) * lookup[jn]
