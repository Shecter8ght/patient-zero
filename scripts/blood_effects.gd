extends Node3D
## Симуляция жидкости: кровяные частицы ползут по земле с вязкостью,
## ветвятся и оставляют постоянные следы через blood_pool.gdshader.
## Все следы на полу — append-only (никогда не исчезают).
const POOL_SHADER = preload("res://assets/shaders/blood_pool.gdshader")

# --- Параметры жидкости ---
const FL_PARTICLES_KILL := 10   # частиц на смерть / выстрел
const FL_PARTICLES_BITE := 3    # частиц на укус
const FL_SPEED_KILL      := 2.8  # начальная скорость (м/с), смерть
const FL_SPEED_BITE      := 1.3  # начальная скорость, укус
const FL_DECAY           := 1.3  # вязкость: exp(-DECAY * dt), меньше = длиннее след
const FL_TURB            := 1.2  # амплитуда случайного отклонения (рад/с)
const FL_MARK_STEP       := 0.45 # метров между следами (> merge cell 0.35)
const FL_MIN_SPEED       := 0.04 # м/с — частица умирает
const FL_MAX_AGE         := 10.0 # сек — принудительная смерть
const FL_MAX_PARTICLES   := 200  # кольцевой буфер
const FL_BRANCH_PROB     := 0.22 # вероятность ветвления
const FL_BRANCH_ANGLE    := 0.85 # максимальный угол ответвления (рад)
const FL_BRANCH_SPEED    := 0.60 # скорость ветки
const FL_BRANCH_MAX      := 3    # максимум ветвлений

# Радиусы следов жидкости (меньше чем стандартные death/bite, но видимые)
const FL_RADIUS_KILL := 0.58   # радиус следа на смерть (м)
const FL_RADIUS_BITE := 0.42   # радиус следа на укус (м)

var sim: Node3D
var pools: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var mark_batches: Array[Dictionary] = []
var floor_tails: Dictionary = {}
var deposits: Dictionary = {}
var droplets: MultiMeshInstance3D
var mark_material: ShaderMaterial
var plane: PlaneMesh
var blood_clock := 0.0
var rng := RandomNumberGenerator.new()
var bite_cooldowns := PackedFloat32Array()
var player_cooldown := 0.0
var visible_floor := -1

# Кровяные частицы — жидкость на земле
# {pos, vel, floor, age, dist, branch, kind}
var fluid: Array = []
var _fluid_spawn_queue: Array = []   # пары [at, fl, count, speed, kind]


func _ready() -> void:
	sim = get_parent()
	rng.seed = 81723
	plane = PlaneMesh.new()
	plane.size = Vector2(2, 2)
	mark_material = ShaderMaterial.new()
	mark_material.shader = POOL_SHADER
	mark_material.set_shader_parameter("spread_seconds", Tuning.BLOOD_SPREAD_TIME)
	var drop_mesh := SphereMesh.new()
	drop_mesh.radius = 0.023
	drop_mesh.height = 0.09
	drop_mesh.radial_segments = 8
	drop_mesh.rings = 4
	droplets = _batch(drop_mesh, Tuning.BLOOD_DROP_COUNT)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.35, 0.006, 0.013)
	red.roughness = 0.2
	droplets.material_override = red
	sim.blood_hit.connect(emit_hit)
	sim.visuals_reset.connect(clear)
	clear()


func _batch(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.use_custom_data = true
	node.multimesh.mesh = mesh
	node.multimesh.instance_count = count
	node.multimesh.visible_instance_count = 0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-100, -3, -100), Vector3(200, 30, 200))
	add_child(node)
	return node


func clear() -> void:
	for batch in mark_batches:
		batch.node.hide()
		batch.node.queue_free()
	mark_batches.clear()
	floor_tails.clear()
	deposits.clear()
	pools.clear()
	drops.clear()
	fluid.clear()
	_fluid_spawn_queue.clear()
	blood_clock = 0.0
	visible_floor = -1
	mark_material.set_shader_parameter("blood_clock", blood_clock)
	bite_cooldowns.resize(Tuning.AGENT_COUNT)
	bite_cooldowns.fill(0)
	player_cooldown = 0.0
	if droplets:
		droplets.multimesh.visible_instance_count = 0


func visible_mark_count() -> int:
	var count := 0
	for batch in mark_batches:
		if batch.node.visible: count += int(batch.used)
	return count


