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

# --- Комнаты ТЦ (одинаковы на всех этажах) ---
var mall_rooms: Array = []       # Array[Dictionary] {id:int, rect:Rect2}
var mall_doors: Array = []       # Array[Dictionary] {pos:Vector2, a:int, b:int}
var _mall_adj:  Dictionary = {}  # node_id -> Array[{other:int, pos:Vector2}]

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

	_build_mall_rooms()

	# Стены комнат одинаковы на всех этажах. Киоски/магазины прототипа не рисуем.
	mall_obstacles.resize(Tuning.MALL_FLOORS)
	mall_kiosks.resize(Tuning.MALL_FLOORS)
	mall_shops.resize(Tuning.MALL_FLOORS)
	var walls := _build_mall_walls()
	for fl in Tuning.MALL_FLOORS:
		mall_obstacles[fl] = walls.duplicate()
		mall_kiosks[fl] = []
		mall_shops[fl] = []

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


# ---------------------------------------------------- Планировка ТЦ (комнаты)
## Крестовидный атриум в центре, 4 угловые комнаты, у каждой одна дверь в атриум.
## Узел 0 = атриум; узлы 1..4 = комнаты (NW, NE, SW, SE).
func _build_mall_rooms() -> void:
	mall_rooms.clear()
	mall_doors.clear()
	_mall_adj.clear()

	var he := Tuning.MALL_SIZE * 0.5 - Tuning.MALL_WALL_T - 0.5   # внешняя граница комнат
	var ab := Tuning.MALL_ATRIUM_HALF                            # полуширина атриума

	# id: 1=NW, 2=NE, 3=SW, 4=SE. Дверь на вертикальном ребре (x=±ab), в атриум.
	var defs := [
		{"id": 1, "rect": Rect2(-he,  ab, he - ab, he - ab), "door_x": -ab},
		{"id": 2, "rect": Rect2( ab,  ab, he - ab, he - ab), "door_x":  ab},
		{"id": 3, "rect": Rect2(-he, -he, he - ab, he - ab), "door_x": -ab},
		{"id": 4, "rect": Rect2( ab, -he, he - ab, he - ab), "door_x":  ab},
	]
	var wt := Tuning.MALL_ROOM_WALL_T
	var dh := Tuning.MALL_DOOR_W * 0.5
	for d: Dictionary in defs:
		var r: Rect2 = d["rect"]
		mall_rooms.append({"id": d["id"], "rect": r})
		var door_z := r.position.y + r.size.y * 0.5
		var door := Vector2(d["door_x"], door_z)
		# «Заглушка» — прямоугольник, перекрывающий проём, когда дверь закрыта.
		var plug := Rect2(d["door_x"] - wt * 0.5, door_z - dh, wt, dh * 2.0)
		mall_doors.append({"pos": door, "a": 0, "b": d["id"], "di": mall_doors.size(), "plug": plug})

	# Граф смежности из дверей (неориентированный), с индексом двери di.
	for node in [0, 1, 2, 3, 4]:
		_mall_adj[node] = []
	for door: Dictionary in mall_doors:
		_mall_adj[door["a"]].append({"other": door["b"], "pos": door["pos"], "di": door["di"]})
		_mall_adj[door["b"]].append({"other": door["a"], "pos": door["pos"], "di": door["di"]})

	reset_doors()


## Стены комнат: два внутренних ребра (к атриуму) у каждой, дверной вырез на
## вертикальном ребре. Внешние стороны закрывает оболочка ТЦ + clamp push_out.
func _build_mall_walls() -> Array[Rect2]:
	var walls: Array[Rect2] = []
	var ab := Tuning.MALL_ATRIUM_HALF
	var wt := Tuning.MALL_ROOM_WALL_T
	var dh := Tuning.MALL_DOOR_W * 0.5
	for room: Dictionary in mall_rooms:
		var r: Rect2 = room["rect"]
		var door_x: float = -ab if r.position.x < 0.0 else ab
		var door_z := r.position.y + r.size.y * 0.5
		# Вертикальное ребро к атриуму (x=door_x) с проёмом по z.
		walls.append_array(_wall_seg(true, door_x, r.position.y, r.end.y, wt, door_z, dh))
		# Горизонтальное ребро к атриуму (сплошное).
		var edge_z: float = r.position.y if r.position.y >= 0.0 else r.end.y
		walls.append_array(_wall_seg(false, edge_z, r.position.x, r.end.x, wt, NAN, 0.0))
		# Внешние рёбра (видимые стены изнутри; коллизия дублирует оболочку).
		var outer_x: float = r.end.x if door_x > 0.0 else r.position.x
		walls.append_array(_wall_seg(true, outer_x, r.position.y, r.end.y, wt, NAN, 0.0))
		var outer_z: float = r.end.y if r.position.y >= 0.0 else r.position.y
		walls.append_array(_wall_seg(false, outer_z, r.position.x, r.end.x, wt, NAN, 0.0))

	# Не перекрывать эскалаторы: убираем стены, пересекающие их площадки.
	var clear: Array[Rect2] = [mall_up.grow(0.9), mall_down.grow(0.9)]
	var filtered: Array[Rect2] = []
	for w: Rect2 in walls:
		var blocked := false
		for c: Rect2 in clear:
			if w.intersects(c):
				blocked = true
				break
		if not blocked:
			filtered.append(w)
	return filtered


