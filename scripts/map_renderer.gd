extends Node3D
## Рисует карту. Стены+крыша+пол для каждого здания (стиль Project Zomboid).
## Крыша скрывается только когда игрок находится внутри этого конкретного здания.

var _sim: Node3D
var _mall_exterior: Node3D
var _floor_nodes: Array[Node3D]
var _bldg_floor_ids:  PackedInt32Array
var _bldg_wall_mats:  Array   # Array[StandardMaterial3D]
var _bldg_roof_mats:  Array   # Array[StandardMaterial3D]
var _bldg_rects:      Array   # Array[Rect2]
var _evac_meshes: Array[MeshInstance3D] = []
var _horde_marker: MeshInstance3D = null
var _horde_mat:    StandardMaterial3D = null

const FADE_DIST   := 16.0  # дистанция начала затухания (метры)
const ALPHA_NEAR  := 0.12  # прозрачность у стены/крыши
const FADE_SPEED  := 9.0   # скорость перехода


func _ready() -> void:
	_sim = get_parent()
	MapGen.generate()
	_render_outdoor_buildings()
	_mall_exterior = Node3D.new()
	add_child(_mall_exterior)
	_render_mall_exterior()
	_floor_nodes.resize(Tuning.MALL_FLOORS)
	for fl in Tuning.MALL_FLOORS:
		var fn := Node3D.new()
		add_child(fn)
		_floor_nodes[fl] = fn
	_render_mall_floors()
	_render_transition_markers()
	_horde_marker = _make_horde_marker()
	_horde_marker.visible = false


func _process(delta: float) -> void:
	if _sim == null:
		return
	var pfl: int     = _sim.p_floor
	var p:   Vector2 = _sim.p_pos

	_mall_exterior.visible = (pfl == 0)
	for fl in Tuning.MALL_FLOORS:
		_floor_nodes[fl].visible = (pfl == fl + 1)

	# Затухание стен и крыш по близости к игроку
	for i in _bldg_wall_mats.size():
		var fid:  int   = _bldg_floor_ids[i]
		var rect: Rect2 = _bldg_rects[i]
		var dist: float = _dist_to_rect(p, rect)
		var inside := (pfl == fid)

		var wall_target: float
		var roof_target: float
		if inside:
			wall_target = 0.12
			roof_target = 0.0
		elif dist < FADE_DIST:
			var t := dist / FADE_DIST
			wall_target = lerpf(ALPHA_NEAR, 1.0, t)
			roof_target = lerpf(ALPHA_NEAR, 1.0, t)
		else:
			wall_target = 1.0
			roof_target = 1.0

		_apply_alpha(_bldg_wall_mats[i], wall_target, delta)
		_apply_alpha(_bldg_roof_mats[i], roof_target, delta)

	# Маркер орды
	if _sim.horde_target_life > 0.0 and pfl == 0:
		_horde_marker.visible  = true
		_horde_marker.position = Vector3(_sim.horde_target.x, 0.15, _sim.horde_target.y)
		var frac: float = _sim.horde_target_life / Tuning.HORDE_CMD_DURATION
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		if _horde_mat:
			_horde_mat.albedo_color.a             = frac * (0.4 + 0.3 * pulse)
			_horde_mat.emission_energy_multiplier = 1.5 + 2.0 * pulse
	else:
		_horde_marker.visible = false

	# Точки эвакуации
	var active_evac: Array = _sim.evac_points
	for mi_idx in _evac_meshes.size():
		_evac_meshes[mi_idx].visible = false
	for ep_idx in active_evac.size():
		if ep_idx >= _evac_meshes.size():
			_evac_meshes.append(_make_evac_mesh())
		var mi: MeshInstance3D = _evac_meshes[ep_idx]
		var ep: Dictionary     = active_evac[ep_idx]
		mi.visible  = (pfl == 0)
		mi.position = Vector3(ep["pos"].x, 0.15, ep["pos"].y)
		var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.003)
		var mat := mi.get_surface_override_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.1, 1.0, 0.3, pulse)
			mat.emission     = Color(0.0, 0.8, 0.2) * pulse