func _deposit(at: Vector2, fl: int, kind: int, direction: Vector2, override_radius := -1.0) -> void:
	var cell := Tuning.BLOOD_MERGE_CELL if kind != 3 else Tuning.BLOOD_MERGE_CELL * 0.35
	var key := Vector4i(fl, floori(at.x / cell), floori(at.y / cell), kind)
	if deposits.has(key):
		var old: Dictionary = pools[deposits[key]]
		old.volume = minf(1.0, float(old.volume) + 0.08)
		_write_mark(old)
		return
	var batch_id: int = floor_tails.get(fl, -1)
	if batch_id < 0 or mark_batches[batch_id].used >= Tuning.BLOOD_MARK_BATCH_SIZE:
		var node := _batch(plane, Tuning.BLOOD_MARK_BATCH_SIZE)
		node.material_override = mark_material
		node.visible = fl == sim.p_floor
		batch_id = mark_batches.size()
		mark_batches.append({"node": node, "floor": fl, "used": 0})
		floor_tails[fl] = batch_id
	var radius: float = override_radius if override_radius > 0.0 else \
		[Tuning.BLOOD_BITE_RADIUS, Tuning.BLOOD_DEATH_RADIUS,
		Tuning.BLOOD_SHOT_RADIUS, Tuning.BLOOD_IMPACT_RADIUS][kind]
	var angle := -direction.angle() + rng.randf_range(-0.25, 0.25)
	var ground := MapGen.floor_y3d(fl) + (0.057 if fl == 0 else 0.012)
	ground += float(pools.size() % 64) * 0.000015
	var mark := {
		"pos": Vector3(at.x, ground, at.y), "floor": fl, "born": blood_clock,
		"radius": radius, "seed": rng.randf(), "angle": angle,
		"kind": kind, "volume": 0.48 if kind == 0 else 0.72,
		"batch": batch_id, "slot": mark_batches[batch_id].used,
	}
	deposits[key] = pools.size()
	pools.append(mark)
	mark_batches[batch_id].used += 1
	var mesh: MultiMesh = mark_batches[batch_id].node.multimesh
	mesh.set_instance_transform(mark.slot,
		Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(radius, 1, radius)), mark.pos))
	mesh.visible_instance_count = mark_batches[batch_id].used
	_write_mark(mark)


func _write_mark(mark: Dictionary) -> void:
	var mesh: MultiMesh = mark_batches[mark.batch].node.multimesh
	mesh.set_instance_custom_data(mark.slot,
		Color(mark.born, mark.seed, float(mark.kind), mark.volume))


func _spawn_fluid(at: Vector2, fl: int, count: int, base_speed: float, kind: int) -> void:
	for _i in count:
		if fluid.size() >= FL_MAX_PARTICLES:
			fluid.pop_front()
		var angle := rng.randf_range(0.0, TAU)
		var speed := rng.randf_range(base_speed * 0.35, base_speed)
		fluid.append({
			"pos":    at,
			"vel":    Vector2(cos(angle), sin(angle)) * speed,
			"floor":  fl,
			"age":    0.0,
			"dist":   0.0,
			"branch": 0,
			"kind":   kind,
		})


func emit_hit(at: Vector2, fl: int, lethal: bool, direction: Vector2, behavior: int = -1) -> void:
	var kind := behavior if behavior >= 0 else (1 if lethal else 2)
	_deposit(at, fl, kind, direction)
	if lethal or kind == 2:
		_spawn_fluid(at, fl, FL_PARTICLES_KILL, FL_SPEED_KILL, kind)
	else:
		_spawn_fluid(at, fl, FL_PARTICLES_BITE, FL_SPEED_BITE, 0)
	var ground := MapGen.floor_y3d(fl) + (0.057 if fl == 0 else 0.012)
	var amount := Tuning.BLOOD_DEATH_DROPS if lethal else Tuning.BLOOD_BITE_DROPS
	for i in amount:
		if drops.size() >= Tuning.BLOOD_DROP_COUNT:
			drops.pop_front()
		var speed := rng.randf_range(0.45, 1.5) if kind == 0 else rng.randf_range(1.3, 3.8)
		var lateral := direction.rotated(rng.randf_range(-1.0, 1.0)) * speed
		drops.append({
			"pos": Vector3(at.x, ground + 1.2, at.y),
			"velocity": Vector3(lateral.x, rng.randf_range(-0.6, 1.4), lateral.y),
			"floor": fl, "ground": ground, "age": 0.0,
			"scale": rng.randf_range(0.55, 1.45), "leave_mark": i < Tuning.BLOOD_IMPACT_MARKS,
		})


func _bite(target: int, source: Vector2) -> void:
	if target < 0 or target >= sim.pos.size(): return
	if sim.state[target] not in [sim.S.HEALTHY, sim.S.COP]: return
	emit_hit(sim.pos[target], sim.floor_idx[target], false,
		(sim.pos[target] - source).normalized(), 0)


