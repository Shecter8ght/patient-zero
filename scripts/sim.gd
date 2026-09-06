extends Node3D
## Ядро симуляции. Все агенты живут в плоских массивах, НЕ в нодах.
## 300 нод с _process уронят FPS — держим данные в массивах,
## рисуем через MultiMeshInstance3D (см. agent_renderer.gd).

enum S { HEALTHY, INFECTED, DEAD, COP, LATENT, INFECTED_COP }

# --- Данные агентов ---
var pos:          PackedVector2Array
var vel:          PackedVector2Array
var state:        PackedByteArray
var timer:        PackedFloat32Array
var resist:       PackedFloat32Array
var grab_target:  PackedInt32Array
var grab_prog:    PackedFloat32Array
var panic:        PackedFloat32Array
var facing:       PackedFloat32Array
var alert:        PackedFloat32Array
var alert_target: PackedInt32Array
var was_cop:      PackedByteArray
var floor_idx:    PackedByteArray     # 0=улица, 1..MALL_FLOORS=ТЦ
var floor_cd:     PackedFloat32Array  # кулдаун смены этажа
var health:       PackedByteArray     # здоровье: AGENT_HEALTH выстрелов
var archetype:    PackedByteArray     # ARCH_* константы Tuning
var infect_thresh: PackedFloat32Array # порог p_prog для заражения по архетипу
var photo_timer:  PackedFloat32Array  # > 0 = журналист фотографирует
var has_phone:    PackedByteArray     # 1 = есть телефон
var phone_timer:  PackedFloat32Array  # > 0 = звонит (обратный отсчёт)

# --- Игрок ---
var p_pos      := Vector2.ZERO
var p_vel      := Vector2.ZERO
var p_grab     := -1
var p_prog     := 0.0
var p_floor    := 0
var p_floor_cd := 0.0
var sprinting  := false
var holding    := false

# --- Арест ---
var p_being_arrested := false
var p_arrest_timer   := 0.0
var _arresting_cop   := -1
var p_qte_key        := KEY_NONE   # текущая ожидаемая клавиша
var p_qte_key_str    := ""         # строка для HUD
var _qte_timer       := 0.0        # время до смены клавиши

# --- QTE захвата ---
var _grab_qte_key     := KEY_NONE
var _grab_qte_str     := ""
var _grab_qte_timer   := 0.0
var _grab_wrong_count := 0

# --- Бросок ---
var _throw_cd := 0.0

const _QTE_KEYS := [
	["W", KEY_W], ["A", KEY_A], ["S", KEY_S], ["D", KEY_D],
	["E", KEY_E], ["F", KEY_F], ["Q", KEY_Q], ["G", KEY_G],
]

# --- Состояние забега ---
var suspicion     := 0.0
var elapsed       := 0.0
var cop_count     := 0
var cop_spawn_t   := 0.0
var finished      := 0   # 0=идёт, 1=победа, 2=поражение

var evac_timer  := 0.0
var evac_count  := 0
var evac_points: Array[Dictionary] = []

# --- Орда ---
var horde_target      := Vector2.ZERO
var horde_target_life := 0.0

# --- Мутации ---
var active_mutations: Array[int] = []
var _next_mut_at     := Tuning.MUT_THRESHOLD
var _pending_mutation := false
var grab_range_eff   := Tuning.GRAB_RANGE
var incubation_eff   := Tuning.INCUBATION
var _backstab_applied := false

# --- Эскалация ---
var escalation_level := 0
var _esc_checked     := [false, false, false]

# --- SWAT ---
var is_swat: PackedByteArray

var _grid := {}

signal run_finished(result: int, seconds: float)
signal escalation_triggered(level: int, headline: String)
signal stats_changed(healthy: int, infected: int, latent: int, dead: int, cops: int, suspicion: float, arrest_prog: float, qte_key: String, evac_count: int)
signal shot_fired(from_pos: Vector2, to_pos: Vector2)
signal mutation_available(options: Array)
signal horde_commanded(world_pos: Vector2)
signal bark_event(agent: int, cat: String, pos2: Vector2, fl: int)


func _ready() -> void:
	reset_run()


