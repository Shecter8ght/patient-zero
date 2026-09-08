extends MultiMeshInstance3D
## Nine mesh batches, no agent nodes or per-agent Skeleton3D/AnimationPlayer.
const BONE_SHADER = preload("res://assets/shaders/crowd_bones.gdshader")
const SETS = [preload("res://assets/animations/civilian_normal_a_crowd.res"),
	preload("res://assets/animations/civilian_child_a_crowd.res"),
	preload("res://assets/animations/civilian_elder_a_crowd.res"),
	preload("res://assets/animations/civilian_brute_a_crowd.res"),
	preload("res://assets/animations/civilian_journalist_a_crowd.res"),
	preload("res://assets/animations/police_officer_a_crowd.res"),
	preload("res://assets/animations/swat_officer_a_crowd.res"),
	preload("res://assets/animations/civilian_normal_b_crowd.res"),
	preload("res://assets/animations/civilian_normal_c_crowd.res")]
@export var sim_path: NodePath
var sim: Node3D
var batches: Array[MultiMeshInstance3D] = []
var clip_names: Array[String] = []
var clip_times := PackedFloat32Array()
var frame_rows := PackedFloat32Array()
var from_rows := PackedFloat32Array()
var blend_times := PackedFloat32Array()
var previous_states := PackedInt32Array()
var turning_left := PackedFloat32Array()
var shooting_left := PackedFloat32Array()
var grabbed_by_horde := PackedByteArray()
var previous_elapsed := 0.0

func _ready() -> void:
	sim = get_node(sim_path)
	for i in SETS.size():
		var batch := self if i == 0 else MultiMeshInstance3D.new()
		if i > 0: add_child(batch)
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.use_colors = true
		batch.multimesh.use_custom_data = true
		batch.multimesh.mesh = SETS[i].mesh
		batch.multimesh.instance_count = Tuning.AGENT_COUNT
		batch.multimesh.visible_instance_count = 0
		batch.custom_aabb = AABB(Vector3(-Tuning.WORLD_SIZE, -3, -Tuning.WORLD_SIZE), Vector3(Tuning.WORLD_SIZE * 2, Tuning.MALL_FLOORS * Tuning.FLOOR_HEIGHT + 8, Tuning.WORLD_SIZE * 2))
		var mat := ShaderMaterial.new()
		mat.shader = BONE_SHADER
		mat.set_shader_parameter("bone_texture", SETS[i].bone_texture)
		mat.set_shader_parameter("palette", SETS[i].palette)
		mat.set_shader_parameter("bone_count", SETS[i].bone_count)
		batch.material_override = mat
		batches.append(batch)
	_reset_animation()
	sim.shot_fired.connect(_on_shot)

func _reset_animation() -> void:
	var n := Tuning.AGENT_COUNT
	clip_names.resize(n); clip_names.fill("")
	clip_times.resize(n); clip_times.fill(0)
	frame_rows.resize(n); frame_rows.fill(0)
	from_rows.resize(n); from_rows.fill(0)
	blend_times.resize(n); blend_times.fill(0)
	previous_states.resize(n); previous_states.fill(-1)
	turning_left.resize(n); turning_left.fill(0)
	shooting_left.resize(n); shooting_left.fill(0)
	grabbed_by_horde.resize(n); grabbed_by_horde.fill(0)

func _on_shot(from_pos: Vector2, _to: Vector2, _swat_shot: bool = false) -> void:
	for i in sim.pos.size():
		if sim.state[i] == sim.S.COP and sim.pos[i].distance_squared_to(from_pos) < 0.01:
			shooting_left[i] = float(SETS[0].clips.shoot.duration)
			break

