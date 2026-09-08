extends Node
## Синглтон-карта (AutoLoad "MapGen").
## floor=0 — улица; floor=1..MALL_FLOORS — этажи ТЦ; floor>MALL_FLOORS — обычные здания.

# --- Уличные препятствия (floor 0) ---
var buildings: Array[Rect2] = []
var street_data: Dictionary = {}
const STREET_LAYOUT = preload("res://scripts/street_layout.gd")

# --- ТЦ ---
var mall_rect := Rect2(Vector2.ONE * (-Tuning.MALL_SIZE * 0.5), Vector2.ONE * Tuning.MALL_SIZE)
var mall_interior := mall_rect.grow(-Tuning.MALL_WALL_T)
var mall_kiosks: Array = []
var mall_shops: Array = []
var mall_up := Rect2(3, Tuning.MALL_SIZE * 0.5 - 8, 4, 4)
var mall_down := Rect2(-7, Tuning.MALL_SIZE * 0.5 - 8, 4, 4)
var mall_entry := Rect2(-Tuning.MALL_ENTRANCE_W / 2, -Tuning.MALL_SIZE / 2 - 1.5, Tuning.MALL_ENTRANCE_W, 2.0)
var mall_exit := Rect2(-Tuning.MALL_ENTRANCE_W / 2, -Tuning.MALL_SIZE / 2 + Tuning.MALL_WALL_T, Tuning.MALL_ENTRANCE_W, 1.5)
var mall_obstacles: Array = []   # Array[Array[Rect2]], индекс = floor-1

# --- Переходы между этажами ---
# Каждый: {rect, from_floor, to_floor, dest}
var transitions: Array = []

# --- Данные интерьеров по floor_id ---
var interior_by_floor: Dictionary = {}   # floor_id -> Rect2

# --- Точки спавна ---
var spawn_points:    PackedVector2Array
var mall_spawns:     Array = []   # Array[PackedVector2Array], индекс = floor-1
var building_spawns: Array = []   # Array[Dictionary] {floor_id, points: PackedVector2Array}

# --- Данные для рендера ---
# {rect, height, color, is_mall, has_interior, floor_id, interior_rect, door_pos}
var building_data: Array = []

var _generated     := false
var _building_count := 0

var _mall_zone := mall_rect.grow(Tuning.MALL_CLEARANCE)


func generate() -> void:
	if _generated:
		return
	_generated = true
	_place_mall()
	_place_outdoor_buildings()
	_build_transitions()
	street_data = STREET_LAYOUT.new().build(self)
	_build_spawn_points()
	_build_mall_spawns()
	_build_building_spawns()


# ----------------------------------------------------------------- ТЦ
func _place_mall() -> void:
	# Full outdoor footprint prevents street agents spawning inside the shell.
	buildings.append(mall_rect)
	var rng := RandomNumberGenerator.new()
	rng.seed = Tuning.MAP_SEED + 9999
	mall_obstacles.resize(Tuning.MALL_FLOORS)
	mall_kiosks.resize(Tuning.MALL_FLOORS)
	mall_shops.resize(Tuning.MALL_FLOORS)
	for fl in Tuning.MALL_FLOORS:
		var obs: Array[Rect2] = []
		var kiosks: Array = []
		var shops: Array = []
		# Central cross and rear gallery remain open between all transitions.
		for x in [-10.0, 10.0]:
			for z in [-13.0, -6.0, 6.0, 13.0]:
				var rect := Rect2(Vector2(x, z) - Vector2(1.75, 1.375), Vector2(3.5, 2.75))
				obs.append(rect)
				kiosks.append({"rect": rect, "kind": rng.randi_range(0, 2)})
		for side in [-1.0, 1.0]:
			for z in [-15.0, -5.0, 5.0, 15.0]:
				var center := Vector2(side * (Tuning.MALL_SIZE * 0.5 - 4.0), z)
				var angle: float = -side * PI / 2.0
				shops.append({"center": center, "angle": angle, "kind": (fl + shops.size()) % 3})
				for local_rect in [Rect2(-4, -3, 8, 0.6), Rect2(-4, -2.4, 0.4, 5.4), Rect2(3.6, -2.4, 0.4, 5.4), Rect2(-3.2, 1.5, 2.5, 0.7)]:
					obs.append(_rotated_shop_rect(local_rect, center, angle))
		mall_obstacles[fl] = obs
		mall_kiosks[fl] = kiosks
		mall_shops[fl] = shops

	building_data.append({
		"rect":         mall_rect,
		"height":       Tuning.MALL_FLOORS * Tuning.FLOOR_HEIGHT,
		"color":        Color(0.45, 0.68, 0.85),
		"is_mall":      true,
		"has_interior": false,
		"floor_id":     0,
		"interior_rect": Rect2(),
		"door_pos":     Vector2.ZERO
	})


