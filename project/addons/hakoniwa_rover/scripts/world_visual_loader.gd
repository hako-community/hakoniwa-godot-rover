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
			"hfield":
				var hm := _hfield_mesh(json_path.get_base_dir().path_join(str(g["hfield"]["file"])), g["hfield"]["size"])
				if hm == null:
					continue
				mi.mesh = hm
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


static func _hfield_mesh(path: String, size: Array) -> ArrayMesh:
	## MuJoCo の HField（export_world_visual.py が書いた、MuJoCo が実際に使う 0..1 の高さ）を三角形のメッシュにする。
	##   格子点 (行 r, 列 c) = FLU (−sx + 2sx·c/(nc−1), −sy + 2sy·r/(nr−1), h·sz)。行 0 = −y
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[rover] HField を開けません: %s" % path)
		return null
	var nr := f.get_32()
	var nc := f.get_32()
	var h := f.get_buffer(nr * nc * 4).to_float32_array()
	var sx := float(size[0])
	var sy := float(size[1])
	var sz := float(size[2])
	var dx := 2.0 * sx / (nc - 1)
	var dy := 2.0 * sy / (nr - 1)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(nr * nc)
	normals.resize(nr * nc)
	for r in nr:
		for c in nc:
			var i := r * nc + c
			verts[i] = RoverFrames.pos(Vector3(-sx + dx * c, -sy + dy * r, h[i] * sz))
			# 法線：中心差分（端は片側）
			var zl := h[r * nc + max(c - 1, 0)] * sz
			var zr := h[r * nc + min(c + 1, nc - 1)] * sz
			var zd := h[max(r - 1, 0) * nc + c] * sz
			var zu := h[min(r + 1, nr - 1) * nc + c] * sz
			var gx := (zr - zl) / (dx * float(min(c + 1, nc - 1) - max(c - 1, 0)))
			var gy := (zu - zd) / (dy * float(min(r + 1, nr - 1) - max(r - 1, 0)))
			normals[i] = RoverFrames.pos(Vector3(-gx, -gy, 1.0).normalized())
	var idx := PackedInt32Array()
	idx.resize((nr - 1) * (nc - 1) * 6)
	var k := 0
	for r in nr - 1:
		for c in nc - 1:
			var a := r * nc + c
			var b := a + 1
			var d := a + nc
			var e := d + 1
			# 対角は (r,c)–(r+1,c+1)。Godot は時計回りが表（上から見て）
			idx[k] = a; idx[k + 1] = e; idx[k + 2] = b
			idx[k + 3] = a; idx[k + 4] = d; idx[k + 5] = e
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
