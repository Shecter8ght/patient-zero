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
var survivor_role:   PackedByteArray    # SURV_* константы Tuning (0=нет)
var following_org:   PackedInt32Array   # -1 или индекс организатора
var following_org_t: PackedFloat32Array # оставшееся время следования
var org_rally_t:     PackedFloat32Array # кулдаун сбора группы для организатора

# --- Игрок ---
var p_pos      := Vector2.ZERO
var p_vel      := Vector2.ZERO
var p_grab     := -1
var p_prog     := 0.0
var p_floor    := 0
var p_floor_cd := 0.0
var p_health   := Tuning.AGENT_HEALTH
var sprinting  := false
var holding    := false

# --- Арест ---
var p_being_arrested := false
var p_arrest_timer   := 0.0
var _arresting_cop   := -1
var p_qte_key        := KEY_NONE   # текущая ожидаемая клавиша
var p_qte_key_str    := ""         # строка для HUD
var _qte_timer       := 0.0        # время до смены клавиши

# --- Шкала захвата ---
var _slider_pos    := 0.5   # текущая позиция [0..1]
var _slider_dir    := 1.0   # направление (+1 или -1)
var _resist_gather := 0.0   # секунды с момента скопления толпы
var _player_knock  := Vector2.ZERO  # импульс отброса при атаке толпы

# --- Бросок ---
var _throw_cd := 0.0
var _grab_cd  := 0.0   # кулдаун после разрыва — не прыгать на соседа

const _QTE_ALL  := [["Q",KEY_Q],["W",KEY_W],["E",KEY_E],["A",KEY_A],["S",KEY_S],["D",KEY_D]]
const _QTE_CIV  := [["Q",KEY_Q],["E",KEY_E],["A",KEY_A]]
const _QTE_COP  := [["Q",KEY_Q],["W",KEY_W],["E",KEY_E],["A",KEY_A],["S",KEY_S]]
const _QTE_SWAT := [["Q",KEY_Q],["W",KEY_W],["E",KEY_E],["A",KEY_A],["S",KEY_S],["D",KEY_D]]

# --- Состояние забега ---
var suspicion       := 0.0
var elapsed         := 0.0
var cop_count       := 0
var cop_spawn_t     := 0.0
var finished        := 0   # 0=идёт, 1=победа, 2=поражение
var _infected_frac  := 0.0  # доля заражённых, обновляется в _update_agents

var evac_timer      := 0.0
var evac_count      := 0
var evac_points: Array[Dictionary] = []
var _evac_announced := false

# --- Орда ---
const HC_NONE   := 0   # нет команды
const HC_MOVE   := 1   # двигаться к точке
const HC_ATTACK := 2   # атаковать конкретную цель
const HC_HOLD   := 3   # удерживать зону
const HC_FOLLOW := 4   # следовать за игроком

var horde_cmd          := HC_NONE
var horde_target       := Vector2.ZERO
var horde_target_life  := 0.0
var horde_target_agent := -1   # индекс агента-цели или -1 (позиционная цель)
var horde_floor        := 0    # этаж, с которого выдана команда

# --- Мутации и синтезы ---
var active_mutations:  Array[int] = []
var active_syntheses:  Array[int] = []
var _next_mut_at     := Tuning.MUT_THRESHOLD
var _pending_mutation := false
var grab_range_eff   := Tuning.GRAB_RANGE
var incubation_eff   := Tuning.INCUBATION
var _backstab_applied := false

# --- Эскалация ---
var escalation_level := 0
var _esc_checked     := [false, false, false]

# --- SWAT ---
var is_swat:        PackedByteArray
var is_bus_driver:  PackedByteArray

# --- Маршрутные автобусы ---
var route_buses: Array = []

# --- Идентичности и трекинг заражений ---
var identities:     Array          = []   # Array[Dictionary], один на агента
var infected_by:    PackedInt32Array      # -1=игрок, -2=аура, -3=нет
var infected_at:    PackedFloat32Array
var infected_where: PackedVector2Array
var spread_count:   PackedInt32Array      # сколько других заразил агент
var dest:           PackedVector2Array    # текущая точка назначения горожанина
var _id_rng        := RandomNumberGenerator.new()
var _last_infector := -3                  # выставлять перед каждым _infect()

var _grid := {}

signal run_finished(result: int, seconds: float)
signal escalation_triggered(level: int, headline: String)
signal stats_changed(healthy: int, infected: int, latent: int, dead: int, cops: int, suspicion: float, arrest_prog: float, qte_key: String, evac_count: int)
signal shot_fired(from_pos: Vector2, to_pos: Vector2, is_swat_shot: bool)
signal mutation_available(options: Array)
signal horde_commanded(world_pos: Vector2)
signal bark_event(agent: int, cat: String, pos2: Vector2, fl: int)
signal blood_hit(at: Vector2, fl: int, lethal: bool, direction: Vector2)
signal visuals_reset


func _ready() -> void:
	reset_run()


