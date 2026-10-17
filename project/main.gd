extends Node3D
## 月面ローバの軽量ビューア（方式A：hakoniwa-godot ＋ 追加機能 addon hakoniwa_rover）
##
## 起動（箱庭あり）：マスタ → PLANT（rover_sim）→ このビューア → hako-cmd start
##   （hakoniwa-mujoco-rover の scripts\windows\run_sim.ps1 -Godot が順に起動する）
## 引数（-- のあと）：
##   --offline            箱庭につながずに表示だけ（形・地形・光の確認用）
##   --shot <png>         画面を保存（--shot-after 秒後）
##   --quit-after <秒>     自動で終了
##   --config <json>      設定（既定 res://config/rover_viewer.json）
##   --world-visual <json> 地形・岩の配置表（既定は設定の world_visual。run_sim.ps1 -World が渡す）
##   --cam-top            真上から見る（操舵・車輪の向きの確認用）
##   --dump-joints        2 秒ごとに、受信した操舵角と描いたノードの回転を並べてログに出す（関節の同期の確認用）
##   --terrain-check <csv> 検査点（x,y：FLU）の真上から地形にレイを当て、<csv>.godot.csv に x,y,z を書いて終了
##                         （hakoniwa-mujoco-rover の tools/check_terrain.py --godot で MuJoCo・DEM と比べる）

# ロボット同期は hakoniwa_robot_sync（install_addons.ps1 で入れる）を継承するので、箱庭につなぐときだけ読む
const ROVER_SYNC_PATH := "res://addons/hakoniwa_rover/scripts/rover_sync_controller.gd"

var cfg: Dictionary = {}
var args := {"offline": false, "shot": "", "shot_after": 10.0, "quit_after": -1.0, "config": "res://config/rover_viewer.json",
		"world_visual": "", "terrain_check": "", "cam_top": false, "dump_joints": false}
var dump_next := 2.0
var terrain: Node3D
var check_frames := 0
var t0 := 0.0
var shot_done := false
var hako_sim = null
var sync = null
var ros_root: Node3D
var cam: Camera3D
var hud: Label
var prev_pos := Vector3.ZERO
var speed := 0.0


func _ready() -> void:
	_parse_args()
	cfg = JSON.parse_string(FileAccess.get_file_as_string(args["config"]))
	t0 = Time.get_ticks_msec() / 1000.0
	var mroot := _resolve(str(cfg["mujoco_rover_root"]))

	RoverLunarEnvironment.build(self, cfg)
	terrain = Node3D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var wv: String = args["world_visual"] if args["world_visual"] != "" else mroot.path_join(str(cfg["world_visual"]))
	var n := RoverWorldVisualLoader.build(terrain, wv, float(cfg.get("regolith_albedo", 0.16)))
	print("[rover_viewer] terrain geoms=%d (%s)" % [n, wv.get_file()])
	if args["terrain_check"] != "":
		for mi in terrain.get_children():
			(mi as MeshInstance3D).create_trimesh_collision()
		return

	# ROS（FLU）の世界に置く根：基底 C（ロボット同期はこの下を FLU として扱う）
	ros_root = Node3D.new()
	ros_root.name = "RosToGodot"
	ros_root.transform = Transform3D(RoverFrames.C, Vector3.ZERO)
	add_child(ros_root)
	# GLB は Godot 座標で作られているので C⁻¹ で戻す。PLANT の車体の原点は地面から h0 上にある
	var h0 := float(JSON.parse_string(FileAccess.get_file_as_string(mroot.path_join(str(cfg["body_mass_json"]))))["chassis_origin_height_m"])
	var visual := Node3D.new()
	visual.name = "RoverVisual"
	visual.transform = Transform3D(RoverFrames.C.inverse(), Vector3(0, 0, -h0))
	ros_root.add_child(visual)
	var model := _load_glb(mroot.path_join(str(cfg["body_glb"])))
	if model == null:
		return
	visual.add_child(model)
	# ★ 箱庭につなぐときは根を動かさない（ロボット同期は根の最初の姿勢を「基準」として覚え、毎回それに掛けるので、
	#   ここで持ち上げると物理より h0 だけ高く描かれる）。表示だけのときは PLANT の初期位置に置く
	if args["offline"]:
		ros_root.position = RoverFrames.pos(Vector3(0, 0, h0))

	var profile_path := _write_profile(model)
	_setup_camera_and_hud()
	if args["offline"]:
		print("[rover_viewer] offline（箱庭につながない）")
		return
	_setup_hakoniwa(profile_path)


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		match a[i]:
			"--offline": args["offline"] = true
			"--shot": i += 1; args["shot"] = a[i]
			"--shot-after": i += 1; args["shot_after"] = float(a[i])
			"--quit-after": i += 1; args["quit_after"] = float(a[i])
			"--config": i += 1; args["config"] = a[i]
			"--world-visual": i += 1; args["world_visual"] = a[i]
			"--terrain-check": i += 1; args["terrain_check"] = a[i]
			"--cam-top": args["cam_top"] = true
			"--dump-joints": args["dump_joints"] = true
		i += 1


