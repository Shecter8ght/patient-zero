extends Node3D
## One skeletal player; the crowd uses GPU bone animation instead.
const MODEL = preload("res://assets/animations/patient_zero_rigged.glb")
const LOOPS := ["idle", "walk", "run", "zombie_idle", "zombie_walk", "zombie_run", "bite", "grab", "resist", "phone", "photo"]
@export var sim_path: NodePath
var sim: Node3D
var animation: AnimationPlayer
var materials: Array[StandardMaterial3D] = []
var clips: Dictionary = {}
var current_clip := ""
var one_shot := ""
var one_shot_left := 0.0
var previous_throw := 0.0
var previous_elapsed := 0.0

func _ready() -> void:
	sim = get_node(sim_path)
	var model := MODEL.instantiate()
	add_child(model)
	_collect(model)
	assert(animation != null, "Rigged player requires AnimationPlayer")
	for key in animation.get_animation_list():
		var short: String = str(key).get_slice("/", str(key).get_slice_count("/") - 1)
		clips[short] = key
		animation.get_animation(key).loop_mode = Animation.LOOP_LINEAR if short in LOOPS else Animation.LOOP_NONE
	animation.play(clips["zombie_idle"])

func _collect(node: Node) -> void:
	if node is AnimationPlayer: animation = node
	if node is MeshInstance3D:
		for s in node.mesh.get_surface_count():
			var mat := node.mesh.surface_get_material(s).duplicate() as StandardMaterial3D
			mat.emission_enabled = true
			mat.emission = Color(0.11, 0.035, 0.018)
			node.set_surface_override_material(s, mat)
			materials.append(mat)
	for child in node.get_children(): _collect(child)

func _process(delta: float) -> void:
	if sim == null: return
	if sim.elapsed < previous_elapsed:
		previous_throw = 0.0
		one_shot_left = 0.0
		current_clip = ""
	previous_elapsed = sim.elapsed
	global_position = Vector3(sim.p_pos.x, MapGen.floor_y3d(sim.p_floor), sim.p_pos.y)
	if sim.finished != 0:
		animation.pause()
		return
	if sim._throw_cd > previous_throw + 0.1:
		one_shot = "lunge"
		one_shot_left = animation.get_animation(clips[one_shot]).length
	previous_throw = sim._throw_cd
	var desired := "zombie_idle"
	if one_shot_left > 0.0: desired = one_shot
	elif sim.p_grab >= 0: desired = "bite"
	elif sim.p_vel.length_squared() > 0.04: desired = "zombie_run" if sim.sprinting else "zombie_walk"
	one_shot_left = maxf(0.0, one_shot_left - delta)
	if desired != current_clip:
		animation.play(clips[desired], Tuning.ANIM_BLEND_TIME)
		current_clip = desired
	elif not animation.is_playing() and desired in LOOPS:
		animation.play()
	animation.speed_scale = 1.0
	if desired == "zombie_walk": animation.speed_scale = clampf(sim.p_vel.length() / Tuning.PLAYER_WALK, 0.5, 1.5)
	if desired == "zombie_run": animation.speed_scale = clampf(sim.p_vel.length() / Tuning.PLAYER_SPRINT, 0.5, 1.5)
	for mat in materials: mat.emission_energy_multiplier = 1.6 if sim.sprinting else 0.4
	var direction: Vector2 = sim.p_vel
	if sim.p_grab >= 0: direction = sim.pos[sim.p_grab] - sim.p_pos
	if direction.length_squared() > 0.01: rotation.y = PI * 0.5 - direction.angle()