func reset_run() -> void:
	visuals_reset.emit()
	var n := Tuning.AGENT_COUNT
	pos.resize(n);         vel.resize(n);         state.resize(n)
	timer.resize(n);       resist.resize(n);      grab_target.resize(n)
	grab_prog.resize(n);   panic.resize(n);       facing.resize(n)
	alert.resize(n);       alert_target.resize(n); was_cop.resize(n)
	floor_idx.resize(n);   floor_cd.resize(n);    health.resize(n)
	is_swat.resize(n)
	archetype.resize(n);   infect_thresh.resize(n); photo_timer.resize(n)
	has_phone.resize(n);   phone_timer.resize(n)
	is_bus_driver.resize(n)
	infected_by.resize(n); infected_at.resize(n)
	infected_where.resize(n); spread_count.resize(n)
	dest.resize(n)
	identities.clear();    identities.resize(n)
	survivor_role.resize(n);   survivor_role.fill(0)
	following_org.resize(n);   following_org.fill(-1)
	following_org_t.resize(n); following_org_t.fill(0.0)
	org_rally_t.resize(n);     org_rally_t.fill(0.0)
	_id_rng.randomize()
	_last_infector = -3

	MapGen.generate()

	# -------- распределение агентов --------
	# 50 — улица, 200 — ТЦ, остальные — интерьеры зданий
	var mall_per_floor  := Tuning.MALL_AGENTS_PER_FLOOR
	var mall_total      := mall_per_floor * Tuning.MALL_FLOORS   # 200
	var street_total    := Tuning.STREET_AGENTS                  # 50
	var building_total  := n - mall_total - street_total         # 250

	var out_pts: Array = Array(MapGen.spawn_points)
	out_pts.shuffle()
	var mall_spawn_sets: Array = []
	for points in MapGen.mall_spawns:
		var shuffled: Array = Array(points)
		shuffled.shuffle()
		mall_spawn_sets.append(shuffled)
	# Собираем все точки спавна зданий в один плоский список {fl, pt}
	var bld_pts: Array = []
	for bslot: Dictionary in MapGen.building_spawns:
		var fid: int = bslot["floor_id"]
		for bp: Vector2 in bslot["points"]:
			bld_pts.append({"fl": fid, "pt": bp})
	bld_pts.shuffle()

	for i in n:
		var fl    := 0
		var pt    := Vector2.ZERO

		if i < mall_total:
			fl = (i / mall_per_floor) + 1   # этажи 1..MALL_FLOORS
			var mall_pts: Array = mall_spawn_sets[fl - 1]
			if mall_pts.size() > 0:
				pt = mall_pts[(i % mall_per_floor) % mall_pts.size()]
			else:
				pt = MapGen.mall_interior.get_center()
		elif i < mall_total + building_total:
			# Здание
			if bld_pts.size() > 0:
				var slot: Dictionary = bld_pts[(i - mall_total) % bld_pts.size()]
				fl = slot["fl"]
				pt = slot["pt"]
			else:
				var oi := (i - mall_total) % out_pts.size()
				pt = out_pts[oi] if out_pts.size() > 0 else Vector2.ZERO
		else:
			# Улица
			var si := (i - mall_total - building_total) % out_pts.size()
			pt = out_pts[si] if out_pts.size() > 0 else Vector2.ZERO

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
		infected_by[i]    = -3
		infected_at[i]    = 0.0
		infected_where[i] = Vector2.ZERO
		spread_count[i]   = 0
		dest[i]           = Vector2.ZERO  # будет выбрана в первом тике
		identities[i]     = Identity.generate(_id_rng, arch, false)

	# -------- роли выживших --------
	for i in n:
		if state[i] != S.HEALTHY or archetype[i] == Tuning.ARCH_CHILD:
			continue
		var r := randf()
		if r < Tuning.SURV_PANICKER_CHANCE:
			survivor_role[i] = Tuning.SURV_PANICKER
			# panic НЕ выставляем сразу — паникёр спокоен до первого триггера,
			# но после него уже никогда не успокаивается (в _tick_civilian)
		elif r < Tuning.SURV_PANICKER_CHANCE + Tuning.SURV_HIDER_CHANCE:
			survivor_role[i] = Tuning.SURV_HIDER
		elif r < Tuning.SURV_PANICKER_CHANCE + Tuning.SURV_HIDER_CHANCE + Tuning.SURV_ORGANIZER_CHANCE:
			survivor_role[i] = Tuning.SURV_ORGANIZER

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
	p_health          = Tuning.AGENT_HEALTH
	p_being_arrested  = false
	p_arrest_timer    = 0.0
	_arresting_cop    = -1
	p_qte_key         = KEY_NONE
	p_qte_key_str     = ""
	_qte_timer        = 0.0
	_slider_pos    = 0.5
	_slider_dir    = 1.0
	_resist_gather = 0.0
	_player_knock  = Vector2.ZERO
	_throw_cd      = 0.0
	_grab_cd       = 0.0
	suspicion         = 0.0
	elapsed          = 0.0
	cop_count        = 0
	cop_spawn_t      = 0.0
	finished         = 0
	horde_cmd          = HC_NONE
	horde_target       = Vector2.ZERO
	horde_target_life  = 0.0
	horde_target_agent = -1
	horde_floor        = 0
	evac_timer        = Tuning.EVAC_FIRST_TIME
	evac_count        = 0
	evac_points.clear()
	_evac_announced   = false
	active_mutations.clear()
	active_syntheses.clear()
	route_buses.clear()
	_next_mut_at      = Tuning.MUT_THRESHOLD
	_pending_mutation = false
	grab_range_eff    = Tuning.GRAB_RANGE
	incubation_eff    = Tuning.INCUBATION
	_backstab_applied = false
	escalation_level  = 0
	_esc_checked      = [false, false, false]
	_infected_frac    = 0.0
	_build_bus_routes()


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
	_tick_route_buses(delta)
	var susp_decay_mult := Tuning.SYN_SHADOW_SUSP_MULT if Tuning.SYN_SHADOW in active_syntheses else 1.0
	suspicion = clampf(suspicion - Tuning.SUSP_DECAY * susp_decay_mult * delta, 0.0, 100.0)


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
		var pick: Array = _QTE_ALL[randi() % _QTE_ALL.size()]
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
	_grab_cd          = maxf(0.0, _grab_cd  - delta)

	# FOLLOW: цель = позиция игрока, обновляется каждый кадр
	if horde_cmd == HC_FOLLOW:
		horde_target      = p_pos
		horde_target_life = Tuning.HORDE_CMD_DURATION
		horde_floor       = p_floor
	elif horde_cmd == HC_HOLD:
		horde_target_life = Tuning.HORDE_CMD_DURATION   # HOLD не истекает само по себе
	else:
		horde_target_life = maxf(0.0, horde_target_life - delta)
		if horde_target_life <= 0.0:
			horde_cmd = HC_NONE

	# WASD-движение; мышь задаёт только направление взгляда
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): dir.y -= 1.0
	if Input.is_key_pressed(KEY_S): dir.y += 1.0
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0
	if dir.length_squared() > 0.01:
		dir = dir.normalized()
		var active_camera: Camera3D = get_viewport().get_camera_3d()
		if active_camera != null:
			dir = dir.rotated(-active_camera.global_rotation.y)

	var speed := Tuning.PLAYER_SPRINT if sprinting else Tuning.PLAYER_WALK
	if p_grab >= 0:
		speed *= 0.35

	p_vel = p_vel.move_toward(dir * speed, Tuning.ACCEL * delta)
	_player_knock = _player_knock.move_toward(Vector2.ZERO, 14.0 * delta)
	var p_intended := p_pos + (p_vel + _player_knock) * delta
	p_pos = MapGen.push_out(p_intended, 0.35, p_floor)
	if p_floor == 0:
		p_pos = _clamp_world(p_pos)
	var p_corr := p_pos - p_intended
	if p_corr.length_squared() > 0.0001:
		var wn := p_corr.normalized()
		p_vel = p_vel - minf(0.0, p_vel.dot(wn)) * wn

	# Переход между этажами
	if p_floor_cd <= 0.0:
		var tr := MapGen.check_transition(p_pos, p_floor)
		if not tr.is_empty():
			p_floor    = tr["to_floor"]
			p_pos      = tr["dest"]
			p_floor_cd = Tuning.FLOOR_CD

	# Начать захват
	if holding and p_grab < 0 and _grab_cd <= 0.0:
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
			_slider_pos = randf()
			_slider_dir = 1.0 if randf() > 0.5 else -1.0
			bark_event.emit(best, "grabbed", pos[best], p_floor)
			# MUT_BACKSTAB: жертва спиной — сужаем "вырвался" до нуля
			if Tuning.MUT_BACKSTAB in active_mutations:
				var to_player := (p_pos - pos[best]).normalized()
				var vf := Vector2(cos(facing[best]), sin(facing[best]))
				if to_player.dot(vf) < -0.4:
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
			# Шкала: ползунок двигается, Space = выбор исхода
			if p_grab >= 0:
				var arch := archetype[p_grab] if p_grab < archetype.size() else 0
				var spd: float = Tuning.SLIDER_SPEED_BASE * float(Tuning.SLIDER_SPEED_ARCH[arch])
				if _resist_gather >= Tuning.RESIST_ATTACK_DELAY * 0.5:
					spd *= Tuning.SLIDER_SPEED_RESIST
				_slider_pos += _slider_dir * spd * delta
				if _slider_pos >= 1.0:
					_slider_pos = 1.0; _slider_dir = -1.0
				elif _slider_pos <= 0.0:
					_slider_pos = 0.0; _slider_dir = 1.0
				_check_resisters(delta)


