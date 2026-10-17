class_name RoverLunarEnvironment
extends Node
## 月面の空と光（検討書 §3.5・§3.7）。
##   - 空は黒・空からの光（環境光）はほぼ 0・霧なし（大気が無い）
##   - 太陽は平行光。方位と高度で置く（南極域は高度が数度）。視直径 0.53° を影のにじみに使う
##   - 露出は固定（自動露出を使わない）
## ★ 照り返し（間接光）は Godot の軽量ビューアでは近似しない（主ビューアの Unreal で Lumen を使う）。

static func build(parent: Node, cfg: Dictionary) -> DirectionalLight3D:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = float(cfg.get("ambient_energy", 0.03))
	env.fog_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)

	var sun_cfg: Dictionary = cfg.get("sun", {})
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = float(sun_cfg.get("energy", 2.2))
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	sun.light_angular_distance = float(sun_cfg.get("angular_diameter_deg", 0.53))
	# 方位：FLU の +x（コースの前方）から左回り。高度：地平線から上
	var az := deg_to_rad(float(sun_cfg.get("azimuth_deg", 150.0)))
	var el := deg_to_rad(float(sun_cfg.get("elevation_deg", 8.0)))
	var to_sun_flu := Vector3(cos(el) * cos(az), cos(el) * sin(az), sin(el))
	var to_sun := RoverFrames.pos(to_sun_flu)
	parent.add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP if abs(to_sun.y) < 0.99 else Vector3.FORWARD)
	return sun


static func regolith_material(albedo: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(albedo, albedo, albedo * 0.97)
	m.roughness = 1.0
	m.metallic_specular = 0.0
	return m