# ---------------------------------------------------------------- обычные здания
func _render_outdoor_buildings() -> void:
	for entry in MapGen.building_data:
		if entry["is_mall"]:
			continue
		_render_building(entry)


func _render_building(entry: Dictionary) -> void:
	var r:     Rect2 = entry["rect"]
	var h:     float = entry["height"]
	var color: Color = entry["color"]
	var fid:   int   = entry["floor_id"]
	var wt := Tuning.BUILDING_WALL_T
	var ew := Tuning.BUILDING_DOOR_W * 0.5
	var door_x := r.position.x + r.size.x * 0.5

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = color
	wall_mat.roughness    = 0.85

	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = color.darkened(0.3)
	roof_mat.roughness    = 0.9

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.18, 0.17, 0.16)
	floor_mat.roughness    = 0.95

	# --- Стены ---
	# Север
	_add_box(Vector3(r.position.x + r.size.x * 0.5, h * 0.5, r.position.y + wt * 0.5),
		Vector3(r.size.x, h, wt), wall_mat)
	# Восток
	_add_box(Vector3(r.end.x - wt * 0.5, h * 0.5, r.position.y + r.size.y * 0.5),
		Vector3(wt, h, r.size.y), wall_mat)
	# Запад
	_add_box(Vector3(r.position.x + wt * 0.5, h * 0.5, r.position.y + r.size.y * 0.5),
		Vector3(wt, h, r.size.y), wall_mat)
	# Юг-запад (до двери)
	var sw_w := door_x - ew - r.position.x
	if sw_w > 0.01:
		_add_box(Vector3(r.position.x + sw_w * 0.5, h * 0.5, r.end.y - wt * 0.5),
			Vector3(sw_w, h, wt), wall_mat)
	# Юг-восток (после двери)
	var se_x := door_x + ew
	var se_w := r.end.x - se_x
	if se_w > 0.01:
		_add_box(Vector3(se_x + se_w * 0.5, h * 0.5, r.end.y - wt * 0.5),
			Vector3(se_w, h, wt), wall_mat)

	# --- Пол интерьера ---
	var intr: Rect2 = entry["interior_rect"]
	_add_box(Vector3(intr.position.x + intr.size.x * 0.5, 0.1, intr.position.y + intr.size.y * 0.5),
		Vector3(intr.size.x, 0.2, intr.size.y), floor_mat)

	# --- Крыша (скрывается когда внутри) ---
	var roof_mi  := MeshInstance3D.new()
	var roof_box := BoxMesh.new()
	roof_box.size     = Vector3(r.size.x, 0.18, r.size.y)
	roof_box.material = roof_mat
	roof_mi.mesh      = roof_box
	roof_mi.position  = Vector3(r.position.x + r.size.x * 0.5, h + 0.09, r.position.y + r.size.y * 0.5)
	add_child(roof_mi)
	# (roof visibility handled via alpha fading)
	_bldg_floor_ids.append(fid)

	# --- Регистрируем материалы и прямоугольник для затухания ---
	_bldg_wall_mats.append(wall_mat)
	_bldg_roof_mats.append(roof_mat)
	_bldg_rects.append(r)


func _apply_alpha(mat: StandardMaterial3D, target: float, delta: float) -> void:
	var new_a := lerpf(mat.albedo_color.a, target, 1.0 - exp(-FADE_SPEED * delta))
	if new_a < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color.a = new_a


func _dist_to_rect(p: Vector2, r: Rect2) -> float:
	var cx := clampf(p.x, r.position.x, r.end.x)
	var cy := clampf(p.y, r.position.y, r.end.y)
	return p.distance_to(Vector2(cx, cy))