func reset_run() -> void:
	var n := Tuning.AGENT_COUNT
	pos.resize(n);         vel.resize(n);         state.resize(n)
	timer.resize(n);       resist.resize(n);      grab_target.resize(n)
	grab_prog.resize(n);   panic.resize(n);       facing.resize(n)
	alert.resize(n);       alert_target.resize(n); was_cop.resize(n)
	floor_idx.resize(n);   floor_cd.resize(n);    health.resize(n)
	is_swat.resize(n)
	archetype.resize(n);   infect_thresh.resize(n); photo_timer.resize(n)
	has_phone.resize(n);   phone_timer.resize(n)

	MapGen.generate()

	# -------- распределение агентов --------
	# 200 — в ТЦ равномерно по этажам, 300 — на улице
	var mall_per_floor := 50
	var mall_total := mall_per_floor * Tuning.MALL_FLOORS   # 200
	var out_total  := n - mall_total                         # 300

	var out_pts: Array = Array(MapGen.spawn_points)
	out_pts.shuffle()

	for i in n:
		var fl    := 0
		var pt    := Vector2.ZERO

		if i < mall_total:
			fl = (i / mall_per_floor) + 1   # этажи 1..MALL_FLOORS
			var mall_pts: PackedVector2Array = MapGen.mall_spawns[fl - 1]
			if mall_pts.size() > 0:
				pt = mall_pts[i % mall_pts.size()]
			else:
				pt = Vector2(randf_range(-9, 9), randf_range(-9, 9))
		else:
			var oi := (i - mall_total) % out_pts.size()
			pt = out_pts[oi] if out_pts.size() > 0 else Vector2.ZERO

		pos[i]          = pt
		floor_idx[i]    = fl
		vel[i]          = Vector2.ZERO
		state[i]        = S.HEALTHY
		timer[i]        = 0.0
		resist[i]       = randf_range(Tuning.RESIST_MIN, Tuning.RESIST_MAX)
		grab_target[i]  = -1
		grab_prog[i]    = 0.0
		panic[i]        = 0.0
		facing[i]       = randf() * TAU
		alert[i]        = 0.0
		alert_target[i] = -1
		was_cop[i]      = 0
		floor_cd[i]     = 0.0
		health[i]       = Tuning.AGENT_HEALTH
		# Архетип
		var arch := 0
		var rng_a := randf()
		var cum   := 0.0
		for ai in Tuning.ARCH_FREQ.size():
			cum += Tuning.ARCH_FREQ[ai]
			if rng_a < cum:
				arch = ai
				break
		archetype[i]    = arch
		infect_thresh[i] = Tuning.ARCH_THRESH[arch]
		photo_timer[i]  = 0.0
		is_swat[i]      = 0
		var can_have_phone := (arch == Tuning.ARCH_NORMAL or arch == Tuning.ARCH_ELDER)
		has_phone[i]   = 1 if (can_have_phone and randf() < Tuning.PHONE_FREQ) else 0
		phone_timer[i] = 0.0

	# -------- игрок появляется в переулке у края карты --------
	var corner := Vector2(-65.0, -65.0)
	var best_pt := corner
	var best_d  := INF
	for sp in MapGen.spawn_points:
		var d := sp.distance_squared_to(corner)
		if d < best_d:
			best_d  = d
			best_pt = sp
	p_pos            = best_pt
	p_vel            = Vector2.ZERO
	p_grab           = -1
	p_prog           = 0.0
	p_floor          = 0
	p_floor_cd       = 0.0
	p_being_arrested  = false
	p_arrest_timer    = 0.0
	_arresting_cop    = -1
	p_qte_key         = KEY_NONE
	p_qte_key_str     = ""
	_qte_timer        = 0.0
	_grab_qte_key     = KEY_NONE
	_grab_qte_str     = ""
	_grab_qte_timer   = 0.0
	_grab_wrong_count = 0
	_throw_cd         = 0.0
	suspicion         = 0.0
	elapsed          = 0.0
	cop_count        = 0
	cop_spawn_t      = 0.0
	finished         = 0
	horde_target      = Vector2.ZERO
	horde_target_life = 0.0
	evac_timer        = Tuning.EVAC_FIRST_TIME
	evac_count        = 0
	evac_points.clear()
	active_mutations.clear()
	_next_mut_at      = Tuning.MUT_THRESHOLD
	_pending_mutation = false
	grab_range_eff    = Tuning.GRAB_RANGE
	incubation_eff    = Tuning.INCUBATION
	_backstab_applied = false
	escalation_level  = 0
	_esc_checked      = [false, false, false]


func _physics_process(delta: float) -> void:
	if finished != 0:
		return
	if _pending_mutation:
		return
	elapsed += delta
	_rebuild_grid()
	_update_player(delta)
	_update_agents(delta)
	_spawn_cops(delta)
	_tick_evac(delta)
	suspicion = clampf(suspicion - Tuning.SUSP_DECAY * delta, 0.0, 100.0)


# ---------------------------------------------------------------- сетка
func _rebuild_grid() -> void:
	_grid.clear()
	for i in pos.size():
		if state[i] == S.DEAD:
			continue
		var key := _cell3(pos[i], floor_idx[i])
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		_grid[key].append(i)


func _cell3(p: Vector2, floor: int) -> Vector3i:
	return Vector3i(floor, floori(p.x / Tuning.GRID_CELL), floori(p.y / Tuning.GRID_CELL))


func _neighbors(p: Vector2, floor: int) -> Array[int]:
	var out: Array[int] = []
	var cx := floori(p.x / Tuning.GRID_CELL)
	var cy := floori(p.y / Tuning.GRID_CELL)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector3i(floor, cx + dx, cy + dy)
			if _grid.has(k):
				for i in _grid[k]:
					out.append(i)
	return out


# ---------------------------------------------------------------- арест
func _handle_arrest(delta: float) -> void:
	if _arresting_cop < 0 or state[_arresting_cop] != S.COP:
		_clear_arrest()
		return

	# Игрок заморожен
	p_vel = p_vel.move_toward(Vector2.ZERO, Tuning.ACCEL * delta)

	# Таймер ареста
	p_arrest_timer += delta
	if p_arrest_timer >= Tuning.ARREST_TIME:
		finished = 2
		run_finished.emit(2, elapsed)
		return

	# Смена клавиши по интервалу
	_qte_timer -= delta
	if _qte_timer <= 0.0:
		_qte_timer = Tuning.QTE_INTERVAL
		var pick: Array = _QTE_KEYS[randi() % _QTE_KEYS.size()]
		p_qte_key_str = pick[0]
		p_qte_key     = pick[1]


