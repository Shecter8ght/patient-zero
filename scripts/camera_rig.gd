extends Node3D
## Ортографическая камера под изометрическим углом.

@export var sim_path:    NodePath
@export var follow_lerp := 4.0
@export var ortho_size  := 34.0

const ORTHO_OUTDOOR    := 34.0
const ORTHO_INDOOR     := 18.0
const ORTHO_INDOOR_BLDG := 22.0
const ORTHO_MIN        := 10.0
const ORTHO_MAX        := 55.0
const ZOOM_STEP        := 3.0

var sim:          Node3D
var cam:          Camera3D
var _target_size: float
var _prev_floor:  int = -1
@export var rotation_sensitivity: float = 0.005
var _rotating: bool = false


func _ready() -> void:
	sim  = get_node(sim_path)
	cam  = $Camera3D
	cam.projection    = Camera3D.PROJECTION_ORTHOGONAL
	cam.size          = ortho_size
	_target_size      = ortho_size
	rotation_degrees  = Vector3(0, 45, 0)
	cam.rotation_degrees = Vector3(-40, 0, 0)
	cam.position      = Vector3(0, 26, 30)


func _process(delta: float) -> void:
	if sim == null:
		return

	# Следим за этажом — автозум при переходе
	var fl: int = sim.p_floor
	if fl != _prev_floor:
		if fl == 0:
			_target_size = ORTHO_OUTDOOR
		elif fl <= Tuning.MALL_FLOORS:
			_target_size = ORTHO_INDOOR
		else:
			_target_size = ORTHO_INDOOR_BLDG
		_prev_floor = fl

	# Плавное изменение размера
	cam.size = lerpf(cam.size, _target_size, 1.0 - exp(-6.0 * delta))

	# Следим за игроком (по Y учитываем этаж)
	var ty := MapGen.floor_y3d(fl)
	var t  := Vector3(sim.p_pos.x, ty, sim.p_pos.y)
	global_position = global_position.lerp(t, 1.0 - exp(-follow_lerp * delta))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = mb.pressed
			get_viewport().set_input_as_handled()
			return

		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_size = clampf(_target_size - ZOOM_STEP, ORTHO_MIN, ORTHO_MAX)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_size = clampf(_target_size + ZOOM_STEP, ORTHO_MIN, ORTHO_MAX)
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _rotating:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		rotation.y -= motion.screen_relative.x * rotation_sensitivity
		get_viewport().set_input_as_handled()