func _add_box(pos3: Vector3, size3: Vector3, mat: StandardMaterial3D) -> void:
	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size     = size3
	box.material = mat
	mi.mesh      = box
	mi.position  = pos3
	add_child(mi)


# ---------------------------------------------------------------- ТЦ снаружи
func _render_mall_exterior() -> void:
	var total_h := Tuning.MALL_FLOORS * Tuning.FLOOR_HEIGHT
	var r       := MapGen.mall_rect

	var mat := StandardMaterial3D.new()
	mat.albedo_color      = Color(0.50, 0.72, 0.90, 0.55)
	mat.transparency      = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness         = 0.25
	mat.metallic          = 0.15
	mat.metallic_specular = 0.9

	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size     = Vector3(r.size.x, total_h, r.size.y)
	box.material = mat
	mi.mesh      = box
	mi.position  = Vector3(r.position.x + r.size.x * 0.5, total_h * 0.5, r.position.y + r.size.y * 0.5)
	_mall_exterior.add_child(mi)

	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.35, 0.48, 0.62)
	roof_mat.roughness    = 0.7
	var roof_mi  := MeshInstance3D.new()
	var roof_box := BoxMesh.new()
	roof_box.size     = Vector3(r.size.x, 0.3, r.size.y)
	roof_box.material = roof_mat
	roof_mi.mesh      = roof_box
	roof_mi.position  = Vector3(r.position.x + r.size.x * 0.5, total_h + 0.15, r.position.y + r.size.y * 0.5)
	_mall_exterior.add_child(roof_mi)


# ---------------------------------------------------------------- ТЦ изнутри
func _render_mall_floors() -> void:
	var mi_rect := MapGen.mall_interior

	for fl in Tuning.MALL_FLOORS:
		var fn: Node3D = _floor_nodes[fl]
		var slab_y     := fl * Tuning.FLOOR_HEIGHT + 0.15

		var slab_mat := StandardMaterial3D.new()
		slab_mat.albedo_color = Color(0.20, 0.21, 0.23)
		slab_mat.roughness    = 0.75
		var slab_mi  := MeshInstance3D.new()
		var slab_box := BoxMesh.new()
		slab_box.size     = Vector3(mi_rect.size.x, 0.25, mi_rect.size.y)
		slab_box.material = slab_mat
		slab_mi.mesh      = slab_box
		slab_mi.position  = Vector3(mi_rect.position.x + mi_rect.size.x * 0.5, slab_y,
				mi_rect.position.y + mi_rect.size.y * 0.5)
		fn.add_child(slab_mi)

		# Прозрачные боковые стены
		var wall_h   := Tuning.FLOOR_HEIGHT - 0.25
		var wall_y   := slab_y + 0.125 + wall_h * 0.5
		var wt       := 0.4
		var rx       := mi_rect.position.x
		var ry       := mi_rect.position.y
		var rw       := mi_rect.size.x
		var rd       := mi_rect.size.y
		var wall_mat := StandardMaterial3D.new()
		wall_mat.albedo_color = Color(0.58, 0.75, 0.92, 0.35)
		wall_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wall_mat.roughness    = 0.2

		for w in [
			[Vector3(rx + rw * 0.5, wall_y, ry),            Vector3(rw, wall_h, wt)],
			[Vector3(rx + rw * 0.5, wall_y, ry + rd),       Vector3(rw, wall_h, wt)],
			[Vector3(rx,            wall_y, ry + rd * 0.5), Vector3(wt, wall_h, rd)],
			[Vector3(rx + rw,       wall_y, ry + rd * 0.5), Vector3(wt, wall_h, rd)],
		]:
			var wmi  := MeshInstance3D.new()
			var wbox := BoxMesh.new()
			wbox.size     = w[1]
			wbox.material = wall_mat
			wmi.mesh      = wbox
			wmi.position  = w[0]
			fn.add_child(wmi)

		# Магазины
		var hue      := fmod(float(fl) * 0.19 + 0.07, 1.0)
		var shop_mat := StandardMaterial3D.new()
		shop_mat.albedo_color = Color.from_hsv(hue, 0.5, 0.58)
		shop_mat.roughness    = 0.8

		if fl < MapGen.mall_obstacles.size():
			for shop: Rect2 in MapGen.mall_obstacles[fl]:
				var sh  := 2.0
				var smi := MeshInstance3D.new()
				var sbx := BoxMesh.new()
				sbx.size      = Vector3(shop.size.x, sh, shop.size.y)
				sbx.material  = shop_mat
				smi.mesh      = sbx
				smi.position  = Vector3(shop.position.x + shop.size.x * 0.5, slab_y + 0.125 + sh * 0.5,
						shop.position.y + shop.size.y * 0.5)
				fn.add_child(smi)