func _clear_arrest() -> void:
	p_being_arrested = false
	p_arrest_timer   = 0.0
	_arresting_cop   = -1
	p_qte_key        = KEY_NONE
	p_qte_key_str    = ""
	_qte_timer       = 0.0
	p_grab           = -1
	p_prog           = 0.0


# ---------------------------------------------------------------- игрок
func _update_player(delta: float) -> void:
	p_floor_cd = maxf(0.0, p_floor_cd - delta)

	if p_being_arrested:
		_handle_arrest(delta)
		return

	_throw_cd         = maxf(0.0, _throw_cd - delta)
	horde_target_life = maxf(0.0, horde_target_life - delta)

	var mouse_world := _mouse_world_pos()
	var to_mouse    := mouse_world - p_pos
	var dist_m      := to_mouse.length()
	var dir         := Vector2.ZERO
	if dist_m > 0.25:
		dir = to_mouse.normalized()
		if dist_m < 1.5:
			dir *= dist_m / 1.5  # притормаживаем рядом с курсором

	var speed := Tuning.PLAYER_SPRINT if sprinting else Tuning.PLAYER_WALK
	if p_grab >= 0:
		speed *= 0.35

	p_vel = p_vel.move_toward(dir * speed, Tuning.ACCEL * delta)
	p_pos += p_vel * delta
	p_pos  = MapGen.push_out(p_pos, 0.35, p_floor)
	if p_floor == 0:
		p_pos = _clamp_world(p_pos)

	# Переход между этажами
	if p_floor_cd <= 0.0:
		var tr := MapGen.check_transition(p_pos, p_floor)
		if not tr.is_empty():
			p_floor    = tr["to_floor"]
			p_pos      = tr["dest"]
			p_floor_cd = Tuning.FLOOR_CD

	# Начать захват
	if holding and p_grab < 0:
		var best   := -1
		var best_d := grab_range_eff * grab_range_eff
		for i in _neighbors(p_pos, p_floor):
			var s := state[i]
			if s != S.HEALTHY and s != S.COP:
				continue
			if floor_idx[i] != p_floor:
				continue
			var d := pos[i].distance_squared_to(p_pos)
			if d < best_d:
				best_d = d
				best   = i
		if best >= 0:
			p_grab = best
			p_prog = 0.0
			_backstab_applied = false
			bark_event.emit(best, "grabbed", pos[best], p_floor)
			# MUT_BACKSTAB: жертва спиной — 1 нажатие QTE
			if Tuning.MUT_BACKSTAB in active_mutations:
				var to_player := (p_pos - pos[best]).normalized()
				var vf := Vector2(cos(facing[best]), sin(facing[best]))
				if to_player.dot(vf) < -0.4:
					infect_thresh[best] = minf(infect_thresh[best], Tuning.QTE_HIT_PROG)
					_backstab_applied = true

	# Отпустил рано
	if not holding and p_grab >= 0:
		_break_grab(true)

	if p_grab >= 0:
		var v := p_grab
		if state[v] != S.HEALTHY and state[v] != S.COP:
			_break_grab(false)
		elif pos[v].distance_to(p_pos) > Tuning.GRAB_BREAK_RANGE:
			_break_grab(true)
		else:
			pos[v] = pos[v].lerp(p_pos, 1.0 - exp(-6.0 * delta))
			var help := _count_helpers(v)
			# Толпа оттаскивает жертву
			if help >= Tuning.HELPER_SHOVE_AT:
				p_prog -= Tuning.HELPER_SHOVE_LOSS * delta
				if p_prog <= -0.05:
					_break_grab(true)
			# QTE-таймер — если не нажал вовремя, считается промах
			if p_grab >= 0:
				_grab_qte_timer -= delta
				if _grab_qte_timer <= 0.0:
					if _grab_qte_key != KEY_NONE:
						# Время вышло → промах
						_grab_qte_key   = KEY_NONE
						_grab_qte_str   = ""
						_grab_wrong_count += 1
						if _grab_wrong_count >= Tuning.QTE_WRONG_LIMIT:
							suspicion += Tuning.SUSP_QTE_FAIL
							_break_grab(true)
					if p_grab >= 0:
						_grab_qte_timer = Tuning.GRAB_QTE_INTERVAL
						var pick: Array = _QTE_KEYS[randi() % _QTE_KEYS.size()]
						_grab_qte_str = pick[0]
						_grab_qte_key = pick[1]


func _break_grab(scream: bool) -> void:
	if p_grab >= 0:
		var v   := p_grab
		var away := pos[v] - p_pos
		if away.length() < 0.01:
			away = Vector2.RIGHT.rotated(randf() * TAU)
		vel[v] = away.normalized() * Tuning.KNOCKBACK_SPEED
		panic[v] = Tuning.PANIC_MEMORY
		if scream and p_prog > 0.15:
			suspicion += Tuning.SUSP_GRAB_FAIL
			bark_event.emit(v, "broke_free", pos[v], floor_idx[v])
	p_grab            = -1
	p_prog            = 0.0
	_backstab_applied = false
	_clear_grab_qte()


func _clear_grab_qte() -> void:
	_grab_qte_key     = KEY_NONE
	_grab_qte_str     = ""
	_grab_qte_timer   = 0.0
	_grab_wrong_count = 0


