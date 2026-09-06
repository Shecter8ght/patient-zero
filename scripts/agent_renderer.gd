extends MultiMeshInstance3D
## Рисует всех агентов ОДНИМ мешем. Никаких 300 нод.
## Цвет несёт состояние — читается с одного взгляда.

@export var sim_path: NodePath
var sim: Node3D

const C_HEALTHY := Color(0.71, 0.70, 0.66)
const C_LATENT := Color(0.73, 0.46, 0.09)
const C_INFECTED := Color(0.85, 0.35, 0.19)
const C_DEAD := Color(0.29, 0.18, 0.18)
const C_COP := Color(0.22, 0.54, 0.87)
const C_INFECTED_COP := Color(1.0, 0.32, 0.20)


func _ready() -> void:
	sim = get_node(sim_path)

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 1.7
	capsule.radial_segments = 6   # лоу-поли: дёшево и стильно
	capsule.rings = 2

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	capsule.material = mat

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = capsule
	multimesh.instance_count = Tuning.AGENT_COUNT


func _process(_delta: float) -> void:
	if sim == null:
		return
	for i in multimesh.instance_count:
		var p: Vector2 = sim.pos[i]
		var s: int     = sim.state[i]
		var fl: int    = sim.floor_idx[i]

		# Скрываем агентов не на этаже игрока — помещаем под землю
		if fl != sim.p_floor:
			multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -100, 0)))
			multimesh.set_instance_color(i, Color.TRANSPARENT)
			continue

		var base_y: float = MapGen.floor_y3d(fl)
		var y := base_y + (0.15 if s == sim.S.DEAD else 0.85)
		var basis := Basis(Vector3.UP, sim.facing[i])
		if s == sim.S.DEAD:
			basis = basis.rotated(Vector3.RIGHT, PI * 0.5)
		multimesh.set_instance_transform(i, Transform3D(basis, Vector3(p.x, y, p.y)))
		multimesh.set_instance_color(i, _color_for(s, i))


func _color_for(s: int, i: int) -> Color:
	match s:
		sim.S.LATENT:        return C_LATENT
		sim.S.INFECTED:      return C_INFECTED
		sim.S.DEAD:          return C_DEAD
		sim.S.COP:           return C_COP
		sim.S.INFECTED_COP:  return C_INFECTED_COP
		_:
			# Звонит в полицию — оранжевый
			if sim.has_phone[i] == 1 and sim.phone_timer[i] > 0.0:
				return Color(1.0, 0.5, 0.0)
			match sim.archetype[i]:
				Tuning.ARCH_CHILD:      return Color(1.0, 0.95, 0.4)
				Tuning.ARCH_ELDER:      return Color(0.75, 0.6, 0.45)
				Tuning.ARCH_BRUTE:      return Color(0.3, 0.7, 0.35)
				Tuning.ARCH_JOURNALIST: return Color(0.2, 0.85, 0.9)
				_:                      return C_HEALTHY