# ---------------------------------------------------------------- маркеры переходов
func _render_transition_markers() -> void:
	var ew := Tuning.MALL_ENTRANCE_W * 0.5
	_add_marker(self, Rect2(-ew, -14.5, ew * 2, 3.0), 0.12, Color(0.10, 0.85, 0.35))

	for fl in range(1, Tuning.MALL_FLOORS):
		var fn: Node3D = _floor_nodes[fl - 1]
		var base_y := fl * Tuning.FLOOR_HEIGHT
		_add_marker(fn, Rect2(7.0, 7.0, 4.0, 4.0),   base_y + 0.12, Color(0.20, 0.60, 1.00))
		_add_marker(fn, Rect2(-11.0, 7.0, 4.0, 4.0), base_y + 0.12, Color(1.00, 0.55, 0.15))

	if _floor_nodes.size() > 0:
		_add_marker(_floor_nodes[0], Rect2(-ew, -11.5, ew * 2, 1.5),
			Tuning.FLOOR_HEIGHT * 0.0 + 0.12, Color(0.10, 0.85, 0.35))

	# Дверные маркеры на улице
	for entry in MapGen.building_data:
		if not entry["has_interior"]:
			continue
		var dp: Vector2 = entry["door_pos"]
		var bew := Tuning.BUILDING_DOOR_W * 0.5
		_add_marker(self, Rect2(dp.x - bew, dp.y - 0.3, bew * 2, 0.5), 0.05,
			Color(0.15, 0.90, 0.40))


func _make_evac_mesh() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color            = Color(0.1, 1.0, 0.3, 0.8)
	mat.transparency            = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled        = true
	mat.emission                = Color(0.0, 0.8, 0.2)
	mat.emission_energy_multiplier = 2.0
	mat.roughness               = 0.3
	var box := BoxMesh.new()
	box.size = Vector3(6.0, 0.25, 6.0)
	var mi  := MeshInstance3D.new()
	mi.mesh = box
	mi.set_surface_override_material(0, mat)
	add_child(mi)
	return mi


func _make_horde_marker() -> MeshInstance3D:
	_horde_mat = StandardMaterial3D.new()
	_horde_mat.albedo_color             = Color(0.8, 0.15, 1.0, 0.7)
	_horde_mat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA
	_horde_mat.emission_enabled         = true
	_horde_mat.emission                 = Color(0.6, 0.0, 1.0)
	_horde_mat.emission_energy_multiplier = 3.0
	_horde_mat.roughness                = 0.2
	var cyl := CylinderMesh.new()
	cyl.top_radius    = 2.2
	cyl.bottom_radius = 2.2
	cyl.height        = 0.12
	cyl.material      = _horde_mat
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	add_child(mi)
	return mi


func _add_marker(parent: Node3D, r: Rect2, y: float, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color     = color
	mat.emission_enabled = true
	mat.emission         = color * 0.6
	mat.roughness        = 0.3
	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size     = Vector3(r.size.x, 0.1, r.size.y)
	box.material = mat
	mi.mesh      = box
	mi.position  = Vector3(r.position.x + r.size.x * 0.5, y, r.position.y + r.size.y * 0.5)
	parent.add_child(mi)