func _try_auto_grab() -> void:
	if Tuning.MUT_AUTO_GRAB not in active_mutations or p_grab >= 0:
		return
	var best   := -1
	var best_d := grab_range_eff * 4.0 * grab_range_eff * 4.0
	for nb in _neighbors(p_pos, p_floor):
		if (state[nb] == S.HEALTHY or state[nb] == S.COP) and floor_idx[nb] == p_floor:
			var da := pos[nb].distance_squared_to(p_pos)
			if da < best_d:
				best_d = da
				best   = nb
	if best >= 0:
		p_grab          = best
		p_prog          = 0.0
		_grab_qte_timer = 0.0
		_backstab_applied = false


func _count_helpers(v: int) -> int:
	var n  := 0
	var r2 := Tuning.HELPER_RADIUS * Tuning.HELPER_RADIUS
	for i in _neighbors(pos[v], floor_idx[v]):
		if i == v or state[i] != S.HEALTHY:
			continue
		if pos[i].distance_squared_to(pos[v]) < r2:
			n += 1
	return n


func _infect(i: int) -> void:
	phone_timer[i] = 0.0   # заразили — звонок отменён
	was_cop[i] = 1 if state[i] == S.COP else 0
	if state[i] == S.COP:
		cop_count -= 1
	state[i]       = S.LATENT
	timer[i]       = incubation_eff
	grab_target[i] = -1
	grab_prog[i]   = 0.0
	bark_event.emit(i, "turning", pos[i], floor_idx[i])
	# Бонус за обращение SWAT — мгновенная мутация
	if is_swat[i] == 1:
		is_swat[i] = 0
		if not _pending_mutation:
			_pending_mutation = true
			_offer_mutations()


# ---------------------------------------------------------------- мутации
func _offer_mutations() -> void:
	var available: Array = []
	for mid in Tuning.MUT_NAMES.size():
		if mid not in active_mutations:
			available.append(mid)
	available.shuffle()
	var options := available.slice(0, min(3, available.size()))
	mutation_available.emit(options)


func apply_mutation(mut_id: int) -> void:
	if mut_id in active_mutations:
		return
	active_mutations.append(mut_id)
	_pending_mutation = false
	match mut_id:
		Tuning.MUT_FAST_INCUBATION:
			incubation_eff = 6.0
		Tuning.MUT_WIDE_GRAB:
			grab_range_eff = Tuning.GRAB_RANGE * 2.0


# ---------------------------------------------------------------- агенты
func _update_agents(delta: float) -> void:
	var healthy  := 0
	var infected := 0
	var latent   := 0
	var dead     := 0
	var cops     := 0

	for i in pos.size():
		floor_cd[i] = maxf(0.0, floor_cd[i] - delta)

		match state[i]:
			S.DEAD:
				dead += 1
				continue
			S.LATENT:
				latent   += 1
				infected += 1
				_tick_latent(i, delta)
			S.INFECTED, S.INFECTED_COP:
				infected += 1
				_tick_infected(i, delta)
			S.COP:
				cops += 1
				_tick_cop(i, delta)
			_:
				healthy += 1
				_tick_civilian(i, delta)

		pos[i] += vel[i] * delta
		pos[i]  = MapGen.push_out(pos[i], 0.35, floor_idx[i])
		if floor_idx[i] == 0:
			pos[i] = _clamp_world(pos[i])

		if vel[i].length_squared() > 0.01:
			facing[i] = vel[i].angle()

		# Переход между этажами для агента
		if floor_cd[i] <= 0.0:
			var tr := MapGen.check_transition(pos[i], floor_idx[i])
			if not tr.is_empty():
				floor_idx[i] = tr["to_floor"]
				pos[i]       = tr["dest"]
				floor_cd[i]  = Tuning.FLOOR_CD

	# MUT_CROWD_SPREAD — заражённые медленно заражают соседей
	if Tuning.MUT_CROWD_SPREAD in active_mutations:
		var to_infect: Array[int] = []
		for i in pos.size():
			if state[i] != S.INFECTED and state[i] != S.INFECTED_COP:
				continue
			for nb in _neighbors(pos[i], floor_idx[i]):
				if (state[nb] == S.HEALTHY or state[nb] == S.COP) and floor_idx[nb] == floor_idx[i]:
					if pos[nb].distance_squared_to(pos[i]) < 2.5 * 2.5:
						grab_prog[nb] += 0.04 * delta
						if grab_prog[nb] >= 1.0:
							grab_prog[nb] = 0.0
							to_infect.append(nb)
		for j in to_infect:
			_infect(j)

	# Проверка порога мутации
	var total_infected := infected + latent + dead
	if total_infected >= _next_mut_at and not _pending_mutation:
		_next_mut_at += Tuning.MUT_THRESHOLD
		_pending_mutation = true
		_offer_mutations()

	# Проверка порогов эскалации
	var total_agents := pos.size()
	var infected_frac := float(infected + latent + dead) / float(total_agents) if total_agents > 0 else 0.0
	for ei in Tuning.ESC_THRESHOLDS.size():
		if not _esc_checked[ei] and infected_frac >= Tuning.ESC_THRESHOLDS[ei]:
			_esc_checked[ei] = true
			escalation_level = ei + 1
			cop_spawn_t      = 0.0
			escalation_triggered.emit(escalation_level, Tuning.ESC_HEADLINES_RU[ei])

	var got := infected + dead
	var arrest_prog := p_arrest_timer / Tuning.ARREST_TIME if p_being_arrested else 0.0
	var qte_str: String
	if p_being_arrested:
		qte_str = p_qte_key_str
	elif p_grab >= 0:
		qte_str = _grab_qte_str
	else:
		qte_str = ""
	stats_changed.emit(healthy, infected, latent, dead, cops, suspicion, arrest_prog, qte_str, evac_count)
	if pos.size() > 0 and float(got) / float(pos.size()) >= Tuning.WIN_RATIO:
		finished = 1
		run_finished.emit(1, elapsed)


