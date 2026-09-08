extends Node3D
## Рисует карту. Стены+крыша+пол для каждого здания (стиль Project Zomboid).
## Крыша скрывается только когда игрок находится внутри этого конкретного здания.

const STREET_RENDERER = preload("res://scripts/street_renderer.gd")
const CITY_BUILDINGS = preload("res://scripts/city_building_catalog.gd")
const HOUSE_MODEL = preload("res://assets/models/buildings/building_house_a.glb")
const MALL_SHELL = preload("res://assets/models/mall/mall_shell.glb")
const MALL_FLOOR = preload("res://assets/models/mall/mall_floor.glb")
const MALL_KIOSKS = [preload("res://assets/models/mall/mall_kiosk_food.glb"), preload("res://assets/models/mall/mall_kiosk_clothes.glb"), preload("res://assets/models/mall/mall_kiosk_electronics.glb")]
const MALL_SHOPS = [preload("res://assets/models/mall/mall_shop_food.glb"), preload("res://assets/models/mall/mall_shop_clothes.glb"), preload("res://assets/models/mall/mall_shop_electronics.glb")]
const MALL_ESCALATOR_UP = preload("res://assets/models/mall/mall_escalator_up.glb")
const MALL_ESCALATOR_DOWN = preload("res://assets/models/mall/mall_escalator_down.glb")
var _outdoor_nodes: Array[Node3D] = []
var _ground: MeshInstance3D
var _sim: Node3D
var _mall_exterior: Node3D
var _floor_nodes: Array[Node3D]
var _bldg_floor_ids:  PackedInt32Array
var _bldg_wall_mats:  Array   # Array[StandardMaterial3D]
var _bldg_roof_mats:  Array   # Array[StandardMaterial3D]
var _bldg_rects:      Array   # Array[Rect2]
var _horde_marker: MeshInstance3D = null
var _horde_mat:    StandardMaterial3D = null
var _mall_door_nodes: Array = []   # [floor] -> Array[MeshInstance3D] по di

const FADE_DIST   := 16.0  # дистанция начала затухания (метры)
const ALPHA_NEAR  := 0.12  # прозрачность у стены/крыши
const FADE_SPEED  := 9.0   # скорость перехода


func _ready() -> void:
	_sim = get_parent()
	_ground = _sim.get_node("Ground")
	MapGen.generate()
	_ground.position.y = -.05
	var ground_mat := _ground.get_surface_override_material(0).duplicate() as StandardMaterial3D
	ground_mat.albedo_color = Color("4b5648")
	_ground.set_surface_override_material(0, ground_mat)
	_render_outdoor_buildings()
	var streets := STREET_RENDERER.new()
	add_child(streets)
	streets.build(MapGen.street_data)
	for child in get_children():
		if child is Node3D: _outdoor_nodes.append(child)
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

	_ground.visible = pfl == 0 or pfl > Tuning.MALL_FLOORS
	for node in _outdoor_nodes:
		node.visible = pfl == 0 or pfl > Tuning.MALL_FLOORS
	_mall_exterior.visible = (pfl == 0)
	for fl in Tuning.MALL_FLOORS:
		_floor_nodes[fl].visible = (pfl == fl + 1)
		# Створки видны, когда дверь закрыта.
		if fl < _mall_door_nodes.size():
			var dnodes: Array = _mall_door_nodes[fl]
			for di in dnodes.size():
				(dnodes[di] as MeshInstance3D).visible = not MapGen.is_door_open(fl + 1, di)

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
	if _sim.horde_target_life > 0.0 and _sim.horde_cmd != _sim.HC_NONE:
		_horde_marker.visible  = true
		_horde_marker.position = Vector3(_sim.horde_target.x, 0.15, _sim.horde_target.y)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		if _horde_mat:
			match _sim.horde_cmd:
				_sim.HC_FOLLOW:
					_horde_mat.albedo_color = Color(0.3, 0.8, 1.0, 0.55 + 0.2 * pulse)   # голубой
					_horde_mat.emission    = Color(0.1, 0.5, 1.0)
				_sim.HC_HOLD:
					_horde_mat.albedo_color = Color(0.2, 1.0, 0.5, 0.6)                   # зелёный, статичный
					_horde_mat.emission    = Color(0.0, 0.8, 0.3)
				_sim.HC_ATTACK:
					_horde_mat.albedo_color = Color(1.0, 0.2, 0.1, 0.5 + 0.3 * pulse)    # красный
					_horde_mat.emission    = Color(1.0, 0.1, 0.0)
				_:  # HC_MOVE
					_horde_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.4 + 0.3 * pulse)   # жёлтый
					_horde_mat.emission    = Color(1.0, 0.6, 0.0)
			_horde_mat.emission_energy_multiplier = 1.5 + 2.0 * pulse
	else:
		_horde_marker.visible = false