func _break_grab(scream: bool) -> void:
	if p_grab >= 0:
		var v   := p_grab
		var away := pos[v] - p_pos
		if away.length() < 0.01:
			away = Vector2.RIGHT.rotated(randf() * TAU)
		vel[v]   = away.normalized() * Tuning.KNOCKBACK_SPEED
		panic[v] = Tuning.PANIC_MEMORY
		if scream and p_prog > 0.3:
			suspicion += Tuning.SUSP_GRAB_FAIL
			bark_event.emit(v, "broke_free", pos[v], floor_idx[v])
	p_grab            = -1
	p_prog            = 0.0
	_backstab_applied = false
	_slider_pos    = 0.5
	_slider_dir    = 1.0
	_resist_gather = 0.0
	_grab_cd       = 0.45   # 0.45с до следующего захвата — не прыгаем в толпе


func _resolve_slider() -> void:
	if p_grab < 0: return
	var sl := _slider_pos
	# Backstab значительно сужает зону "вырвался"
	var esc_end   := 0.04 if _backstab_applied else Tuning.SLIDER_ESCAPE_END
	var kill_start := 0.96 if _backstab_applied else Tuning.SLIDER_KILL_START
	if sl <= esc_end:
		# ВЫРВАЛСЯ
		_break_grab(true)
	elif sl <= kill_start:
		# ЗАРАЗИЛСЯ
		var help := _count_helpers(p_grab)
		suspicion += Tuning.SUSP_GRAB_SEEN if help > 0 else 1.0
		_last_infector = -1
		_infect(p_grab)
		p_grab = -1; p_prog = 0.0
		_slider_pos = 0.5; _slider_dir = 1.0; _resist_gather = 0.0
		_backstab_applied = false
		_try_auto_grab()
	else:
		# УБИТ
		var v := p_grab
		blood_hit.emit(pos[v], floor_idx[v], true, (pos[v] - p_pos).normalized(), 1)
		state[v] = S.DEAD
		vel[v]   = Vector2.ZERO
		suspicion = minf(100.0, suspicion + Tuning.SUSP_KILL_CIV)
		p_grab = -1; p_prog = 0.0
		_slider_pos = 0.5; _slider_dir = 1.0; _resist_gather = 0.0
		_backstab_applied = false


func _check_resisters(delta: float) -> void:
	# Только BRUTE и NORMAL нападают; один заражённый рядом — все разбегаются
	var inf_nearby := false
	var att_count  := 0
	var attackers: Array[int] = []
	for nb in _neighbors(p_pos, p_floor):
		if floor_idx[nb] != p_floor: continue
		var st := state[nb]
		if st == S.INFECTED or st == S.INFECTED_COP:
			if pos[nb].distance_to(p_pos) < Tuning.RESIST_INF_SUPPRESS:
				inf_nearby = true; break
		elif st == S.HEALTHY:
			var arch := archetype[nb]
			if arch == Tuning.ARCH_BRUTE or arch == Tuning.ARCH_NORMAL:
				if pos[nb].distance_to(p_pos) < Tuning.RESIST_ATT_RADIUS:
					att_count += 1
					attackers.append(nb)
	if inf_nearby or att_count < Tuning.RESIST_MIN_CIV:
		_resist_gather = 0.0; return
	_resist_gather += delta
	if _resist_gather < Tuning.RESIST_ATTACK_DELAY: return
	_resist_gather = 0.0
	# Атака!
	var att := attackers[randi() % attackers.size()]
	vel[att] = (p_pos - pos[att]).normalized() * 4.5
	_player_knock = (p_pos - pos[att]).normalized() * Tuning.RESIST_PUSH_SPEED
	suspicion = minf(100.0, suspicion + Tuning.RESIST_SUSP_BOOST)
	bark_event.emit(att, "spot_infected", pos[att], floor_idx[att])
	_break_grab(false)
	if randf() < Tuning.RESIST_INFECT_PROB:
		_last_infector = -2
		_infect(att)