func _tick_latent(i: int, delta: float) -> void:
	_wander(i, delta, Tuning.CIV_WALK)
	timer[i] -= delta
	if timer[i] <= 0.0:
		state[i] = S.INFECTED_COP if was_cop[i] == 1 else S.INFECTED
		if Tuning.MUT_SILENT_REVEAL not in active_mutations:
			suspicion += Tuning.SUSP_REVEAL
			panic[i]   = Tuning.PANIC_MEMORY


func _tick_infected(i: int, delta: float) -> void:
	var is_cop := state[i] == S.INFECTED_COP
	var speed  := Tuning.INFECTED_COP_SPEED if is_cop else Tuning.INFECTED_SPEED

	if grab_target[i] >= 0:
		var v := grab_target[i]
		if state[v] != S.HEALTHY or floor_idx[v] != floor_idx[i] \
				or pos[v].distance_to(pos[i]) > Tuning.GRAB_BREAK_RANGE:
			grab_target[i] = -1
			grab_prog[i]   = 0.0
		else:
			pos[v] = pos[v].lerp(pos[i], 1.0 - exp(-5.0 * delta))
			var base := Tuning.GRAB_TIME * resist[v] * (0.6 if is_cop else 1.3)
			grab_prog[i] += delta / base
			vel[i] = vel[i].move_toward(Vector2.ZERO, Tuning.ACCEL * delta)
			if grab_prog[i] >= 1.0:
				_infect(v)
				grab_target[i] = -1
				grab_prog[i]   = 0.0
			return

	# Команда орды — двигаемся к цели (только на улице)
	if horde_target_life > 0.0 and floor_idx[i] == 0:
		var to_target := horde_target - pos[i]
		var dist_t    := to_target.length()
		if dist_t > Tuning.HORDE_ARRIVE_DIST:
			vel[i] = vel[i].lerp(to_target.normalized() * speed, 0.12)
			pos[i] += vel[i] * delta
			pos[i]  = MapGen.push_out(pos[i], 0.3, floor_idx[i])
			pos[i]  = _clamp_world(pos[i])
			# Хватаем если жертва оказалась рядом по пути
			for nb in _neighbors(pos[i], floor_idx[i]):
				if (state[nb] == S.HEALTHY or state[nb] == S.COP) and floor_idx[nb] == floor_idx[i]:
					if pos[nb].distance_squared_to(pos[i]) < grab_range_eff * grab_range_eff:
						grab_target[i] = nb
						grab_prog[i]   = 0.0
						break
			return

	var target := _nearest(pos[i], floor_idx[i], S.HEALTHY, 25.0)
	if target >= 0:
		var to := pos[target] - pos[i]
		vel[i] = vel[i].move_toward(to.normalized() * speed, Tuning.ACCEL * delta)
		if to.length() < Tuning.GRAB_RANGE:
			grab_target[i] = target
			grab_prog[i]   = 0.0
	else:
		_wander(i, delta, speed * 0.5)


func _tick_cop(i: int, delta: float) -> void:
	# Арестующий коп держит позицию — логику пропускаем
	if p_being_arrested and _arresting_cop == i:
		vel[i] = vel[i].move_toward(Vector2.ZERO, Tuning.ACCEL * delta)
		return

	timer[i] = maxf(0.0, timer[i] - delta)
	alert[i] = maxf(0.0, alert[i] - delta)

	var seen := -1
	var best := Tuning.COP_VIEW_DIST * Tuning.COP_VIEW_DIST
	var fov  := deg_to_rad(Tuning.COP_FOV_DEG) * 0.5
	for j in _neighbors(pos[i], floor_idx[i]):
		var s := state[j]
		if s != S.INFECTED and s != S.INFECTED_COP:
			continue
		if floor_idx[j] != floor_idx[i]:
			continue
		var to := pos[j] - pos[i]
		var d2 := to.length_squared()
		if d2 > best:
			continue
		if absf(angle_difference(facing[i], to.angle())) > fov:
			continue
		best = d2
		seen = j

	if seen >= 0:
		alert_target[i] = seen
		alert[i]        = Tuning.COP_MEMORY
		_radio(i, seen)

	var goal := Vector2.INF
	if alert[i] > 0.0 and alert_target[i] >= 0:
		var t := alert_target[i]
		if state[t] == S.INFECTED or state[t] == S.INFECTED_COP:
			goal = pos[t]
			if timer[i] <= 0.0 and pos[t].distance_to(pos[i]) < Tuning.COP_SHOOT_RANGE:
				health[t] = maxi(0, health[t] - 1)
				timer[i] = Tuning.COP_SHOOT_CD
				shot_fired.emit(pos[i], pos[t])
				bark_event.emit(i, "cop_shoot", pos[i], floor_idx[i])
				if health[t] == 0:
					state[t] = S.DEAD
		else:
			alert[i] = 0.0

	if suspicion > Tuning.SUSP_HUNT_PLAYER \
			and floor_idx[i] == p_floor \
			and p_pos.distance_to(pos[i]) < Tuning.COP_VIEW_DIST:
		goal = p_pos
		if p_pos.distance_to(pos[i]) < Tuning.COP_ARREST_RANGE and not p_being_arrested:
			p_being_arrested = true
			_arresting_cop   = i
			p_prog           = 0.0

	if goal != Vector2.INF:
		var cop_spd := Tuning.SWAT_SPEED if is_swat[i] == 1 else Tuning.COP_SPEED
		vel[i] = vel[i].move_toward((goal - pos[i]).normalized() * cop_spd, Tuning.ACCEL * delta)
	else:
		_patrol(i, delta)