func _process(delta: float) -> void:
	if sim.finished != 0: delta = 0.0
	blood_clock += delta
	mark_material.set_shader_parameter("blood_clock", blood_clock)

	if visible_floor != sim.p_floor:
		visible_floor = sim.p_floor
		for batch in mark_batches:
			batch.node.visible = batch.floor == visible_floor

	player_cooldown = maxf(0.0, player_cooldown - delta)
	if delta > 0 and sim.p_grab >= 0:
		if player_cooldown <= 0:
			_bite(sim.p_grab, sim.p_pos)
			player_cooldown = Tuning.BLOOD_BITE_INTERVAL
	else:
		player_cooldown = 0.0

	for i in sim.pos.size():
		bite_cooldowns[i] = maxf(0.0, bite_cooldowns[i] - delta)
		if delta > 0 and sim.state[i] in [sim.S.INFECTED, sim.S.INFECTED_COP] \
				and sim.grab_target[i] >= 0:
			if bite_cooldowns[i] <= 0:
				_bite(sim.grab_target[i], sim.pos[i])
				bite_cooldowns[i] = Tuning.BLOOD_BITE_INTERVAL
		else:
			bite_cooldowns[i] = 0.0

	# --- Симуляция жидкости ---
	if delta > 0.0:
		var to_add: Array = []
		var fi := fluid.size() - 1
		while fi >= 0:
			var p: Dictionary = fluid[fi]
			p.age += delta

			var vel: Vector2 = p.vel
			var spd := vel.length()

			if spd < FL_MIN_SPEED or float(p.age) > FL_MAX_AGE:
				fluid.remove_at(fi)
				fi -= 1
				continue

			# Турбулентность: случайное отклонение угла (тем меньше, чем быстрее)
			var turb_amt := FL_TURB * delta * (1.0 - spd / FL_SPEED_KILL)
			vel = vel.rotated(rng.randf_range(-turb_amt, turb_amt))

			# Вязкость
			vel *= exp(-FL_DECAY * delta)

			# Движение
			var move := vel * delta
			var new_pos: Vector2 = (p.pos as Vector2) + move
			var fl: int = p.floor

			# Стена — отражаем
			if MapGen.is_blocked(new_pos, 0.05, fl):
				# Пробуем скользить по X, потом по Y
				var try_x := Vector2(new_pos.x, (p.pos as Vector2).y)
				var try_y := Vector2((p.pos as Vector2).x, new_pos.y)
				if not MapGen.is_blocked(try_x, 0.05, fl):
					new_pos = try_x
					vel.y *= -0.4
				elif not MapGen.is_blocked(try_y, 0.05, fl):
					new_pos = try_y
					vel.x *= -0.4
				else:
					# Тупик — гасим частицу
					fluid.remove_at(fi)
					fi -= 1
					continue

			p.pos = new_pos
			p.vel = vel
			p.dist += move.length()

			# Оставляем след каждые FL_MARK_STEP метров
			if float(p.dist) >= FL_MARK_STEP:
				p.dist = fmod(float(p.dist), FL_MARK_STEP)
				# kind=0 (bite) → поток укуса 0.42м; kind=1/2 (death/shot) → 0.58м
				var is_death := int(p.kind) != 0
				var trail_kind := 1 if is_death else 0
				var trail_r := FL_RADIUS_KILL if is_death else FL_RADIUS_BITE
				_deposit(new_pos, fl, trail_kind, vel.normalized(), trail_r)

				# Ветвление — тем вероятнее, чем медленнее (кровь "расползается")
				var branch_p := FL_BRANCH_PROB * (1.0 - spd / FL_SPEED_KILL)
				if int(p.branch) < FL_BRANCH_MAX and rng.randf() < branch_p \
						and to_add.size() < 12:
					var bangle := rng.randf_range(-FL_BRANCH_ANGLE, FL_BRANCH_ANGLE)
					to_add.append({
						"pos":    p.pos,
						"vel":    vel.rotated(bangle) * FL_BRANCH_SPEED,
						"floor":  fl,
						"age":    float(p.age),
						"dist":   0.0,
						"branch": int(p.branch) + 1,
						"kind":   p.kind,
					})

			fi -= 1

		for nb in to_add:
			if fluid.size() < FL_MAX_PARTICLES:
				fluid.append(nb)

	# --- Воздушные капли (3D баллистика) ---
	var count := 0
	for i in range(drops.size() - 1, -1, -1):
		var d := drops[i]
		d.age += delta
		var previous: Vector3 = d.pos
		d.pos += d.velocity * delta + Vector3.DOWN * Tuning.BLOOD_GRAVITY * delta * delta * 0.5
		d.velocity.y -= Tuning.BLOOD_GRAVITY * delta
		if d.pos.y <= d.ground:
			if d.leave_mark:
				var amt := clampf(
					(previous.y - float(d.ground)) / maxf(0.0001, previous.y - float(d.pos.y)),
					0.0, 1.0)
				var landing: Vector3 = previous.lerp(d.pos, amt)
				var at2 := Vector2(landing.x, landing.z)
				if not MapGen.is_blocked(at2, 0.03, d.floor):
					_deposit(at2, d.floor, 3, Vector2(d.velocity.x, d.velocity.z))
			drops.remove_at(i)
			continue
		if d.age > Tuning.BLOOD_DROP_LIFETIME:
			drops.remove_at(i)
			continue
		if d.floor != sim.p_floor: continue
		var sz: float = d.scale
		var vel: Vector3 = d.velocity
		var basis := Basis(Quaternion(Vector3.UP, vel.normalized())) \
			if vel.length_squared() > 0.001 else Basis()
		droplets.multimesh.set_instance_transform(count,
			Transform3D(basis.scaled(Vector3(sz, sz, sz)), d.pos))
		count += 1
	droplets.multimesh.visible_instance_count = count
