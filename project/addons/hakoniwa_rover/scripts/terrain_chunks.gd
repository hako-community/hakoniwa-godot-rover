class_name RoverTerrainChunks
extends Node3D
## 小クレータのある細かい地形（hakoniwa-simenv-data の crater_field.py --fine の 0.5 m 格子。ROV-28）を、カメラの近くだけ細かく描く。
##   地形を CHUNK_M 四方の区画に分け、ふだんは 5 m の HField（物理の MJCF の、絵だけの地面）の区画を描く。
##   カメラから FINE_DRAW_M 以内の区画は細かい格子のメッシュに差し替え（1 フレームに BUILD_PER_FRAME 区画まで作る）、
##   離れたら捨てて 5 m に戻す。
##   ★ 細かい格子を全部メッシュにすると 4001² 点で重すぎる（K55 と同じく GPU を使い切る）。
##   ★ 三角形は物理の HField と同じ（各マスを (0,0)–(1,1) の対角で切る）。頂点は細かい格子の点そのもの。
##   ★ 細かい区画と 5 m の区画の境目は、クレータが境をまたぐ所で少し段がつく（遠くなので許す）。

const CHUNK_M := 50.0
const FINE_DRAW_M := 150.0      # 区画の中心がカメラ（地面の上の位置）からこれより近ければ細かく描く
const FINE_KEEP_M := 200.0      # これより遠くなったら捨てる（行き来で作り直さないように幅を持たせる）
const BUILD_PER_FRAME := 2

var _material: Material
# 5 m の HField（0..1 と size）
var _cz: PackedFloat32Array
var _cnr := 0
var _cnc := 0
var _csize := Vector3.ZERO     # sx, sy, sz
var _cpos_z := 0.0
# 細かい格子（局所の高さ [m]）
var _fz: PackedFloat32Array
var _fnr := 0
var _fnc := 0
var _fres := 0.5
var _fhx := 0.0
var _fhy := 0.0
var _nchunk := 0
var _coarse := {}    # Vector2i → MeshInstance3D
var _fine := {}      # Vector2i → MeshInstance3D
var fine_built := 0


func setup(coarse_path: String, coarse_size: Array, coarse_pos_z: float, fine_path: String, fine: Dictionary, mat: Material) -> bool:
	_material = mat
	var f := FileAccess.open(coarse_path, FileAccess.READ)
	if f == null:
		push_error("[rover] HField を開けません: %s" % coarse_path)
		return false
	_cnr = f.get_32()
	_cnc = f.get_32()
	_cz = f.get_buffer(_cnr * _cnc * 4).to_float32_array()
	_csize = Vector3(float(coarse_size[0]), float(coarse_size[1]), float(coarse_size[2]))
	_cpos_z = coarse_pos_z
	var g := FileAccess.open(fine_path, FileAccess.READ)
	if g == null:
		push_error("[rover] 細かい格子を開けません（mujoco-rover の tools/make_world.py で作る）: %s" % fine_path)
		return false
	_fnr = g.get_32()
	_fnc = g.get_32()
	_fz = g.get_buffer(_fnr * _fnc * 4).to_float32_array()
	_fres = float(fine["resolution_m"])
	_fhx = float(fine["half_extent_m"][0])
	_fhy = float(fine["half_extent_m"][1])
	_nchunk = int(ceil(2.0 * _fhx / CHUNK_M))
	for i in _nchunk:
		for j in _nchunk:
			var key := Vector2i(i, j)
			var mi := MeshInstance3D.new()
			mi.name = "Coarse_%d_%d" % [i, j]
			mi.mesh = _coarse_mesh(key)
			mi.material_override = _material
			add_child(mi)
			_coarse[key] = mi
	print("[rover] terrain chunks: %d×%d of %.0f m, fine %d×%d @ %.2f m within %.0f m" % [_nchunk, _nchunk, CHUNK_M, _fnc, _fnr, _fres, FINE_DRAW_M])
	return true


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _nchunk == 0:
		return
	var p := RoverFrames.C.inverse() * cam.global_position     # Godot → FLU
	update_around(Vector2(p.x, p.y), BUILD_PER_FRAME)