func _resolve(p: String) -> String:
	if p.is_absolute_path():
		return p
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


func _load_glb(path: String) -> Node3D:
	## GLB は実行時に読む（公開リポジトリに GLB を入れないため。インポートも不要）
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("[rover_viewer] GLB を読めません（%d）: %s" % [err, path])
		return null
	var scene := doc.generate_scene(state) as Node3D
	print("[rover_viewer] model: %s" % path)
	return scene


func _write_profile(model: Node3D) -> String:
	## GLB のノード名（susp_* / steer_* / wheel_*）から、関節名 ↔ ノードの対応表を作る。
	## 名前の約束は image2sim の build_rover.py と hakoniwa-mujoco-rover の MJCF で共通。
	##   車輪：Godot のローカル X 軸まわり、ROS の前進回転（+y 軸）は Godot では −X → sign −1
	##   操舵：Godot のローカル Y 軸まわり（上）、ROS の +z と同じ向き → sign +1
	##   懸架：Godot のローカル Y 方向の移動（上）→ slide_mappings
	var joints := []
	var slides := []
	for node in model.find_children("*", "Node3D", true, false):
		var nm := String(node.name)
		var path := String(ros_root.get_path_to(node))
		if nm.begins_with("wheel_") and nm.count("_") == 1:
			joints.append({"joint_name": nm, "node_path": path, "axis": "x", "sign": -1.0, "offset_rad": 0.0, "apply_mode": "basis_delta"})
		elif nm.begins_with("steer_"):
			joints.append({"joint_name": nm, "node_path": path, "axis": "y", "sign": 1.0, "offset_rad": 0.0, "apply_mode": "basis_delta"})
		elif nm.begins_with("susp_"):
			slides.append({"joint_name": nm, "node_path": path, "axis": "y", "sign": 1.0})
	var profile := {
		"version": 1, "robot_name": cfg["robot_name"],
		"base_link_pdu_name": cfg["base_link_pdu_name"], "joint_states_pdu_name": cfg["joint_states_pdu_name"],
		"base_node_path": "RoverVisual",
		"coordinate_system": {"position_rule": "hakoniwa_to_godot", "rotation_rule": "hakoniwa_to_godot"},
		"joint_mappings": joints, "slide_mappings": slides,
	}
	var p := "user://rover_robot_sync.profile.json"
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(profile, "  "))
	f.close()
	print("[rover_viewer] profile: joints=%d slides=%d -> %s" % [joints.size(), slides.size(), ProjectSettings.globalize_path(p)])
	return p


func _setup_hakoniwa(profile_path: String) -> void:
	if load("res://addons/hakoniwa/hakoniwa.gdextension") == null:
		push_error("[rover_viewer] hakoniwa-godot（GDExtension）を読めません。scripts\\windows\\install_addons.ps1 を実行")
		return
	var codec = load("res://addons/hakoniwa/scripts/hakoniwa_codec_node.gd").new()
	codec.name = "HakoniwaCodecNode"
	codec.codec_manifest_path = "res://addons/hakoniwa/codec_manifest.json"
	codec.load_on_ready = true
	add_child(codec)
	hako_sim = load("res://addons/hakoniwa/scripts/hakoniwa_simulation_node.gd").new()
	hako_sim.name = "HakoniwaSimNode"
	hako_sim.asset_name = str(cfg.get("asset_name", "RoverViewer"))
	hako_sim.use_internal_shm_endpoint = true
	hako_sim.shm_endpoint_config_path = "res://config/endpoint_shm.json"
	hako_sim.codec_node_path = NodePath("../HakoniwaCodecNode")
	hako_sim.delta_time_usec = int(cfg.get("delta_time_usec", 20000))
	hako_sim.auto_initialize_on_ready = true
	hako_sim.simulation_ready.connect(func(): print("[rover_viewer] registered. waiting for 'hako-cmd start'"))
	hako_sim.simulation_started.connect(func(): print("[rover_viewer] hakoniwa started"))
	add_child(hako_sim)
	sync = load(ROVER_SYNC_PATH).new()
	sync.name = "RoverSync"
	sync.sim_node_path = NodePath("../HakoniwaSimNode")
	sync.target_root_path = NodePath("../RosToGodot")
	sync.profile_path = profile_path
	add_child(sync)


