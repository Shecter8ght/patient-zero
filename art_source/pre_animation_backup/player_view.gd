extends Node3D
## Визуал игрока. Логика — в sim.gd, здесь только отрисовка.

@export var sim_path: NodePath
var sim: Node3D
var body: MeshInstance3D
var mat: StandardMaterial3D


func _ready() -> void:
	sim = get_node(sim_path)
	body = MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = 0.28
	m.height = 1.8
	m.radial_segments = 8
	body.mesh = m
	mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.77, 0.70)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.22, 0.12)
	mat.emission_energy_multiplier = 0.5
	body.material_override = mat
	add_child(body)


func _process(_delta: float) -> void:
	if sim == null:
		return
	global_position = Vector3(sim.p_pos.x, MapGen.floor_y3d(sim.p_floor) + 0.9, sim.p_pos.y)
	# Спринт светится ярче — сразу видно, что ты палишься
	mat.emission_energy_multiplier = 1.6 if sim.sprinting else 0.4
	if sim.p_vel.length_squared() > 0.05:
		rotation.y = -sim.p_vel.angle() + PI * 0.5