# ---------------------------------------------------------------- обычные здания
func _render_outdoor_buildings() -> void:
	for entry in MapGen.building_data:
		if entry["is_mall"]:
			continue
		if is_equal_approx(float(entry["height"]), Tuning.FLOOR_HEIGHT):
			_render_house(entry)
		elif not _render_city_building(entry):
			_render_building(entry)


func _render_city_building(entry: Dictionary) -> bool:
	var fid: int = entry["floor_id"]
	if not CITY_BUILDINGS.ENTRIES.has(fid):
		return false
	var asset: Dictionary = CITY_BUILDINGS.ENTRIES[fid]
	var r: Rect2 = entry["rect"]
	# A changed map keeps its correct geometry until its exports are rebuilt.
	if not asset["size"].is_equal_approx(Vector3(r.size.x, entry["height"], r.size.y)):
		return false
	var model := (asset["model"] as PackedScene).instantiate() as Node3D
	model.name = "CityBuilding%d" % fid
	add_child(model)
	model.position = Vector3(r.get_center().x, 0, r.get_center().y)
	var walls := model.find_child("Walls", true, false) as MeshInstance3D
	var roof  := model.find_child("Roof",  true, false) as MeshInstance3D
	if walls == null or roof == null:
		return false
	var wall_mat := walls.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	var roof_mat := roof.mesh.surface_get_material(0).duplicate()  as StandardMaterial3D
	if wall_mat == null or roof_mat == null:
		return false
	for s in walls.mesh.get_surface_count():
		walls.set_surface_override_material(s, wall_mat)
	for s in roof.mesh.get_surface_count():
		roof.set_surface_override_material(s, roof_mat)
	_bldg_floor_ids.append(fid)
	_bldg_wall_mats.append(wall_mat)
	_bldg_roof_mats.append(roof_mat)
	_bldg_rects.append(r)
	return true


func _render_house(entry: Dictionary) -> void:
	var r: Rect2 = entry["rect"]
	var house := HOUSE_MODEL.instantiate() as Node3D
	house.name = "House%d" % int(entry["floor_id"])
	add_child(house)
	house.position = Vector3(r.get_center().x, 0, r.get_center().y)
	house.scale = Vector3(r.size.x / 9.0, 1.0, r.size.y / 7.5)
	var walls := house.find_child("Walls", true, false) as MeshInstance3D
	var roof  := house.find_child("Roof",  true, false) as MeshInstance3D
	var wall_mat := walls.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	var roof_mat := roof.mesh.surface_get_material(0).duplicate()  as StandardMaterial3D
	for s in walls.mesh.get_surface_count():
		walls.set_surface_override_material(s, wall_mat)
	for s in roof.mesh.get_surface_count():
		roof.set_surface_override_material(s, roof_mat)
	_bldg_floor_ids.append(entry["floor_id"])
	_bldg_wall_mats.append(wall_mat)
	_bldg_roof_mats.append(roof_mat)
	_bldg_rects.append(r)


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
	var shell := MALL_SHELL.instantiate() as Node3D
	shell.name = "MallShell"
	_mall_exterior.add_child(shell)