func _try_auto_grab() -> void:
	if Tuning.MUT_AUTO_GRAB not in active_mutations or p_grab >= 0:
		return
	var r2 := grab_range_eff * 4.0 * grab_range_eff * 4.0
	# ХИЩНЫЙ РЕФЛЕКС: предпочитаем цели спиной, сразу применяем backstab
	if Tuning.SYN_PREDATOR in active_syntheses:
		for nb in _neighbors(p_pos, p_floor):
			if (state[nb] == S.HEALTHY or state[nb] == S.COP) and floor_idx[nb] == p_floor:
				if pos[nb].distance_squared_to(p_pos) < r2:
					var to_player := (p_pos - pos[nb]).normalized()
					var vf := Vector2(cos(facing[nb]), sin(facing[nb]))
					if to_player.dot(vf) < -0.4:   # жертва стоит спиной
						p_grab = nb; p_prog = 0.0; _backstab_applied = true
						_slider_pos = 0.02  # почти сразу в зоне "заразился"
						_slider_dir = 1.0
						return
	# Обычный автозахват — просто ближайший
	var best   := -1
	var best_d := r2
	for nb in _neighbors(p_pos, p_floor):
		if (state[nb] == S.HEALTHY or state[nb] == S.COP) and floor_idx[nb] == p_floor:
			var da := pos[nb].distance_squared_to(p_pos)
			if da < best_d:
				best_d = da
				best   = nb
	if best >= 0:
		p_grab = best; p_prog = 0.0; _backstab_applied = false
		_slider_pos = randf(); _slider_dir = 1.0 if randf() > 0.5 else -1.0


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
	infected_by[i]    = _last_infector
	infected_at[i]    = elapsed
	infected_where[i] = pos[i]
	if _last_infector >= 0:
		spread_count[_last_infector] += 1
	_last_infector = -3
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
	if available.is_empty():
		_pending_mutation = false
		return
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
	_check_syntheses()


func _check_syntheses() -> void:
	_try_activate_syn(Tuning.SYN_SHADOW,      Tuning.MUT_SILENT_REVEAL,   Tuning.MUT_SILENT_SPRINT)
	_try_activate_syn(Tuning.SYN_BLACK_DEATH, Tuning.MUT_CROWD_SPREAD,    Tuning.MUT_FAST_INCUBATION)
	_try_activate_syn(Tuning.SYN_LIVING_BOMB, Tuning.MUT_AUTO_GRAB,       Tuning.MUT_FAST_INCUBATION)
	_try_activate_syn(Tuning.SYN_PREDATOR,    Tuning.MUT_BACKSTAB,        Tuning.MUT_AUTO_GRAB)
	_try_activate_syn(Tuning.SYN_SWARM,       Tuning.MUT_AUTO_GRAB,       Tuning.MUT_CROWD_SPREAD)


func _try_activate_syn(syn_id: int, mut_a: int, mut_b: int) -> void:
	if syn_id in active_syntheses: return
	if mut_a not in active_mutations or mut_b not in active_mutations: return
	active_syntheses.append(syn_id)
	escalation_triggered.emit(-2, "СИНТЕЗ: " + Tuning.SYN_NAMES[syn_id] + " — " + Tuning.SYN_DESC[syn_id])


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

		var intended := pos[i] + vel[i] * delta
		pos[i] = MapGen.push_out(intended, 0.35, floor_idx[i])
		if floor_idx[i] == 0:
			pos[i] = _clamp_world(pos[i])
		var correction := pos[i] - intended
		if correction.length_squared() > 0.0001:
			var wn := correction.normalized()
			vel[i] = vel[i] - minf(0.0, vel[i].dot(wn)) * wn

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
	# BLACK_DEATH расширяет это на носителей в инкубации (вдвое медленнее)
	if Tuning.MUT_CROWD_SPREAD in active_mutations:
		var black_death := Tuning.SYN_BLACK_DEATH in active_syntheses
		var to_infect: Array = []   # pairs [victim, infector]
		for i in pos.size():
			var is_active := state[i] == S.INFECTED or state[i] == S.INFECTED_COP
			var is_latent := state[i] == S.LATENT and black_death
			if not (is_active or is_latent):
				continue
			var rate := 0.04 if is_active else 0.02
			for nb in _neighbors(pos[i], floor_idx[i]):
				if (state[nb] == S.HEALTHY or state[nb] == S.COP) and floor_idx[nb] == floor_idx[i]:
					if pos[nb].distance_squared_to(pos[i]) < 2.5 * 2.5:
						grab_prog[nb] += rate * delta
						if grab_prog[nb] >= 1.0:
							grab_prog[nb] = 0.0
							to_infect.append([nb, i])
		for pair in to_infect:
			_last_infector = pair[1]
			_infect(pair[0])

	# Проверка порога мутации
	var total_infected := infected + latent + dead
	if total_infected >= _next_mut_at and not _pending_mutation:
		_next_mut_at += Tuning.MUT_THRESHOLD
		_pending_mutation = true
		_offer_mutations()

	# Проверка порогов эскалации
	var total_agents := pos.size()
	var infected_frac := float(infected + latent + dead) / float(total_agents) if total_agents > 0 else 0.0
	_infected_frac = infected_frac
	for ei in Tuning.ESC_THRESHOLDS.size():
		if not _esc_checked[ei] and infected_frac >= Tuning.ESC_THRESHOLDS[ei]:
			_esc_checked[ei] = true
			escalation_level = ei + 1
			cop_spawn_t      = 0.0
			escalation_triggered.emit(escalation_level, Tuning.ESC_HEADLINES_RU[ei])

	var got := infected + dead
	var arrest_prog := p_arrest_timer / Tuning.ARREST_TIME if p_being_arrested else 0.0
	stats_changed.emit(healthy, infected, latent, dead, cops, suspicion, arrest_prog,
		p_qte_key_str if p_being_arrested else "", evac_count)
	if pos.size() > 0 and float(got) / float(pos.size()) >= Tuning.WIN_RATIO:
		finished = 1
		run_finished.emit(1, elapsed)


func _tick_latent(i: int, delta: float) -> void:
	_wander(i, delta, Tuning.CIV_WALK)
	timer[i] -= delta
	if timer[i] <= 0.0:
		# ЖИВАЯ БОМБА: тихое заражение ближайшей цели прямо перед вскрытием
		if Tuning.SYN_LIVING_BOMB in active_syntheses:
			var bomb_t := _nearest(pos[i], floor_idx[i], [S.HEALTHY, S.COP], 4.0)
			if bomb_t >= 0:
				_last_infector = i
				_infect(bomb_t)
				bark_event.emit(bomb_t, "grabbed", pos[bomb_t], floor_idx[i])
		state[i] = S.INFECTED_COP if was_cop[i] == 1 else S.INFECTED
		if Tuning.MUT_SILENT_REVEAL not in active_mutations:
			suspicion += Tuning.SUSP_REVEAL
			panic[i]   = Tuning.PANIC_MEMORY


func _nearest(origin: Vector2, fl: int, states: Array, radius: float) -> int:
	var best := -1
	var best_d := radius * radius
	for nb in _neighbors(origin, fl):
		if floor_idx[nb] != fl: continue
		if state[nb] not in states: continue
		var d2 := origin.distance_squared_to(pos[nb])
		if d2 < best_d:
			best_d = d2
			best   = nb
	return best


