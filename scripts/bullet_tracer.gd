extends Node3D
## Пул трассеров выстрелов + вспышки у стрелка.
## Трассер: жёлтый (коп) / красно-оранжевый (SWAT).
## Вспышка: маленький диск у from_pos на 0.1 сек — сразу видно кто выстрелил.

const POOL_SIZE   := 20
const TRACER_LIFE := 0.14
const FLASH_LIFE  := 0.10

var _tracers:      Array[MeshInstance3D] = []
var _flashes:      Array[MeshInstance3D] = []
var _tracer_t:     PackedFloat32Array
var _flash_t:      PackedFloat32Array

var _mat_cop:  StandardMaterial3D
var _mat_swat: StandardMaterial3D
var _mat_flash: StandardMaterial3D


func _ready() -> void:
	_tracer_t.resize(POOL_SIZE)
	_flash_t.resize(POOL_SIZE)

	_mat_cop = StandardMaterial3D.new()
	_mat_cop.albedo_color     = Color(1.0, 0.95, 0.3)
	_mat_cop.emission_enabled = true
	_mat_cop.emission         = Color(1.0, 0.85, 0.1) * 2.5

	_mat_swat = StandardMaterial3D.new()
	_mat_swat.albedo_color     = Color(1.0, 0.35, 0.1)
	_mat_swat.emission_enabled = true
	_mat_swat.emission         = Color(1.0, 0.2, 0.0) * 3.0

	_mat_flash = StandardMaterial3D.new()
	_mat_flash.albedo_color       = Color(1.0, 1.0, 0.8)
	_mat_flash.emission_enabled   = true
	_mat_flash.emission           = Color(1.0, 0.9, 0.5) * 6.0
	_mat_flash.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA

	for idx in POOL_SIZE:
		var mi  := MeshInstance3D.new()
		var bx  := BoxMesh.new()
		bx.size     = Vector3(0.07, 0.07, 1.0)
		bx.material = _mat_cop
		mi.mesh    = bx
		mi.visible = false
		add_child(mi)
		_tracers.append(mi)
		_tracer_t[idx] = 0.0

		var fm  := MeshInstance3D.new()
		var fd  := CylinderMesh.new()
		fd.top_radius    = 0.28
		fd.bottom_radius = 0.28
		fd.height        = 0.04
		fd.material      = _mat_flash
		fm.mesh    = fd
		fm.visible = false
		add_child(fm)
		_flashes.append(fm)
		_flash_t[idx] = 0.0

	var sim := get_parent()
	if sim.has_signal("shot_fired"):
		sim.shot_fired.connect(_on_shot)


func _process(delta: float) -> void:
	for idx in POOL_SIZE:
		if _tracer_t[idx] > 0.0:
			_tracer_t[idx] -= delta
			if _tracer_t[idx] <= 0.0:
				_tracers[idx].visible = false
		if _flash_t[idx] > 0.0:
			_flash_t[idx] -= delta
			var a := _flash_t[idx] / FLASH_LIFE
			_mat_flash.albedo_color.a = a
			if _flash_t[idx] <= 0.0:
				_flashes[idx].visible = false


func _on_shot(from_pos: Vector2, to_pos: Vector2, is_swat_shot: bool) -> void:
	# Слот для трассера
	var slot := -1
	for idx in POOL_SIZE:
		if _tracer_t[idx] <= 0.0:
			slot = idx
			break
	if slot < 0:
		slot = 0

	var mid   := (from_pos + to_pos) * 0.5
	var dist  := from_pos.distance_to(to_pos)
	var angle := -(to_pos - from_pos).angle()

	var mi := _tracers[slot]
	mi.position = Vector3(mid.x, 0.9, mid.y)
	mi.rotation = Vector3(0.0, angle, 0.0)
	var bx := mi.mesh as BoxMesh
	bx.size    = Vector3(0.06, 0.06, maxf(0.3, dist))
	bx.material = _mat_swat if is_swat_shot else _mat_cop
	mi.visible = true
	_tracer_t[slot] = TRACER_LIFE

	# Вспышка у стрелка
	var fm := _flashes[slot]
	fm.position  = Vector3(from_pos.x, 0.95, from_pos.y)
	fm.visible   = true
	_flash_t[slot] = FLASH_LIFE