func _radio(from: int, target: int) -> void:
	var r2 := Tuning.COP_RADIO_RADIUS * Tuning.COP_RADIO_RADIUS
	for j in _neighbors(pos[from], floor_idx[from]):
		if state[j] != S.COP or j == from:
			continue
		if floor_idx[j] != floor_idx[from]:
			continue
		if pos[j].distance_squared_to(pos[from]) < r2:
			alert[j]        = Tuning.COP_MEMORY
			alert_target[j] = target


func _tick_civilian(i: int, delta: float) -> void:
	# Журналист: видит захват → фотографирует
	if archetype[i] == Tuning.ARCH_JOURNALIST and state[i] == S.HEALTHY:
		var near_grab := (p_grab >= 0 and i != p_grab
			and floor_idx[i] == p_floor
			and pos[i].distance_squared_to(pos[p_grab]) < Tuning.PANIC_RADIUS * Tuning.PANIC_RADIUS)
		if near_grab and photo_timer[i] <= 0.0:
			photo_timer[i] = Tuning.JOURNALIST_PHOTO_TIME
		if photo_timer[i] > 0.0:
			photo_timer[i] -= delta
			if photo_timer[i] <= 0.0:
				suspicion = minf(100.0, suspicion + Tuning.SUSP_JOURNALIST)
				panic[i]  = Tuning.PANIC_MEMORY
		elif not near_grab:
			photo_timer[i] = 0.0

	# Телефон: звонок в полицию при виде паники
	var calling := false
	if has_phone[i] == 1 and state[i] == S.HEALTHY and panic[i] <= 0.0 and floor_idx[i] == 0:
		if phone_timer[i] > 0.0:
			calling = true
			phone_timer[i] -= delta
			if phone_timer[i] <= 0.0:
				suspicion = minf(100.0, suspicion + Tuning.SUSP_PHONE_CALL)
				var spawned := 0
				for j in pos.size():
					if spawned >= Tuning.PHONE_COP_BONUS:
						break
					if state[j] == S.HEALTHY and panic[j] <= 0.0 and floor_idx[j] == 0:
						var edge := Vector2.RIGHT.rotated(randf() * TAU) * (Tuning.WORLD_SIZE * 0.5 - 1.0)
						pos[j]          = edge
						state[j]        = S.COP
						resist[j]       = 1.2
						alert[j]        = 0.0
						alert_target[j] = -1
						cop_count       += 1
						spawned         += 1
		else:
			var sees_panic := false
			var r2_phone := Tuning.PHONE_PANIC_RANGE * Tuning.PHONE_PANIC_RANGE
			for nb in _neighbors(pos[i], floor_idx[i]):
				if nb == i:
					continue
				if panic[nb] > 0.0 and pos[nb].distance_squared_to(pos[i]) < r2_phone:
					sees_panic = true
					break
			if sees_panic:
				phone_timer[i] = Tuning.PHONE_CALL_TIME

	# Эвакуация: тянет здоровых без паники на улице к точке
	var going_to_evac := false
	if state[i] == S.HEALTHY and panic[i] <= 0.0 and floor_idx[i] == 0 and not evac_points.is_empty():
		var nearest_evac := Vector2.ZERO
		var nearest_d    := INF
		for ep in evac_points:
			var d2 := pos[i].distance_squared_to(ep["pos"])
			if d2 < nearest_d:
				nearest_d    = d2
				nearest_evac = ep["pos"]
		if nearest_d < Tuning.EVAC_PULL_RANGE * Tuning.EVAC_PULL_RANGE:
			var to_evac   := nearest_evac - pos[i]
			var dist_evac := to_evac.length()
			if dist_evac < Tuning.EVAC_RADIUS:
				state[i]    = S.DEAD
				evac_count += 1
				if evac_count >= Tuning.EVAC_LOSE_AT and finished == 0:
					finished = 3
					run_finished.emit(3, elapsed)
				return
			if not going_to_evac:
				bark_event.emit(i, "evac_call", pos[i], floor_idx[i])
			going_to_evac = true
			vel[i] = vel[i].lerp((to_evac / dist_evac) * Tuning.EVAC_PULL_SPEED, 0.15)

	var flee   := Vector2.ZERO
	var threats := 0
	var r2     := Tuning.PANIC_RADIUS * Tuning.PANIC_RADIUS

	# Тело рядом — замечаем (только если ещё не паникуем)
	if state[i] == S.HEALTHY and panic[i] <= 0.0:
		for nb in _neighbors(pos[i], floor_idx[i]):
			if state[nb] == S.DEAD and pos[nb].distance_squared_to(pos[i]) < 5.0 * 5.0:
				bark_event.emit(i, "spot_body", pos[i], floor_idx[i])
				break

	for j in _neighbors(pos[i], floor_idx[i]):
		var s := state[j]
		if s != S.INFECTED and s != S.INFECTED_COP:
			continue
		if floor_idx[j] != floor_idx[i]:
			continue
		var d := pos[i] - pos[j]
		if d.length_squared() < r2:
			if flee.length_squared() < 0.001:
				bark_event.emit(i, "spot_infected", pos[i], floor_idx[i])
			flee   += d.normalized()
			threats += 1

	if (sprinting or suspicion > 50.0) and floor_idx[i] == p_floor:
		var dp := pos[i] - p_pos
		if dp.length_squared() < r2 and p_grab != i:
			flee   += dp.normalized()
			threats += 1
			if Tuning.MUT_SILENT_SPRINT not in active_mutations:
				suspicion += Tuning.SUSP_SPRINT_NEAR * delta

	# Свидетели захвата — разбегаются от игрока
	if p_grab >= 0 and floor_idx[i] == p_floor and i != p_grab:
		var dg := pos[i] - p_pos
		if dg.length_squared() < r2:
			flee   += dg.normalized()
			threats += 1

	if threats > 0:
		if panic[i] <= 0.0:
			bark_event.emit(i, "flee_panic", pos[i], floor_idx[i])
		panic[i] = Tuning.PANIC_MEMORY

	if panic[i] > 0.0:
		panic[i] -= delta
		var panic_spd := Tuning.CIV_PANIC * Tuning.ARCH_PANIC_MULT[archetype[i]]
		if flee.length_squared() > 0.001:
			vel[i] = vel[i].move_toward(flee.normalized() * panic_spd, Tuning.ACCEL * delta)
		else:
			vel[i] = vel[i].move_toward(vel[i].normalized() * panic_spd, Tuning.ACCEL * delta)
	elif p_grab == i:
		vel[i] = vel[i].move_toward(Vector2.ZERO, Tuning.KNOCKBACK_DECAY * delta)
	elif calling:
		vel[i] = vel[i].move_toward(Vector2.ZERO, Tuning.ACCEL * delta)
	elif not going_to_evac:
		_wander(i, delta, Tuning.CIV_WALK)


