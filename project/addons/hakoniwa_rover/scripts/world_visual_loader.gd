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
	if doc.has("rocks"):
		n += _build_rocks(parent, json_path.get_base_dir().path_join(str(doc["rocks"]["file"])), rock)
	return n


static func rock_transform(r: Array) -> Transform3D:
	## 配置表の 1 行（x y z a b c qw qx qy qz …、FLU）→ Godot の変換（単位球のメッシュを楕円体へ）
	var q := Quaternion(float(r[7]), float(r[8]), float(r[9]), float(r[6]))   # Godot の Quaternion は (x, y, z, w)
	var m := Basis(q) * Basis.from_scale(Vector3(float(r[3]), float(r[4]), float(r[5])))
	return Transform3D(RoverFrames.C * m * RoverFrames.C.inverse(), RoverFrames.pos(Vector3(float(r[0]), float(r[1]), float(r[2]))))


static func rock_mesh(src: Dictionary) -> ArrayMesh:
	## 配置表の meshes の 1 つ（FLU の単位球の内側）→ Godot のメッシュ。表の向きは外向きにそろえる
	var v: Array = src["vertices"]
	var t: Array = src["triangles"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(0, t.size(), 3):
		var p := []
		for j in 3:
			var i := int(t[k + j])
			p.append(RoverFrames.pos(Vector3(float(v[3 * i]), float(v[3 * i + 1]), float(v[3 * i + 2]))))
		# Godot は時計回り（外から見て）が表：外向きの法線になる並びの逆順で入れる
		if (p[1] - p[0]).cross(p[2] - p[0]).dot(p[0]) > 0.0:
			p = [p[0], p[2], p[1]]
		for j in 3:
			st.add_vertex(p[j])
	st.generate_normals()
	return st.commit()


static func _build_rocks(parent: Node3D, path: String, mat: Material) -> int:
	## 岩（hakoniwa-mujoco-rover の tools/rock_field.py の配置表）。物理は車両の近くだけ持つが、絵は全部描く。
	## メッシュの種類ごとに MultiMesh 1 つ
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[rover] 岩の配置表を開けません: %s" % path)
		return 0
	var doc = JSON.parse_string(f.get_as_text())
	var meshes: Array = doc["meshes"]
	var groups := []
	for i in meshes.size():
		groups.append([])
	for r in doc["rocks"]:
		groups[int(r[10])].append(r)
	var root := Node3D.new()
	root.name = "Rocks"
	parent.add_child(root)
	for i in meshes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = rock_mesh(meshes[i])
		mm.instance_count = groups[i].size()
		for k in groups[i].size():
			mm.set_instance_transform(k, rock_transform(groups[i][k]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Rocks_%d" % i
		mmi.multimesh = mm
		mmi.material_override = mat
		root.add_child(mmi)
	root.set_meta("rocks_doc", doc)
	print("[rover] rocks: %d (%d meshes) from %s" % [doc["rocks"].size(), meshes.size(), path.get_file()])
	return doc["rocks"].size()


static func add_rock_collisions(parent: Node3D, points: Array, reach: float) -> int:
	## 検査用：検査点（FLU の x, y）から reach [m] 以内に中心がある岩に、絵と同じ形の当たり判定を付ける
	var root := parent.get_node_or_null("Rocks")
	if root == null:
		return 0
	var doc: Dictionary = root.get_meta("rocks_doc")
	var cell := {}
	for p in points:
		var key := Vector2i(floori(p.x / reach), floori(p.y / reach))
		if not cell.has(key):
			cell[key] = []
		cell[key].append(p)
	var faces := {}
	var n := 0
	for r in doc["rocks"]:
		var c := Vector2(float(r[0]), float(r[1]))
		var key := Vector2i(floori(c.x / reach), floori(c.y / reach))
		var near := false
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for p in cell.get(key + Vector2i(dx, dy), []):
					if c.distance_to(p) <= reach:
						near = true
		if not near:
			continue
		var vi := int(r[10])
		if not faces.has(vi):
			faces[vi] = rock_mesh(doc["meshes"][vi]).get_faces()
		var xf := rock_transform(r)
		var baked := PackedVector3Array()
		for v in faces[vi]:
			baked.append(xf * v)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(baked)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)
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