func _process(delta: float) -> void:
	if sim == null: return
	if sim.elapsed < previous_elapsed: _reset_animation()
	previous_elapsed = sim.elapsed
	if sim.finished != 0: delta = 0.0
	var counts := PackedInt32Array()
	counts.resize(SETS.size())
	grabbed_by_horde.fill(0)
	for attacker in sim.grab_target.size():
		var target: int = sim.grab_target[attacker]
		if target >= 0 and target < grabbed_by_horde.size() and sim.state[attacker] in [sim.S.INFECTED, sim.S.INFECTED_COP]:
			grabbed_by_horde[target] = 1
	for i in sim.pos.size():
		var state: int = sim.state[i]
		var kind := _kind(i)
		if previous_states[i] >= 0 and previous_states[i] != state and state in [sim.S.INFECTED, sim.S.INFECTED_COP]:
			turning_left[i] = float(SETS[kind].clips.turning.duration)
		previous_states[i] = state
		var desired := _clip_for(i)
		var info: Dictionary = SETS[kind].clips[desired]
		if clip_names[i] != desired:
			from_rows[i] = frame_rows[i]
			blend_times[i] = 0.0
			clip_times[i] = fmod(float(i) * 0.173, float(info.duration)) if info.loop and desired in ["idle", "walk", "run", "bitten_idle", "bitten_walk", "bitten_run", "zombie_idle", "zombie_walk", "zombie_run"] else 0.0
			clip_names[i] = desired
		var rate := 1.0
		if desired in ["walk", "bitten_walk"]: rate = clampf(sim.vel[i].length() / Tuning.CIV_WALK, 0.4, 1.6)
		if desired in ["run", "bitten_run"]: rate = clampf(sim.vel[i].length() / Tuning.CIV_PANIC, 0.5, 1.6)
		if desired == "zombie_walk": rate = clampf(sim.vel[i].length() / Tuning.INFECTED_SPEED, 0.5, 1.5)
		if desired == "zombie_run": rate = clampf(sim.vel[i].length() / Tuning.INFECTED_COP_SPEED, 0.5, 1.5)
		clip_times[i] += delta * rate
		blend_times[i] += delta
		var time: float = fmod(clip_times[i], float(info.duration)) if info.loop else minf(clip_times[i], float(info.duration))
		frame_rows[i] = float(info.start) + time / float(info.duration) * (float(info.frames) - 1.0)
		turning_left[i] = maxf(0.0, turning_left[i] - delta)
		shooting_left[i] = maxf(0.0, shooting_left[i] - delta)
		if sim.floor_idx[i] != sim.p_floor: continue
		var index := counts[kind]
		counts[kind] += 1
		var mm := batches[kind].multimesh
		var p: Vector2 = sim.pos[i]
		var facing: float = sim.facing[i]
		if desired == "bite" and sim.grab_target[i] >= 0:
			var direction: Vector2 = sim.pos[sim.grab_target[i]] - p
			if direction.length_squared() > 0.001: facing = direction.angle()
		var basis := Basis(Vector3.UP, PI * 0.5 - facing)
		mm.set_instance_transform(index, Transform3D(basis, Vector3(p.x, MapGen.floor_y3d(sim.floor_idx[i]), p.y)))
		mm.set_instance_color(index, _color_for(state, i))
		mm.set_instance_custom_data(index, Color(frame_rows[i], from_rows[i], minf(1.0, blend_times[i] / Tuning.ANIM_BLEND_TIME), 0))
	for k in batches.size(): batches[k].multimesh.visible_instance_count = counts[k]

func _kind(i: int) -> int:
	if sim.is_swat[i] == 1: return 6
	if sim.was_cop[i] == 1 or sim.state[i] in [sim.S.COP, sim.S.INFECTED_COP]: return 5
	if sim.archetype[i] == 0 and i % 3 != 0: return 6 + i % 3
	return clampi(sim.archetype[i], 0, 4)

func _clip_for(i: int) -> String:
	if sim.state[i] == sim.S.DEAD: return "fall"
	if turning_left[i] > 0: return "turning"
	if i == sim.p_grab or grabbed_by_horde[i] == 1: return "resist"
	if sim.grab_target[i] >= 0: return "bite" if sim.state[i] in [sim.S.INFECTED, sim.S.INFECTED_COP] else "grab"
	if sim.state[i] in [sim.S.INFECTED, sim.S.INFECTED_COP]:
		if sim.vel[i].length_squared() <= 0.04: return "zombie_idle"
		return "zombie_run" if sim.vel[i].length() > Tuning.ANIM_ZOMBIE_RUN_THRESHOLD else "zombie_walk"
	if shooting_left[i] > 0: return "shoot"
	if sim.phone_timer[i] > 0: return "phone"
	if sim.photo_timer[i] > 0: return "photo"
	if sim.state[i] == sim.S.LATENT:
		if sim.vel[i].length_squared() <= 0.04: return "bitten_idle"
		return "bitten_run" if sim.vel[i].length() > Tuning.ANIM_RUN_THRESHOLD else "bitten_walk"
	if sim.vel[i].length_squared() > 0.04: return "run" if sim.vel[i].length() > Tuning.ANIM_RUN_THRESHOLD else "walk"
	return "idle"

func _color_for(state: int, i: int) -> Color:
	if state == sim.S.DEAD: return Color(0.38, 0.23, 0.23)
	if state in [sim.S.INFECTED, sim.S.INFECTED_COP]: return Color(1.65, 0.48, 0.32)
	if state == sim.S.LATENT: return Color(1.0, 0.78, 0.42)
	if sim.phone_timer[i] > 0: return Color(1.35, 0.75, 0.35)
	return Color.WHITE