func _tick_infected(i: int, delta: float) -> void:
	var is_cop := state[i] == S.INFECTED_COP
	var speed  := Tuning.INFECTED_COP_SPEED if is_cop else Tuning.INFECTED_SPEED

	if grab_target[i] >= 0:
		var v := grab_target[i]
		if (state[v] != S.HEALTHY and state[v] != S.COP) or floor_idx[v] != floor_idx[i] \
				or pos[v].distance_to(pos[i]) > Tuning.GRAB_BREAK_RANGE:
			grab_target[i] = -1
			grab_prog[i]   = 0.0
		else:
			pos[v] = pos[v].lerp(pos[i], 1.0 - exp(-5.0 * delta))
			var base := Tuning.GRAB_TIME * resist[v] * (0.6 if is_cop else 1.3)
			grab_prog[i] += delta / base
			vel[i] = vel[i].move_toward(Vector2.ZERO, Tuning.ACCEL * delta)
			if grab_prog[i] >= 1.0:
				_last_infector = i
				_infect(v)
				grab_target[i] = -1
				grab_prog[i]   = 0.0
			return

	# Помощь орды: если игрока арестовывают — бежим к копу и хватаем его
	if p_being_arrested and _arresting_cop >= 0 and grab_target[i] < 0:
		var cop_fl := floor_idx[_arresting_cop]
		if floor_idx[i] == cop_fl:
			var d_cop := pos[i].distance_to(pos[_arresting_cop])
			if d_cop < Tuning.COP_RESCUE_RADIUS:
				if d_cop < Tuning.GRAB_RANGE * 1.8:
					grab_target[i] = _arresting_cop
					grab_prog[i]   = maxf(grab_prog[i], 0.15)
				else:
					var to_cop := pos[_arresting_cop] - pos[i]
					vel[i] = vel[i].move_toward(to_cop.normalized() * speed * 1.3, Tuning.ACCEL * delta)
				return

	# Мягкое расталкивание между заражёнными (против скучивания)
	var repulse := Vector2.ZERO
	for nb in _neighbors(pos[i], floor_idx[i]):
		if nb == i or floor_idx[nb] != floor_idx[i]: continue
		if state[nb] != S.INFECTED and state[nb] != S.INFECTED_COP: continue
		var rd := pos[i] - pos[nb]
		var rl := rd.length()
		if rl < Tuning.HORDE_SCATTER_DIST and rl > 0.01:
			repulse += rd.normalized() * (Tuning.HORDE_SCATTER_DIST - rl)
	if repulse.length_squared() > 0.001:
		vel[i] = (vel[i] + repulse * 0.4).limit_length(speed * 1.3)

	# --- Команды орды ---
	if horde_target_life > 0.0 and floor_idx[i] == horde_floor:
		match horde_cmd:

			HC_FOLLOW:
				# Кольцо вокруг игрока (золотое сечение → равномерное распределение)
				var angle := fposmod(float(i) * 2.399, TAU)
				var follow_pos := p_pos + Vector2.RIGHT.rotated(angle) * Tuning.HORDE_FOLLOW_DIST
				var to_f := follow_pos - pos[i]
				if to_f.length() > 1.5:
					vel[i] = vel[i].lerp(to_f.normalized() * speed, 0.12)
				else:
					vel[i] = vel[i].move_toward(Vector2.ZERO, Tuning.ACCEL * delta)
				_try_grab_nearby(i)
				return

			HC_HOLD:
				# Рассредоточиться по зоне и хватать входящих
				var angle := fposmod(float(i) * 2.399, TAU)
				var hold_pos := horde_target + Vector2.RIGHT.rotated(angle) * Tuning.HORDE_HOLD_RADIUS * 0.6
				var to_h := hold_pos - pos[i]
				if to_h.length() > 2.0:
					vel[i] = vel[i].lerp(to_h.normalized() * speed * 0.55, 0.08)
				else:
					vel[i] = vel[i].move_toward(Vector2.ZERO, Tuning.ACCEL * delta)
				_try_grab_nearby(i)
				return

			HC_MOVE, HC_ATTACK:
				var move_to := horde_target
				if horde_target_agent >= 0:
					var ta := horde_target_agent
					if state[ta] == S.HEALTHY or state[ta] == S.COP:
						move_to = pos[ta]
					else:
						horde_target_agent = -1
				var to_target := move_to - pos[i]
				if to_target.length() > Tuning.HORDE_ARRIVE_DIST:
					vel[i] = vel[i].lerp(to_target.normalized() * speed, 0.12)
					_try_grab_nearby(i)
					return

	# --- Автономный приоритет: коп > изолированный > ближайший ---
	var target := _choose_auto_target(i)
	if target >= 0:
		var to := pos[target] - pos[i]
		vel[i] = vel[i].move_toward(to.normalized() * speed, Tuning.ACCEL * delta)
		if to.length() < Tuning.GRAB_RANGE:
			grab_target[i] = target
			grab_prog[i]   = 0.0
	else:
		_wander(i, delta, speed * 0.5)


func _try_grab_nearby(i: int) -> void:
	for nb in _neighbors(pos[i], floor_idx[i]):
		if (state[nb] == S.HEALTHY or state[nb] == S.COP) and floor_idx[nb] == floor_idx[i]:
			if pos[nb].distance_squared_to(pos[i]) < grab_range_eff * grab_range_eff:
				grab_target[i] = nb
				grab_prog[i]   = 0.0
				return


func _choose_auto_target(i: int) -> int:
	var fl := floor_idx[i]
	var pi := pos[i]

	# Приоритет 1: коп / SWAT (ценная цель — быстрее, лучше заражает)
	var best_cop := -1
	var best_cop_d := 20.0 * 20.0
	for nb in _neighbors(pi, fl):
		if state[nb] != S.COP or floor_idx[nb] != fl: continue
		var d2 := pi.distance_squared_to(pos[nb])
		if d2 < best_cop_d and not _target_overcrowded(nb, i):
			best_cop_d = d2
			best_cop   = nb
	if best_cop >= 0:
		return best_cop

	# Приоритет 2: изолированный горожанин (меньше соседей = безопаснее хватать)
	var best   := -1
	var best_s := -INF
	for nb in _neighbors(pi, fl):
		if state[nb] != S.HEALTHY or floor_idx[nb] != fl: continue
		var d := pi.distance_to(pos[nb])
		if d > 25.0: continue
		if _target_overcrowded(nb, i): continue
		var iso   := _count_healthy_near(nb, fl, 5.0)
		var score := -d - iso * 2.5
		if score > best_s:
			best_s = score
			best   = nb
	return best


