class_name RoverWorldVisualLoader
extends RefCounted
## 物理の MJCF から書き出した配置表（hakoniwa-mujoco-rover の tools/export_world_visual.py）で地形・岩を組む。
## ★ 物理と絵で同じ配置表を使う（検討書 R12）。ここで形を足したり動かしたりしない。

static func build(parent: Node3D, json_path: String, albedo: float) -> int:
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		push_error("[rover] 配置表を開けません: %s" % json_path)
		return 0
	var doc = JSON.parse_string(f.get_as_text())
	var soil := RoverLunarEnvironment.regolith_material(albedo)
	var rock := RoverLunarEnvironment.regolith_material(albedo * 0.7)
	var n := 0
	for g in doc.get("geoms", []):
		var mi := MeshInstance3D.new()
		mi.name = str(g["name"])
		var s: Array = g["size"]
		match str(g["type"]):
			"plane":
				var pm := PlaneMesh.new()
				pm.size = Vector2(float(s[1]) * 2.0, float(s[0]) * 2.0)
				mi.mesh = pm
			"box":
				var bm := BoxMesh.new()
				bm.size = RoverFrames.extent(Vector3(s[0], s[1], s[2]))
				mi.mesh = bm
			_:
				continue
		mi.material_override = rock if int(g.get("group", 1)) == 4 else soil
		var p: Array = g["pos"]
		mi.transform = Transform3D(RoverFrames.basis(g["mat"]), RoverFrames.pos(Vector3(p[0], p[1], p[2])))
		parent.add_child(mi)
		n += 1
	return n
