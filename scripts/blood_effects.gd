extends Node3D
## Кровь как декали: стемпим реальные текстуры брызг (разные + случайные
## поворот/масштаб/зеркало) на пол через blood_pool.gdshader. Наложение разных
## реальных брызг читается как настоящая кровь, а не повторяющийся блоб.
## Следы на полу append-only (не исчезают). Плюс 3D-капли, оставляющие мелкие пятна.
const POOL_SHADER = preload("res://assets/shaders/blood_pool.gdshader")

# Реальные текстуры брызг (прозрачный фон). Порядок = индекс ti.
const SPLAT_TEXTURES := [
	preload("res://assets/ninja texture/BloodDrop01.png"),
	preload("res://assets/ninja texture/BloodDrop02.png"),
	preload("res://assets/ninja texture/BloodDrop30.png"),
	preload("res://assets/ninja texture/BloodFabricSpatter01.png"),
	preload("res://assets/ninja texture/BloodFabricSpatter04.png"),
]
# Индексы текстур по назначению
const TI_DROPS := [0, 1, 2]        # брызги со струями/сателлитами — укусы, капли
const TI_POOLS := [2, 3, 4]        # крупные массы — смерть/лужа

const BATCH_SIZE := 128

var sim: Node3D
var batches: Array[Dictionary] = []   # {node, floor, ti, used}
var _cur: Dictionary = {}             # "fl:ti" -> индекс текущего батча
var materials: Array[ShaderMaterial] = []   # по одному на текстуру
var drops: Array[Dictionary] = []
var droplets: MultiMeshInstance3D
var plane: PlaneMesh
var blood_clock := 0.0
var rng := RandomNumberGenerator.new()
var bite_cooldowns := PackedFloat32Array()
var player_cooldown := 0.0
var visible_floor := -1


func _ready() -> void:
	sim = get_parent()
	rng.seed = 81723
	plane = PlaneMesh.new()
	plane.size = Vector2(2, 2)   # [-1..1]; масштаб задаёт реальный размер

	for tex in SPLAT_TEXTURES:
		var mat := ShaderMaterial.new()
		mat.shader = POOL_SHADER
		mat.set_shader_parameter("splat", tex)
		materials.append(mat)

	var drop_mesh := SphereMesh.new()
	drop_mesh.radius = 0.023
	drop_mesh.height = 0.09
	drop_mesh.radial_segments = 8
	drop_mesh.rings = 4
	droplets = _batch_node(drop_mesh, Tuning.BLOOD_DROP_COUNT)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.35, 0.006, 0.013)
	red.roughness = 0.2
	droplets.material_override = red

	sim.blood_hit.connect(emit_hit)
	sim.visuals_reset.connect(clear)
	clear()


func _batch_node(mesh: Mesh, count: int) -> MultiMeshInstance3D:
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
	for b in batches:
		b.node.hide()
		b.node.queue_free()
	batches.clear()
	_cur.clear()
	drops.clear()
	blood_clock = 0.0
	visible_floor = -1
	for m in materials:
		m.set_shader_parameter("blood_clock", 0.0)
	bite_cooldowns.resize(Tuning.AGENT_COUNT)
	bite_cooldowns.fill(0)
	player_cooldown = 0.0
	if droplets:
		droplets.multimesh.visible_instance_count = 0


func visible_mark_count() -> int:
	var count := 0
	for b in batches:
		if b.node.visible:
			count += int(b.used)
	return count


func _get_batch(fl: int, ti: int) -> Dictionary:
	var key := "%d:%d" % [fl, ti]
	var idx: int = _cur.get(key, -1)
	if idx >= 0 and batches[idx].used < BATCH_SIZE:
		return batches[idx]
	var node := _batch_node(plane, BATCH_SIZE)
	node.material_override = materials[ti]
	node.visible = fl == sim.p_floor
	var b := {"node": node, "floor": fl, "ti": ti, "used": 0}
	batches.append(b)
	_cur[key] = batches.size() - 1
	return b


## Штамп одной брызги: случайный поворот/масштаб/зеркало, тонируется шейдером.
func _stamp(at: Vector2, fl: int, size: float, angle: float, ti: int, volume: float) -> void:
	var b := _get_batch(fl, ti)
	var slot: int = b.used
	var sc := size * rng.randf_range(0.82, 1.28)
	var mirror := 1.0 if rng.randf() > 0.5 else -1.0
	var rot := angle + rng.randf_range(-0.4, 0.4)
	var ground := MapGen.floor_y3d(fl) + (0.05 if fl == 0 else 0.012)
	ground += float(b.used % 48) * 0.00002   # микро-смещение слоёв
	var basis := Basis(Vector3.UP, rot).scaled(Vector3(sc * mirror, 1.0, sc))
	var mm: MultiMesh = b.node.multimesh
	mm.set_instance_transform(slot, Transform3D(basis, Vector3(at.x, ground, at.y)))
	mm.set_instance_custom_data(slot, Color(blood_clock, rng.randf(), 0.0, volume))
	b.used += 1
	mm.visible_instance_count = b.used


func emit_hit(at: Vector2, fl: int, lethal: bool, direction: Vector2, behavior: int = -1) -> void:
	var kind := behavior if behavior >= 0 else (1 if lethal else 2)
	var dir_angle := -direction.angle()
	var big := lethal or kind == 1

	if big:
		# Лужа: крупная масса + пара направленных брызг со струями.
		_stamp(at, fl, rng.randf_range(1.15, 1.5), rng.randf() * TAU, TI_POOLS[rng.randi() % TI_POOLS.size()], 0.9)
		for _s in 2:
			_stamp(at, fl, rng.randf_range(0.7, 1.0), dir_angle, TI_DROPS[rng.randi() % TI_DROPS.size()], 0.8)
	else:
		# Укус/выстрел: одна брызга по направлению.
		var size := 0.7 if kind == 2 else 0.5
		_stamp(at, fl, size, dir_angle, TI_DROPS[rng.randi() % TI_DROPS.size()], 0.6)

	# 3D-капли, оставляющие мелкие пятна при падении.
	var ground := MapGen.floor_y3d(fl) + (0.05 if fl == 0 else 0.012)
	var amount := Tuning.BLOOD_DEATH_DROPS if lethal else Tuning.BLOOD_BITE_DROPS
	for i in amount:
		if drops.size() >= Tuning.BLOOD_DROP_COUNT:
			drops.pop_front()
		var speed := rng.randf_range(1.3, 3.8) if big else rng.randf_range(0.45, 1.5)
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
		(sim.pos[target] - source).normalized(), 2)


func _process(delta: float) -> void:
	if sim.finished != 0: delta = 0.0
	blood_clock += delta
	for m in materials:
		m.set_shader_parameter("blood_clock", blood_clock)

	if visible_floor != sim.p_floor:
		visible_floor = sim.p_floor
		for b in batches:
			b.node.visible = b.floor == visible_floor

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
					_stamp(at2, d.floor, rng.randf_range(0.18, 0.32), rng.randf() * TAU,
						TI_DROPS[rng.randi() % TI_DROPS.size()], 0.5)
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