## (x, y)（FLU）の周りの区画を細かくし、遠い区画を戻す。budget は作る区画の数の上限（−1 なら全部）
func update_around(xy: Vector2, budget: int) -> void:
	var want := []
	var r := int(ceil(FINE_DRAW_M / CHUNK_M)) + 1
	var ci := int(floor((xy.x + _fhx) / CHUNK_M))
	var cj := int(floor((xy.y + _fhy) / CHUNK_M))
	for i in range(ci - r, ci + r + 1):
		for j in range(cj - r, cj + r + 1):
			if i < 0 or j < 0 or i >= _nchunk or j >= _nchunk:
				continue
			var d := xy.distance_to(_chunk_center(Vector2i(i, j)))
			if d <= FINE_DRAW_M and not _fine.has(Vector2i(i, j)):
				want.append([d, Vector2i(i, j)])
	want.sort_custom(func(a, b): return a[0] < b[0])
	for k in want.size():
		if budget >= 0 and k >= budget:
			break
		ensure_fine(want[k][1])
	for key in _fine.keys():
		if xy.distance_to(_chunk_center(key)) > FINE_KEEP_M:
			(_fine[key] as MeshInstance3D).queue_free()
			_fine.erase(key)
			(_coarse[key] as MeshInstance3D).visible = true


## 区画を細かいメッシュにする（作ったメッシュを返す。検査で当たり判定を付けるのに使う）
func ensure_fine(key: Vector2i) -> MeshInstance3D:
	if _fine.has(key):
		return _fine[key]
	var mi := MeshInstance3D.new()
	mi.name = "Fine_%d_%d" % [key.x, key.y]
	mi.mesh = _fine_mesh(key)
	mi.material_override = _material
	add_child(mi)
	_fine[key] = mi
	(_coarse[key] as MeshInstance3D).visible = false
	fine_built += 1
	return mi


func chunk_of(xy: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor((xy.x + _fhx) / CHUNK_M)), 0, _nchunk - 1), clampi(int(floor((xy.y + _fhy) / CHUNK_M)), 0, _nchunk - 1))


func _chunk_center(key: Vector2i) -> Vector2:
	return Vector2(-_fhx + (key.x + 0.5) * CHUNK_M, -_fhy + (key.y + 0.5) * CHUNK_M)


func _fine_mesh(key: Vector2i) -> ArrayMesh:
	var per := int(round(CHUNK_M / _fres))
	var c0 := key.x * per
	var r0 := key.y * per
	var c1 := mini(c0 + per, _fnc - 1)
	var r1 := mini(r0 + per, _fnr - 1)
	return _grid_mesh(_fz, _fnr, _fnc, r0, r1, c0, c1, _fres, _fres, -_fhx, -_fhy, 1.0, 0.0)


func _coarse_mesh(key: Vector2i) -> ArrayMesh:
	var dx := 2.0 * _csize.x / (_cnc - 1)
	var dy := 2.0 * _csize.y / (_cnr - 1)
	var per := int(round(CHUNK_M / dx))
	var c0 := key.x * per
	var r0 := key.y * per
	var c1 := mini(c0 + per, _cnc - 1)
	var r1 := mini(r0 + per, _cnr - 1)
	return _grid_mesh(_cz, _cnr, _cnc, r0, r1, c0, c1, dx, dy, -_csize.x, -_csize.y, _csize.z, _cpos_z)


## 格子の一部（行 r0..r1・列 c0..c1）を三角形のメッシュにする。高さ = z[i]·zscale + zoff（FLU）。法線は格子全体の中心差分
static func _grid_mesh(z: PackedFloat32Array, nr: int, nc: int, r0: int, r1: int, c0: int, c1: int,
		dx: float, dy: float, x0: float, y0: float, zscale: float, zoff: float) -> ArrayMesh:
	var w := c1 - c0 + 1
	var h := r1 - r0 + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(w * h)
	normals.resize(w * h)
	for r in range(r0, r1 + 1):
		var rm := maxi(r - 1, 0)
		var rp := mini(r + 1, nr - 1)
		for c in range(c0, c1 + 1):
			var cm := maxi(c - 1, 0)
			var cp := mini(c + 1, nc - 1)
			var i := (r - r0) * w + (c - c0)
			verts[i] = RoverFrames.pos(Vector3(x0 + dx * c, y0 + dy * r, z[r * nc + c] * zscale + zoff))
			var gx := (z[r * nc + cp] - z[r * nc + cm]) * zscale / (dx * float(cp - cm))
			var gy := (z[rp * nc + c] - z[rm * nc + c]) * zscale / (dy * float(rp - rm))
			normals[i] = RoverFrames.pos(Vector3(-gx, -gy, 1.0).normalized())
	var idx := PackedInt32Array()
	idx.resize((w - 1) * (h - 1) * 6)
	var k := 0
	for r in h - 1:
		for c in w - 1:
			var a := r * w + c
			var b := a + 1
			var d := a + w
			var e := d + 1
			# 対角は (r,c)–(r+1,c+1)（物理の HField と同じ）。Godot は時計回りが表（上から見て）
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