func _physics_process(_delta: float) -> void:
	if args["terrain_check"] == "":
		return
	check_frames += 1
	if check_frames < 3:
		return
	# 検査点の真上から下へレイ（FLU → Godot の変換は RoverFrames だけ）
	var space := get_world_3d().direct_space_state
	var lines := FileAccess.get_file_as_string(args["terrain_check"]).split("\n", false)
	var out := FileAccess.open(str(args["terrain_check"]).get_basename() + ".godot.csv", FileAccess.WRITE)
	out.store_line("x,y,z")
	var hit := 0
	for k in range(1, lines.size()):
		var xy := lines[k].strip_edges().split(",")
		var x := float(xy[0])
		var y := float(xy[1])
		var q := PhysicsRayQueryParameters3D.create(RoverFrames.pos(Vector3(x, y, 5000.0)), RoverFrames.pos(Vector3(x, y, -5000.0)))
		var r := space.intersect_ray(q)
		if r.is_empty():
			continue
		var flu := RoverFrames.C.inverse() * (r["position"] as Vector3)
		out.store_line("%s,%s,%.4f" % [xy[0], xy[1], flu.z])
		hit += 1
	out.close()
	print("[rover_viewer] terrain check: %d/%d points -> %s" % [hit, lines.size() - 1, str(args["terrain_check"]).get_basename() + ".godot.csv"])
	get_tree().quit()


func _setup_camera_and_hud() -> void:
	cam = Camera3D.new()
	cam.name = "ChaseCamera"
	cam.fov = 50.0
	cam.far = 2000.0
	add_child(cam)
	cam.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 20)
	layer.add_child(hud)


func _process(delta: float) -> void:
	if ros_root == null or cam == null:
		return
	# 追従カメラ：ローバの左後ろ・少し上から
	var p := ros_root.global_position
	var fwd := ros_root.global_transform.basis * Vector3(1, 0, 0)   # 根は FLU の座標なので +x が前
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var left := Vector3.UP.cross(fwd).normalized()
	if args["cam_top"]:
		# 真上から（操舵・車輪の向きの確認用）。画面の上 = ローバの前
		cam.global_position = p + Vector3.UP * 16.0
		cam.look_at(p, fwd)
	else:
		var eye := p - fwd * 11.0 + left * 7.0 + Vector3.UP * 3.5
		cam.global_position = cam.global_position.lerp(eye, clamp(delta * 3.0, 0.0, 1.0)) if Engine.get_frames_drawn() > 2 else eye
		cam.look_at(p + Vector3.UP * 0.8, Vector3.UP)
	_update_hud_and_shot(delta, p)


func _dump_joints() -> void:
	if sync == null or sync.last_joint_states.is_empty():
		return
	var js: Dictionary = sync.last_joint_states
	var names: Array = js.get("name", [])
	var pos: Array = js.get("position", [])
	var parts := []
	for i in range(min(names.size(), pos.size())):
		var nm := str(names[i])
		if nm.begins_with("steer_"):
			parts.append("%s recv=%+.1f drawn=%+.1f" % [nm, rad_to_deg(float(pos[i])), sync.rendered_joint_deg(nm)])
	print("[rover_viewer] joints: " + "  ".join(parts))


func _update_hud_and_shot(delta: float, p: Vector3) -> void:
	if args["dump_joints"] and hako_sim != null and hako_sim.get_simtime_usec() / 1e6 > dump_next:
		dump_next += 2.0
		_dump_joints()
	if delta > 0.0:
		speed = lerp(speed, (p - prev_pos).length() / delta, 0.1)
	prev_pos = p
	var flu := RoverFrames.C.inverse() * p
	var st := "offline" if args["offline"] else ("running" if hako_sim != null and hako_sim.get_state() >= 0 else "-")
	var simt: float = (hako_sim.get_simtime_usec() / 1e6) if hako_sim != null else 0.0
	hud.text = "Lunar rover (PoC)  sim %.1f s  [%s]\nx %.2f  y %.2f  z %.2f m   speed %.2f m/s" % [simt, st, flu.x, flu.y, flu.z, speed]

	var t := Time.get_ticks_msec() / 1000.0 - t0
	if args["shot"] != "" and not shot_done and t > float(args["shot_after"]):
		shot_done = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(args["shot"])
		print("[rover_viewer] shot: %s" % args["shot"])
	if float(args["quit_after"]) > 0.0 and t > float(args["quit_after"]):
		get_tree().quit()