## Сегмент стены вдоль оси. vertical=true → стена по z при фиксированном x.
## gap_c=NAN — сплошная; иначе вырез шириной 2*gap_h по центру gap_c.
func _wall_seg(vertical: bool, fixed: float, lo: float, hi: float, t: float,
		gap_c: float, gap_h: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var spans: Array = []
	if is_nan(gap_c):
		spans.append([lo, hi])
	else:
		spans.append([lo, gap_c - gap_h])
		spans.append([gap_c + gap_h, hi])
	for s: Array in spans:
		var a: float = s[0]
		var b: float = s[1]
		if b - a < 0.05:
			continue
		if vertical:
			out.append(Rect2(fixed - t * 0.5, a, t, b - a))
		else:
			out.append(Rect2(a, fixed - t * 0.5, b - a, t))
	return out


## Состояние дверей: 1=открыта, 0=закрыта. Индекс этажа = floor-1.
var mall_door_open: Array = []   # Array[PackedByteArray]

func reset_doors() -> void:
	mall_door_open.clear()
	for _fl in Tuning.MALL_FLOORS:
		var row := PackedByteArray()
		row.resize(mall_doors.size())
		row.fill(1)
		mall_door_open.append(row)


func is_door_open(floor: int, di: int) -> bool:
	var fi := floor - 1
	if fi < 0 or fi >= mall_door_open.size():
		return true
	var row: PackedByteArray = mall_door_open[fi]
	return di < 0 or di >= row.size() or row[di] == 1


func set_door(floor: int, di: int, open_state: bool) -> void:
	var fi := floor - 1
	if fi < 0 or fi >= mall_door_open.size():
		return
	var row: PackedByteArray = mall_door_open[fi]
	if di >= 0 and di < row.size():
		row[di] = 1 if open_state else 0
		mall_door_open[fi] = row


## Ближайшая к точке дверь на этаже в радиусе; -1 если нет.
func nearest_door(p: Vector2, floor: int, radius: float) -> int:
	if floor < 1 or floor > Tuning.MALL_FLOORS:
		return -1
	var best := -1
	var best_d := radius * radius
	for door: Dictionary in mall_doors:
		var d2: float = p.distance_squared_to(door["pos"])
		if d2 < best_d:
			best_d = d2
			best = door["di"]
	return best


## Индекс комнаты, содержащей точку (0 = атриум).
func mall_room_at(p: Vector2) -> int:
	for room: Dictionary in mall_rooms:
		if (room["rect"] as Rect2).has_point(p):
			return room["id"]
	return 0


## Путь по этажу ТЦ: список вейпоинтов (двери + финальная точка to).
## Учитывает закрытые двери (ребро недоступно). Пусто→[to], если одна комната.
func mall_path(from: Vector2, to: Vector2, floor: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ra := mall_room_at(from)
	var rb := mall_room_at(to)
	if ra == rb:
		out.append(to)
		return out
	# BFS по маленькому графу узлов, пропуская закрытые двери.
	var prev := {ra: -1}
	var queue := [ra]
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		if cur == rb:
			break
		for e: Dictionary in _mall_adj.get(cur, []):
			if not is_door_open(floor, e["di"]):
				continue
			var nxt: int = e["other"]
			if not prev.has(nxt):
				prev[nxt] = cur
				queue.append(nxt)
	if not prev.has(rb):
		out.append(to)   # недостижимо (двери закрыты) — идём напрямую (fallback)
		return out
	# Восстанавливаем цепочку узлов rb..ra.
	var chain: Array[int] = []
	var n := rb
	while n != -1:
		chain.append(n)
		n = prev[n]
	chain.reverse()   # ra .. rb
	# Двери между соседними узлами.
	for i in range(chain.size() - 1):
		out.append(_door_between(chain[i], chain[i + 1]))
	out.append(to)
	return out


func _door_between(a: int, b: int) -> Vector2:
	for e: Dictionary in _mall_adj.get(a, []):
		if e["other"] == b:
			return e["pos"]
	return Vector2.ZERO


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
		# Закрытые двери перекрывают проём.
		for door: Dictionary in mall_doors:
			if not is_door_open(floor, door["di"]):
				if (door["plug"] as Rect2).grow(radius).has_point(p):
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
		for door: Dictionary in mall_doors:
			if not is_door_open(floor, door["di"]):
				var plug: Rect2 = door["plug"]
				if plug.grow(radius).has_point(p):
					p = _push_rect(p, plug, radius)
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
