extends Node3D
## Пул трассеров выстрелов — 20 жёлтых полосок.
## Получает сигнал shot_fired от Sim и показывает трассер на 0.18 сек.

const POOL_SIZE  := 20
const TRACER_LIFE := 0.18

var _pool:   Array[MeshInstance3D] = []
var _timers: PackedFloat32Array


func _ready() -> void:
	_timers.resize(POOL_SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color     = Color(1.0, 0.95, 0.3)
	mat.emission_enabled = true
	mat.emission         = Color(1.0, 0.85, 0.1) * 2.0

	for i in POOL_SIZE:
		var mi  := MeshInstance3D.new()
		var bx  := BoxMesh.new()
		bx.size     = Vector3(0.07, 0.07, 1.0)
		bx.material = mat
		mi.mesh    = bx
		mi.visible = false
		add_child(mi)
		_pool.append(mi)
		_timers[i] = 0.0

	var sim := get_parent()
	if sim.has_signal("shot_fired"):
		sim.shot_fired.connect(_on_shot)


func _process(delta: float) -> void:
	for i in POOL_SIZE:
		if _timers[i] > 0.0:
			_timers[i] -= delta
			if _timers[i] <= 0.0:
				_pool[i].visible = false


func _on_shot(from_pos: Vector2, to_pos: Vector2) -> void:
	var slot := -1
	for i in POOL_SIZE:
		if _timers[i] <= 0.0:
			slot = i
			break
	if slot < 0:
		slot = 0  # перезаписываем самый старый

	var mid  := (from_pos + to_pos) * 0.5
	var dist := from_pos.distance_to(to_pos)
	var angle := -(to_pos - from_pos).angle()

	var mi := _pool[slot]
	mi.position = Vector3(mid.x, 0.9, mid.y)
	mi.rotation = Vector3(0.0, angle, 0.0)
	var bx := mi.mesh as BoxMesh
	bx.size    = Vector3(0.07, 0.07, maxf(0.3, dist))
	mi.visible = true
	_timers[slot] = TRACER_LIFE