func _wander(i: int, delta: float, speed: float) -> void:
	var ahead := pos[i] + Vector2.RIGHT.rotated(facing[i]) * 2.0
	if MapGen.is_blocked(ahead, 0.3, floor_idx[i]):
		facing[i] += PI * 0.5 + randf_range(-0.5, 0.5)
	elif randf() < delta * 0.6:
		facing[i] += randf_range(-1.0, 1.0)
	var want := Vector2.RIGHT.rotated(facing[i]) * speed
	vel[i] = vel[i].move_toward(want, Tuning.ACCEL * 0.5 * delta)


func _patrol(i: int, delta: float) -> void:
	var ahead := pos[i] + Vector2.RIGHT.rotated(facing[i]) * 2.0
	if MapGen.is_blocked(ahead, 0.3, floor_idx[i]):
		facing[i] += PI * 0.5 + randf_range(-0.3, 0.3)
	elif randf() < delta * 0.4:
		facing[i] += randf_range(-0.9, 0.9)
	var patrol_spd := Tuning.SWAT_SPEED if is_swat[i] == 1 else Tuning.COP_SPEED
	vel[i] = vel[i].move_toward(
		Vector2.RIGHT.rotated(facing[i]) * patrol_spd * 0.5,
		Tuning.ACCEL * delta
	)


func _nearest(from: Vector2, floor: int, want: int, max_dist: float) -> int:
	var best := -1
	var bd   := max_dist * max_dist
	for i in _neighbors(from, floor):
		if state[i] != want:
			continue
		if floor_idx[i] != floor:
			continue
		var d := pos[i].distance_squared_to(from)
		if d < bd:
			bd   = d
			best = i
	return best


func _spawn_cops(delta: float) -> void:
	var esc_idx  := clampi(escalation_level - 1, 0, Tuning.ESC_SPAWN_MULTS.size() - 1)
	var spawn_cd := Tuning.COP_SPAWN_INTERVAL * (Tuning.ESC_SPAWN_MULTS[esc_idx] if escalation_level > 0 else 1.0)
	var cop_max  := Tuning.ESC_COP_MAXES[esc_idx] if escalation_level > 0 else Tuning.COP_MAX
	if suspicion < Tuning.SUSP_COP_SPAWN or cop_count >= cop_max:
		return
	cop_spawn_t -= delta
	if cop_spawn_t > 0.0:
		return
	cop_spawn_t = spawn_cd
	var edge := Vector2.RIGHT.rotated(randf() * TAU) * (Tuning.WORLD_SIZE * 0.5 - 1.0)
	for i in pos.size():
		if state[i] == S.HEALTHY and panic[i] <= 0.0 and floor_idx[i] == 0:
			pos[i]          = edge
			state[i]        = S.COP
			resist[i]       = 1.2
			alert[i]        = 0.0
			alert_target[i] = -1
			cop_count       += 1
			# SWAT при высокой эскалации
			var spawn_as_swat := (escalation_level >= Tuning.SWAT_THRESH_LEVEL and
				(escalation_level >= 3 or randf() < 0.5))
			is_swat[i] = 1 if spawn_as_swat else 0
			if is_swat[i] == 1:
				resist[i]       = 2.0
				infect_thresh[i] = Tuning.ARCH_THRESH[Tuning.ARCH_NORMAL] * Tuning.SWAT_GRAB_MULT
			return