func _target_overcrowded(target: int, exclude: int) -> bool:
	if Tuning.SYN_SWARM in active_syntheses:
		return false   # РОЕВОЙ РАЗУМ: лимит снят
	var r2  := (Tuning.GRAB_RANGE * 4.0) * (Tuning.GRAB_RANGE * 4.0)
	var cnt := 0
	for nb in _neighbors(pos[target], floor_idx[target]):
		if nb == exclude: continue
		if state[nb] != S.INFECTED and state[nb] != S.INFECTED_COP: continue
		if floor_idx[nb] != floor_idx[target]: continue
		if pos[nb].distance_squared_to(pos[target]) < r2:
			cnt += 1
			if cnt >= Tuning.HORDE_MAX_PER_TARGET:
				return true
	return false


func _count_healthy_near(target: int, fl: int, radius: float) -> int:
	var r2  := radius * radius
	var cnt := 0
	for nb in _neighbors(pos[target], fl):
		if state[nb] == S.HEALTHY and floor_idx[nb] == fl:
			if pos[nb].distance_squared_to(pos[target]) < r2:
				cnt += 1
	return cnt


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
				timer[i] = Tuning.COP_SHOOT_CD
				var swat_shot := is_swat[i] == 1
				var hs_chance := Tuning.HEADSHOT_CHANCE_SWAT if swat_shot else Tuning.HEADSHOT_CHANCE_COP
				shot_fired.emit(pos[i], pos[t], swat_shot)
				bark_event.emit(i, "cop_shoot", pos[i], floor_idx[i])
				if randf() < hs_chance:
					state[t] = S.DEAD   # хедшот — мгновенная смерть
					health[t] = 0
					blood_hit.emit(pos[t], floor_idx[t], true, (pos[t] - pos[i]).normalized())
				else:
					health[t] = maxi(1, health[t] - 1)   # тело — минимум 1 HP
					blood_hit.emit(pos[t], floor_idx[t], false, (pos[t] - pos[i]).normalized())
		else:
			alert[i] = 0.0

	var hunt_thresh := Tuning.SYN_SHADOW_HUNT_THRESH if Tuning.SYN_SHADOW in active_syntheses else Tuning.SUSP_HUNT_PLAYER
	if suspicion > hunt_thresh \
			and floor_idx[i] == p_floor \
			and p_pos.distance_to(pos[i]) < Tuning.COP_VIEW_DIST:
		goal = p_pos
		var pdist := p_pos.distance_to(pos[i])
		if suspicion >= Tuning.SUSP_SHOOT_PLAYER:
			# Подозрение критическое — игрок явно заражён, стреляем
			if timer[i] <= 0.0 and pdist < Tuning.COP_SHOOT_RANGE:
				timer[i] = Tuning.COP_SHOOT_CD
				var swat_shot := is_swat[i] == 1
				shot_fired.emit(pos[i], p_pos, swat_shot)
				bark_event.emit(i, "cop_shoot", pos[i], floor_idx[i])
				p_health -= 1
				if p_health <= 0:
					finished = 2
					run_finished.emit(2, elapsed)
		elif pdist < Tuning.COP_ARREST_RANGE and not p_being_arrested:
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
	# Водитель автобуса — его позицией управляет _tick_route_buses
	if is_bus_driver[i] == 1:
		return

	# --- Организатор: периодически собирает группу и ведёт к автобусу ---
	if survivor_role[i] == Tuning.SURV_ORGANIZER and state[i] == S.HEALTHY:
		org_rally_t[i] = maxf(0.0, org_rally_t[i] - delta)
		if org_rally_t[i] <= 0.0:
			org_rally_t[i] = Tuning.ORGANIZER_RALLY_INTERVAL
			var rallied := 0
			for nb in _neighbors(pos[i], floor_idx[i]):
				if nb == i or state[nb] != S.HEALTHY: continue
				if survivor_role[nb] == Tuning.SURV_HIDER: continue
				if pos[i].distance_squared_to(pos[nb]) < Tuning.ORGANIZER_RALLY_RAD * Tuning.ORGANIZER_RALLY_RAD:
					following_org[nb]   = i
					following_org_t[nb] = Tuning.ORGANIZER_FOLLOW_TIME
					rallied += 1
					if rallied >= 4: break
			if rallied > 0:
				bark_event.emit(i, "evac_call", pos[i], floor_idx[i])
		# Организатор сам тоже паникует в сторону автобуса
		panic[i] = maxf(panic[i], Tuning.PANIC_MEMORY)

	# --- Следование за организатором ---
	if following_org[i] >= 0 and state[i] == S.HEALTHY:
		following_org_t[i] -= delta
		var oi := following_org[i]
		if following_org_t[i] <= 0.0 or state[oi] != S.HEALTHY or floor_idx[oi] != floor_idx[i]:
			following_org[i] = -1  # организатор исчез — возврат к нормальному ИИ
		else:
			panic[i] = maxf(panic[i], Tuning.PANIC_MEMORY)
			var to_org := pos[oi] - pos[i]
			if to_org.length() > 1.5:
				vel[i] = vel[i].move_toward(to_org.normalized() * Tuning.CIV_PANIC, Tuning.ACCEL * delta)
				return  # движемся к организатору, остальной ИИ пропускаем
			# Догнали организатора — падаем в нормальный тик (эвакуация обработается ниже)

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
						var edge := Tuning.COP_STATION_POS + Vector2(
							randf_range(-Tuning.COP_STATION_RADIUS, Tuning.COP_STATION_RADIUS),
							randf_range(-Tuning.COP_STATION_RADIUS, Tuning.COP_STATION_RADIUS))
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

	# Эвакуация: только паникующие агенты бегут к автобусу (тихушники — никогда)
	var going_to_evac := false
	if state[i] == S.HEALTHY and panic[i] > 0.0 and floor_idx[i] == 0 \
			and not evac_points.is_empty() and survivor_role[i] != Tuning.SURV_HIDER:
		var nearest_evac := Vector2.ZERO
		var best_ep: Dictionary = {}
		var nearest_d    := INF
		for ep in evac_points:
			# Игрок у автобуса — агенты его боятся, ищут другой
			if p_pos.distance_squared_to(ep["pos"]) < Tuning.EVAC_PLAYER_BLOCK_R * Tuning.EVAC_PLAYER_BLOCK_R:
				continue
			var d2 := pos[i].distance_squared_to(ep["pos"])
			if d2 < nearest_d:
				nearest_d    = d2
				nearest_evac = ep["pos"]
				best_ep      = ep
		if not best_ep.is_empty():
			var to_evac   := nearest_evac - pos[i]
			var dist_evac := to_evac.length()
			if dist_evac < Tuning.EVAC_RADIUS:
				if best_ep["board_cd"] <= 0.0:
					state[i]   = S.DEAD
					evac_count += 1
					best_ep["board_cd"] = Tuning.EVAC_BOARD_INTERVAL
					if evac_count >= Tuning.EVAC_LOSE_AT and finished == 0:
						finished = 3
						run_finished.emit(3, elapsed)
					return
			else:
				going_to_evac = true
				bark_event.emit(i, "evac_call", pos[i], floor_idx[i])
				var evac_spd : float = Tuning.CIV_PANIC * Tuning.ARCH_PANIC_MULT[archetype[i]]
				vel[i] = vel[i].lerp((to_evac / dist_evac) * evac_spd, 0.15)

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
		var panic_set := Tuning.PANIC_MEMORY * \
			(Tuning.HIDER_PANIC_RATE if survivor_role[i] == Tuning.SURV_HIDER else 1.0)
		panic[i] = maxf(panic[i], panic_set)

	if going_to_evac:
		panic[i] = maxf(0.0, panic[i] - delta)
	elif panic[i] > 0.0:
		if survivor_role[i] != Tuning.SURV_PANICKER:  # паникёр не успокаивается
			panic[i] -= delta
		var panic_spd: float = Tuning.CIV_PANIC * Tuning.ARCH_PANIC_MULT[archetype[i]]
		if flee.length_squared() > 0.001:
			vel[i] = vel[i].move_toward(flee.normalized() * panic_spd, Tuning.ACCEL * delta)
		else:
			vel[i] = vel[i].move_toward(vel[i].normalized() * panic_spd, Tuning.ACCEL * delta)
	elif p_grab == i:
		vel[i] = vel[i].move_toward(Vector2.ZERO, Tuning.KNOCKBACK_DECAY * delta)
	elif calling:
		vel[i] = vel[i].move_toward(Vector2.ZERO, Tuning.ACCEL * delta)
	elif not going_to_evac:
		_walk_to_dest(i, delta)