# ----------------------------------------------------------------- Уличные здания
func _rotated_shop_rect(rect: Rect2, center: Vector2, angle: float) -> Rect2:
	var a := rect.position.rotated(-angle) + center
	var b := rect.end.rotated(-angle) + center
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(absf(a.x-b.x), absf(a.y-b.y)))


func _place_outdoor_buildings() -> void:
	var bs  := Tuning.MAP_BLOCK_SIZE
	var sw  := Tuning.MAP_STREET_W
	var mg  := Tuning.MAP_SIDEWALK
	var ox  := -Tuning.WORLD_SIZE * 0.5 + sw
	var oy  := -Tuning.WORLD_SIZE * 0.5 + sw
	var wt  := Tuning.BUILDING_WALL_T

	var rng := RandomNumberGenerator.new()
	rng.seed = Tuning.MAP_SEED

	for row in Tuning.MAP_BLOCK_ROWS:
		for col in Tuning.MAP_BLOCK_COLS:
			var bx    := ox + col * (bs + sw)
			var by    := oy + row * (bs + sw)
			var block := Rect2(bx, by, bs, bs)

			if block.intersects(_mall_zone):
				continue
			if rng.randi_range(0, Tuning.MAP_PLAZA_FREQ - 1) == 0:
				continue

			var t := rng.randi_range(0, 5)
			var color: Color
			var floors: int
			var bw: float
			var bd: float

			match t:
				0, 1:
					color  = Color(0.78, 0.62, 0.46)
					floors = 1
					bw     = rng.randf_range(7, 11)
					bd     = rng.randf_range(6, 9)
				2, 3:
					color  = Color(0.52, 0.54, 0.58)
					floors = rng.randi_range(3, 6)
					bw     = rng.randf_range(10, 15)
					bd     = rng.randf_range(9, 13)
				4:
					color  = Color(0.40, 0.42, 0.37)
					floors = 2
					bw     = rng.randf_range(13, 17)
					bd     = rng.randf_range(11, 15)
				_:
					color  = Color(0.40, 0.55, 0.68)
					floors = rng.randi_range(4, 7)
					bw     = rng.randf_range(10, 14)
					bd     = rng.randf_range(10, 14)

			bw = minf(bw, bs - 2.0 * mg)
			bd = minf(bd, bs - 2.0 * mg)

			var off_x := rng.randf_range(-1.0, 1.0)
			var off_y := rng.randf_range(-1.0, 1.0)
			var rx := clampf(bx + (bs - bw) * 0.5 + off_x, bx + mg, bx + bs - bw - mg)
			var ry := clampf(by + (bs - bd) * 0.5 + off_y, by + mg, by + bs - bd - mg)
			var r  := Rect2(rx, ry, bw, bd)

			# Полный прямоугольник — для floor-0 коллизии
			buildings.append(r)

			# Уникальный floor_id для интерьера
			var fid      := Tuning.MALL_FLOORS + 1 + _building_count
			_building_count += 1

			var interior_rect := Rect2(
				rx + wt, ry + wt,
				bw - 2.0 * wt, bd - 2.0 * wt
			)
			interior_by_floor[fid] = interior_rect

			var door_pos := Vector2(rx + bw * 0.5, ry + bd)

			building_data.append({
				"rect":         r,
				"height":       floors * Tuning.FLOOR_HEIGHT,
				"color":        color,
				"is_mall":      false,
				"has_interior": true,
				"floor_id":     fid,
				"interior_rect": interior_rect,
				"door_pos":     door_pos
			})


# ----------------------------------------------------------------- Переходы
func _build_transitions() -> void:
	transitions.append({"rect": mall_entry, "from_floor": 0, "to_floor": 1,
		"dest": Vector2(0, mall_interior.position.y + 3.0)})
	transitions.append({"rect": mall_exit, "from_floor": 1, "to_floor": 0,
		"dest": Vector2(0, mall_rect.position.y - 2.5)})
	for fl in range(1, Tuning.MALL_FLOORS):
		transitions.append({"rect": mall_up, "from_floor": fl, "to_floor": fl + 1,
			"dest": Vector2(mall_down.get_center().x, mall_down.position.y - 1.0)})
		transitions.append({"rect": mall_down, "from_floor": fl + 1, "to_floor": fl,
			"dest": Vector2(mall_up.get_center().x, mall_up.position.y - 1.0)})

	# Обычные здания: вход/выход через южную стену
	var bew := Tuning.BUILDING_DOOR_W * 0.5
	for entry in building_data:
		if not entry["has_interior"]:
			continue
		var r:    Rect2  = entry["rect"]
		var fid:  int    = entry["floor_id"]
		var intr: Rect2  = entry["interior_rect"]
		var door_x := r.position.x + r.size.x * 0.5
		var end_y  := r.end.y

		# Вход снаружи → интерьер
		transitions.append({
			"rect":       Rect2(door_x - bew, end_y - 0.3, bew * 2, 1.0),
			"from_floor": 0, "to_floor": fid,
			"dest":       Vector2(door_x, intr.end.y - 0.6)
		})
		# Выход из интерьера → улица
		transitions.append({
			"rect":       Rect2(door_x - bew, intr.end.y - 1.0, bew * 2, 1.0),
			"from_floor": fid, "to_floor": 0,
			"dest":       Vector2(door_x, end_y + 1.0)
		})