func _tick_evac(delta: float) -> void:
	var i := evac_points.size() - 1
	while i >= 0:
		evac_points[i]["life"] -= delta
		if evac_points[i]["life"] <= 0.0:
			evac_points.remove_at(i)
		i -= 1

	evac_timer -= delta
	if evac_timer > 0.0:
		return
	evac_timer = Tuning.EVAC_INTERVAL

	const EVAC_SPOTS: Array = [
		Vector2(0.0,  -62.0),
		Vector2(62.0,   0.0),
		Vector2(0.0,   62.0),
		Vector2(-62.0,  0.0),
	]
	for spot in EVAC_SPOTS:
		var taken := false
		for ep in evac_points:
			if (ep["pos"] as Vector2).distance_squared_to(spot) < 4.0:
				taken = true
				break
		if not taken:
			evac_points.append({"pos": spot, "life": Tuning.EVAC_POINT_LIFE})
			break


func _clamp_world(p: Vector2) -> Vector2:
	var h := Tuning.WORLD_SIZE * 0.5
	return Vector2(clampf(p.x, -h, h), clampf(p.y, -h, h))


func _mouse_world_pos() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return p_pos
	var mp      := get_viewport().get_mouse_position()
	var plane_y := MapGen.floor_y3d(p_floor)
	var ro      := cam.project_ray_origin(mp)
	var rd      := cam.project_ray_normal(mp)
	if abs(rd.y) < 0.0001:
		return p_pos
	var t   := (plane_y - ro.y) / rd.y
	var hit := ro + rd * t
	return Vector2(hit.x, hit.z)


func _do_throw() -> void:
	var best   := -1
	var best_d := Tuning.THROW_RANGE * Tuning.THROW_RANGE
	for i in _neighbors(p_pos, p_floor):
		var s := state[i]
		if s != S.HEALTHY and s != S.COP:
			continue
		if floor_idx[i] != p_floor:
			continue
		var d := pos[i].distance_squared_to(p_pos)
		if d < best_d:
			best_d = d
			best   = i
	if best < 0:
		return
	# Прыжок вплотную к цели
	var dir_to := (pos[best] - p_pos).normalized()
	p_pos = pos[best] - dir_to * (Tuning.GRAB_RANGE * 0.7)
	p_pos = MapGen.push_out(p_pos, 0.35, p_floor)
	if p_floor == 0:
		p_pos = _clamp_world(p_pos)
	p_grab        = best
	p_prog        = Tuning.THROW_START_PROG
	_grab_qte_timer = 0.0
	_throw_cd     = Tuning.THROW_CD
	suspicion     = minf(100.0, suspicion + 5.0)


func _unhandled_input(event: InputEvent) -> void:
	# QTE и Space-побег во время ареста
	if p_being_arrested and event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_SPACE:
				suspicion = minf(100.0, suspicion + 35.0)
				_clear_arrest()
				get_viewport().set_input_as_handled()
				return
			if p_qte_key != KEY_NONE:
				if ke.keycode == p_qte_key:
					p_prog        += Tuning.QTE_HIT_PROG
					p_qte_key      = KEY_NONE
					p_qte_key_str  = ""
					_qte_timer     = 0.0
					if p_prog >= 1.0:
						suspicion = maxf(0.0, suspicion - 25.0)
						_infect(_arresting_cop)
						_clear_arrest()
				get_viewport().set_input_as_handled()
				return

	# QTE захвата — только когда не арестован
	if not p_being_arrested and p_grab >= 0 and event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and _grab_qte_key != KEY_NONE:
			var is_qte_key := false
			for kp in _QTE_KEYS:
				if ke.keycode == kp[1]:
					is_qte_key = true
					break
			if is_qte_key:
				if ke.keycode == _grab_qte_key:
					# Правильная клавиша → прогресс
					p_prog += Tuning.QTE_HIT_PROG
					_grab_qte_key   = KEY_NONE
					_grab_qte_str   = ""
					_grab_qte_timer = 0.0
					if p_prog >= infect_thresh[p_grab]:
						var help2 := _count_helpers(p_grab)
						suspicion += Tuning.SUSP_GRAB_SEEN if help2 > 0 else 1.0
						_infect(p_grab)
						p_grab = -1
						p_prog = 0.0
						_clear_grab_qte()
						_try_auto_grab()
				else:
					# Неверная клавиша — счётчик не сбрасываем
					_grab_qte_key   = KEY_NONE
					_grab_qte_str   = ""
					_grab_qte_timer = 0.0
					_grab_wrong_count += 1
					if _grab_wrong_count >= Tuning.QTE_WRONG_LIMIT:
						suspicion += Tuning.SUSP_QTE_FAIL
						_break_grab(true)
			get_viewport().set_input_as_handled()
			return

	# ПКМ — команда орде
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not p_being_arrested:
			var target := _mouse_world_pos()
			horde_target      = target
			horde_target_life = Tuning.HORDE_CMD_DURATION
			horde_commanded.emit(target)
			get_viewport().set_input_as_handled()
			return

	# Бросок: Alt во время спринта
	if event is InputEventKey:
		var ke2 := event as InputEventKey
		if ke2.pressed and not ke2.echo and ke2.keycode == KEY_ALT:
			if sprinting and _throw_cd <= 0.0 and p_grab < 0 and not p_being_arrested:
				_do_throw()
				get_viewport().set_input_as_handled()
				return

	if event.is_action_pressed("sprint"):
		sprinting = true
	elif event.is_action_released("sprint"):
		sprinting = false
	elif event.is_action_pressed("grab"):
		holding = true
	elif event.is_action_released("grab"):
		holding = false
	elif event.is_action_pressed("restart"):
		reset_run()