func _pick_dest(i: int) -> void:
	var fl := floor_idx[i]
	if fl == 0:
		var pts := MapGen.spawn_points
		if pts.size() > 0:
			dest[i] = pts[randi() % pts.size()]
	elif fl <= Tuning.MALL_FLOORS:
		var mi := fl - 1
		if mi < MapGen.mall_spawns.size():
			var pts: Array = MapGen.mall_spawns[mi]
			if pts.size() > 0:
				dest[i] = pts[randi() % pts.size()]
				return
		dest[i] = MapGen.mall_interior.get_center()
	else:
		if MapGen.interior_by_floor.has(fl):
			var r: Rect2 = MapGen.interior_by_floor[fl]
			dest[i] = Vector2(
				randf_range(r.position.x + 1.0, r.end.x - 1.0),
				randf_range(r.position.y + 1.0, r.end.y - 1.0))
		else:
			dest[i] = pos[i]


func _walk_to_dest(i: int, delta: float) -> void:
	if dest[i] == Vector2.ZERO:
		_pick_dest(i)
		return
	var to_dest := dest[i] - pos[i]
	if to_dest.length_squared() < 2.25:   # прибыл (1.5м)
		_pick_dest(i)
		return
	var want_dir := to_dest.normalized()
	# Если прямо стена — попробовать обойти влево или вправо
	var ahead := pos[i] + want_dir * 2.0
	if MapGen.is_blocked(ahead, 0.3, floor_idx[i]):
		var left  := want_dir.rotated(-PI * 0.4)
		var right := want_dir.rotated(PI * 0.4)
		var la    := pos[i] + left * 2.0
		var ra    := pos[i] + right * 2.0
		if not MapGen.is_blocked(la, 0.3, floor_idx[i]):
			want_dir = left
		elif not MapGen.is_blocked(ra, 0.3, floor_idx[i]):
			want_dir = right
		else:
			_pick_dest(i)   # зашли в тупик — сменить цель
			return
	var spd: float = float(Tuning.CIV_WALK) * float(Tuning.ARCH_PANIC_MULT[archetype[i]])
	vel[i] = vel[i].move_toward(want_dir * spd, Tuning.ACCEL * 0.5 * delta)
	facing[i] = want_dir.angle()


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


func _spawn_cops(delta: float) -> void:
	var esc_idx  := clampi(escalation_level - 1, 0, Tuning.ESC_SPAWN_MULTS.size() - 1)
	var spawn_cd: float = Tuning.COP_SPAWN_INTERVAL * (Tuning.ESC_SPAWN_MULTS[esc_idx] if escalation_level > 0 else 1.0)
	var cop_max: int  = Tuning.ESC_COP_MAXES[esc_idx] if escalation_level > 0 else Tuning.COP_MAX
	if _infected_frac < Tuning.COP_SPAWN_MIN_INFECTION:
		return
	if suspicion < Tuning.SUSP_COP_SPAWN or cop_count >= cop_max:
		return
	cop_spawn_t -= delta
	if cop_spawn_t > 0.0:
		return
	cop_spawn_t = spawn_cd
	var edge := Tuning.COP_STATION_POS + Vector2(
		randf_range(-Tuning.COP_STATION_RADIUS, Tuning.COP_STATION_RADIUS),
		randf_range(-Tuning.COP_STATION_RADIUS, Tuning.COP_STATION_RADIUS))
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
				resist[i]        = 2.0
				infect_thresh[i] = Tuning.ARCH_THRESH[Tuning.ARCH_NORMAL] * Tuning.SWAT_GRAB_MULT
			identities[i] = Identity.generate(_id_rng, Tuning.ARCH_NORMAL, true)
			return


