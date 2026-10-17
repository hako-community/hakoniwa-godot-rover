class_name RoverFrames
extends RefCounted
## 座標変換を 1 か所にまとめる。
## 箱庭・MuJoCo は FLU（x 前・y 左・z 上）、Godot は Y 上・−Z 前・+X 右。
##   Godot = C · FLU、C の列 = (x→(0,0,−1), y→(−1,0,0), z→(0,1,0))
## hakoniwa_robot_sync の ros_position_to_godot と同じ変換。

const C := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))


static func pos(flu: Vector3) -> Vector3:
	return C * flu


static func basis(flu_rows: Array) -> Basis:
	## MuJoCo の 3×3（行優先）を Godot の Basis へ：C · M · C⁻¹
	var m := Basis(
		Vector3(flu_rows[0], flu_rows[3], flu_rows[6]),
		Vector3(flu_rows[1], flu_rows[4], flu_rows[7]),
		Vector3(flu_rows[2], flu_rows[5], flu_rows[8]))
	return C * m * C.inverse()


static func extent(flu_half: Vector3) -> Vector3:
	## FLU の半寸法 → Godot の箱の全長（x←y、y←z、z←x）
	return Vector3(flu_half.y, flu_half.z, flu_half.x) * 2.0