func _render_mall_floors() -> void:
	for fl in Tuning.MALL_FLOORS:
		var fn: Node3D = _floor_nodes[fl]
		fn.name = "MallFloor%d" % (fl + 1)
		fn.position.y = MapGen.floor_y3d(fl + 1)
		var floor_model := MALL_FLOOR.instantiate() as Node3D
		fn.add_child(floor_model)
		# Процедурные стены комнат (прототип, серые боксы).
		_render_mall_walls(fn, fl)
		for data: Dictionary in MapGen.mall_kiosks[fl]:
			var kiosk := (MALL_KIOSKS[data["kind"]] as PackedScene).instantiate() as Node3D
			fn.add_child(kiosk)
			var center: Vector2 = data["rect"].get_center()
			kiosk.position = Vector3(center.x, 0, center.y)
		for data: Dictionary in MapGen.mall_shops[fl]:
			var shop := (MALL_SHOPS[data["kind"]] as PackedScene).instantiate() as Node3D
			fn.add_child(shop)
			shop.position = Vector3(data["center"].x, 0, data["center"].y)
			shop.rotation.y = data["angle"]
			var title: String = ["ПРОДУКТЫ", "ОДЕЖДА", "ТЕХНИКА"][data["kind"]]
			_mall_label(shop, title, Vector3(0, 2.8, -2.6), Color.WHITE, 0.007)
		_mall_label(fn, "ЭТАЖ %d" % (fl + 1), Vector3(0, 0.12, -15), Color("2b5559"), 0.025)
		if fl == 0:
			_mall_label(fn, "ВЫХОД ↓", Vector3(0, 0.15, MapGen.mall_exit.end.y + 1.0), Color("235741"), 0.016)


func _render_mall_walls(parent: Node3D, fl: int) -> void:
	if fl >= MapGen.mall_obstacles.size():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.63, 0.66)
	mat.roughness = 0.9
	var wall_h := 2.6
	for w: Rect2 in MapGen.mall_obstacles[fl]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(w.size.x, wall_h, w.size.y)
		mi.mesh = box
		mi.material_override = mat
		var c := w.get_center()
		mi.position = Vector3(c.x, wall_h * 0.5, c.y)
		parent.add_child(mi)

	# Створки дверей: показываются, когда дверь закрыта.
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.52, 0.34, 0.18)
	door_mat.roughness = 0.7
	var door_h := 2.3
	var nodes: Array = []
	for door: Dictionary in MapGen.mall_doors:
		var plug: Rect2 = door["plug"]
		var leaf := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(maxf(plug.size.x, 0.2), door_h, maxf(plug.size.y, 0.2))
		leaf.mesh = box
		leaf.material_override = door_mat
		var c := plug.get_center()
		leaf.position = Vector3(c.x, door_h * 0.5, c.y)
		leaf.visible = false
		parent.add_child(leaf)
		nodes.append(leaf)
	_mall_door_nodes.append(nodes)


func _mall_label(parent: Node3D, title: String, position3: Vector3, color: Color, pixel_size: float) -> void:
	var label := Label3D.new()
	label.text = title
	label.position = position3
	label.font_size = 48
	label.pixel_size = pixel_size
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	parent.add_child(label)


func _render_transition_markers() -> void:
	var exterior := Node3D.new()
	add_child(exterior)
	_outdoor_nodes.append(exterior)
	_add_marker(exterior, MapGen.mall_entry, 0.02, Color(0.10, 0.70, 0.35))
	for fl in range(1, Tuning.MALL_FLOORS):
		var up := MALL_ESCALATOR_UP.instantiate() as Node3D
		_floor_nodes[fl - 1].add_child(up)
		up.position = Vector3(MapGen.mall_up.get_center().x, 0, MapGen.mall_up.get_center().y)
		_mall_label(up, "↑ %d ЭТАЖ" % (fl + 1), Vector3(0, 1.65, 0), Color("8fc9ef"), 0.011)
		var down := MALL_ESCALATOR_DOWN.instantiate() as Node3D
		_floor_nodes[fl].add_child(down)
		down.position = Vector3(MapGen.mall_down.get_center().x, 0, MapGen.mall_down.get_center().y)
		_mall_label(down, "↓ %d ЭТАЖ" % fl, Vector3(0, 1.65, 0), Color("edbb84"), 0.011)
	_add_marker(_floor_nodes[0], MapGen.mall_exit, 0.015, Color(0.10, 0.70, 0.35))
	for entry in MapGen.building_data:
		if not entry["has_interior"]: continue
		var dp: Vector2 = entry["door_pos"]
		var bew := Tuning.BUILDING_DOOR_W * 0.5
		_add_marker(exterior, Rect2(dp.x - bew, dp.y - 0.3, bew * 2, 0.5), 0.05, Color(0.15, 0.90, 0.40))


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