func _tick_evac(delta: float) -> void:
	var i := evac_points.size() - 1
	while i >= 0:
		evac_points[i]["life"]     -= delta
		evac_points[i]["board_cd"]  = maxf(0.0, evac_points[i]["board_cd"] - delta)
		if evac_points[i]["life"] <= 0.0:
			evac_points.remove_at(i)
		i -= 1

	evac_timer -= delta
	if evac_timer > 0.0:
		return
	evac_timer = Tuning.EVAC_INTERVAL

	for spot in Tuning.EVAC_SPOTS:
		var taken := false
		for ep in evac_points:
			if (ep["pos"] as Vector2).distance_squared_to(spot) < 4.0:
				taken = true
				break
		if not taken:
			evac_points.append({"pos": spot, "life": Tuning.EVAC_POINT_LIFE, "board_cd": 0.0})
			if not _evac_announced:
				_evac_announced = true
				escalation_triggered.emit(-1, "ЭВАКУАЦИЯ! АВТОБУСЫ У ПЕРИМЕТРА ГОРОДА")
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
	p_prog      = Tuning.THROW_START_PROG
	_slider_pos = randf()
	_slider_dir = 1.0 if randf() > 0.5 else -1.0
	_throw_cd   = Tuning.THROW_CD
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
						_last_infector = -1
						_infect(_arresting_cop)
						_clear_arrest()
				get_viewport().set_input_as_handled()
				return

	# QTE захвата — только когда не арестован
	if not p_being_arrested and p_grab >= 0 and event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_SPACE:
			_resolve_slider()
			get_viewport().set_input_as_handled()
			return

	# F / H — команды орде (Follow / Hold)
	if event is InputEventKey and not p_being_arrested and p_grab < 0:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_F:
				if horde_cmd == HC_FOLLOW:
					horde_cmd         = HC_NONE
					horde_target_life = 0.0
				else:
					horde_cmd         = HC_FOLLOW
					horde_target      = p_pos
					horde_target_life = Tuning.HORDE_CMD_DURATION
					horde_floor       = p_floor
					horde_target_agent = -1
					horde_commanded.emit(horde_target)
				get_viewport().set_input_as_handled()
				return
			elif ke.keycode == KEY_H:
				if horde_cmd == HC_HOLD:
					horde_cmd         = HC_NONE
					horde_target_life = 0.0
				else:
					horde_cmd = HC_HOLD
					# Удерживать текущую позицию орды или позицию игрока
					if horde_target_life <= 0.0:
						horde_target = p_pos
					horde_target_life  = Tuning.HORDE_CMD_DURATION
					horde_floor        = p_floor
					horde_target_agent = -1
					horde_commanded.emit(horde_target)
				get_viewport().set_input_as_handled()
				return

	# ПКМ — команда орде
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not p_being_arrested:
			var click_pos := _mouse_world_pos()
			# Ищем агента (здоровый или коп) рядом с кликом
			var pick_r2   := 3.5 * 3.5
			var best      := -1
			var best_d    := pick_r2
			for nb in _neighbors(click_pos, p_floor):
				if state[nb] != S.HEALTHY and state[nb] != S.COP:
					continue
				if floor_idx[nb] != p_floor:
					continue
				var d2 := pos[nb].distance_squared_to(click_pos)
				if d2 < best_d:
					best_d = d2
					best   = nb
			horde_cmd          = HC_ATTACK if best >= 0 else HC_MOVE
			horde_target_agent = best
			horde_target       = click_pos if best < 0 else pos[best]
			horde_target_life  = Tuning.HORDE_CMD_DURATION
			horde_floor        = p_floor
			horde_commanded.emit(horde_target)
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


# ---------------------------------------------------------------- маршрутный автобус
func _build_bus_routes() -> void:
	route_buses.clear()
	var pts: Array = Array(MapGen.spawn_points)
	if pts.size() < 8:
		return

	# 8 радиальных секторов → точки маршрута по внешнему кольцу карты
	var route: Array = []
	for sector in 8:
		var angle := sector * TAU / 8.0
		var dir   := Vector2(cos(angle), sin(angle))
		var best_pt := Vector2.ZERO
		var best_dot := 0.5
		for p in pts:
			if (p as Vector2).length() < 25.0:
				continue
			var d := (p as Vector2).normalized().dot(dir)
			if d > best_dot:
				best_dot = d
				best_pt  = p
		if best_pt != Vector2.ZERO:
			route.append(best_pt)

	if route.size() < 4:
		return

	# Водитель — первый здоровый уличный агент
	var driver_idx := -1
	for i in pos.size():
		if state[i] == S.HEALTHY and floor_idx[i] == 0 and is_bus_driver[i] == 0:
			driver_idx = i
			break
	if driver_idx < 0:
		return

	is_bus_driver[driver_idx] = 1
	pos[driver_idx] = route[0]

	route_buses.append({
		"pos":       Vector2(route[0]),
		"vel_angle": 0.0,
		"route_pts": route,
		"route_idx": 0,
		"driver_idx": driver_idx,
		"stopped":   false,
		"stop_t":    0.0,
	})


func _tick_route_buses(delta: float) -> void:
	for bus in route_buses:
		var drv: int = bus["driver_idx"]

		# Водитель вскрылся или умер — автобус встаёт
		if drv >= 0 and state[drv] != S.HEALTHY and state[drv] != S.LATENT:
			is_bus_driver[drv] = 0
			bus["driver_idx"]  = -1
			bus["stopped"]     = true
			drv = -1

		# Водитель в инкубации — автобус замедляется и встаёт
		if drv >= 0 and state[drv] == S.LATENT:
			bus["stop_t"] = minf(bus["stop_t"] + delta, Tuning.BUS_STOP_TIME)
			if bus["stop_t"] >= Tuning.BUS_STOP_TIME:
				bus["stopped"] = true

		if bus["stopped"]:
			if drv >= 0:
				pos[drv] = bus["pos"]
			continue

		# Движение по маршруту
		var route: Array   = bus["route_pts"]
		var next_idx: int  = (bus["route_idx"] + 1) % route.size()
		var target: Vector2 = route[next_idx]
		var to_target := target - Vector2(bus["pos"])
		var dist      := to_target.length()

		var cur_speed := Tuning.BUS_SPEED
		if bus["stop_t"] > 0.0:
			cur_speed *= 1.0 - bus["stop_t"] / Tuning.BUS_STOP_TIME

		if dist < 3.0:
			bus["route_idx"] = next_idx
		elif dist > 0.01:
			var dir := to_target.normalized()
			bus["pos"]       = Vector2(bus["pos"]) + dir * cur_speed * delta
			bus["vel_angle"] = dir.angle()

		if drv >= 0:
			pos[drv] = bus["pos"]