# ----------------------------------------------------------------- Спавн
func _build_spawn_points() -> void:
	spawn_points.clear()
	var half := Tuning.WORLD_SIZE * 0.5
	var step := 2.0
	var x    := -half + step
	while x < half - step:
		var y := -half + step
		while y < half - step:
			if not is_blocked(Vector2(x, y), 0.5, 0):
				spawn_points.append(Vector2(x, y))
			y += step
		x += step


func _build_building_spawns() -> void:
	building_spawns.clear()
	var step := 1.5
	for floor_id: int in interior_by_floor:
		var r: Rect2 = interior_by_floor[floor_id]
		var pts := PackedVector2Array()
		var x := r.position.x + step
		while x < r.end.x - step * 0.5:
			var y := r.position.y + step
			while y < r.end.y - step * 0.5:
				var p := Vector2(x, y)
				if not is_blocked(p, 0.3, floor_id):
					pts.append(p)
				y += step
			x += step
		if pts.size() > 0:
			building_spawns.append({"floor_id": floor_id, "points": pts})


func _build_mall_spawns() -> void:
	mall_spawns.clear()
	for fl in Tuning.MALL_FLOORS:
		var pts  := PackedVector2Array()
		var mi   := mall_interior
		var step := 2.0
		var x    := mi.position.x + step
		while x < mi.end.x - step:
			var y := mi.position.y + step
			while y < mi.end.y - step:
				if not is_blocked(Vector2(x, y), 0.5, fl + 1):
					pts.append(Vector2(x, y))
				y += step
			x += step
		mall_spawns.append(pts)


# ----------------------------------------------------------------- Запросы
func is_blocked(p: Vector2, radius: float, floor: int) -> bool:
	if floor == 0:
		for b: Rect2 in buildings:
			if b.grow(radius).has_point(p):
				return true
		return false
	elif floor <= Tuning.MALL_FLOORS:
		if not mall_interior.grow(-radius).has_point(p):
			return true
		var fi := floor - 1
		if fi < mall_obstacles.size():
			for b: Rect2 in mall_obstacles[fi]:
				if b.grow(radius).has_point(p):
					return true
		return false
	else:
		if not interior_by_floor.has(floor):
			return true
		var r: Rect2 = interior_by_floor[floor]
		return not r.grow(-radius).has_point(p)


func push_out(p: Vector2, radius: float, floor: int) -> Vector2:
	if floor == 0:
		for b: Rect2 in buildings:
			if b.grow(radius).has_point(p):
				p = _push_rect(p, b, radius)
		return p
	elif floor <= Tuning.MALL_FLOORS:
		var fi := floor - 1
		if fi < mall_obstacles.size():
			for b: Rect2 in mall_obstacles[fi]:
				if b.grow(radius).has_point(p):
					p = _push_rect(p, b, radius)
		var mi := mall_interior
		p.x = clampf(p.x, mi.position.x + radius, mi.end.x - radius)
		p.y = clampf(p.y, mi.position.y + radius, mi.end.y - radius)
		return p
	else:
		if not interior_by_floor.has(floor):
			return p
		var r: Rect2 = interior_by_floor[floor]
		p.x = clampf(p.x, r.position.x + radius, r.end.x - radius)
		p.y = clampf(p.y, r.position.y + radius, r.end.y - radius)
		return p


func _push_rect(p: Vector2, b: Rect2, radius: float) -> Vector2:
	var cx := b.position.x + b.size.x * 0.5
	var cy := b.position.y + b.size.y * 0.5
	var hw := b.size.x * 0.5 + radius
	var hh := b.size.y * 0.5 + radius
	var dx := p.x - cx
	var dy := p.y - cy
	var px := hw - absf(dx)
	var py := hh - absf(dy)
	if px < py:
		p.x += px * (1.0 if dx >= 0.0 else -1.0)
	else:
		p.y += py * (1.0 if dy >= 0.0 else -1.0)
	return p


func check_transition(p: Vector2, floor: int) -> Dictionary:
	for t in transitions:
		if t["from_floor"] == floor and (t["rect"] as Rect2).has_point(p):
			return t
	return {}


func floor_y3d(floor_id: int) -> float:
	if floor_id == 0:
		return 0.0
	elif floor_id <= Tuning.MALL_FLOORS:
		return float(floor_id - 1) * Tuning.FLOOR_HEIGHT
	else:
		return 0.0   # обычное здание — на уровне земли
