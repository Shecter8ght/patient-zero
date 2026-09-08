extends Node3D
## Standalone asset review. Open scenes/assets/model_showcase.tscn and press F6.

const MODELS := ["civilian_normal_a", "civilian_child_a", "civilian_elder_a", "civilian_brute_a", "civilian_journalist_a", "police_officer_a", "swat_officer_a", "patient_zero"]
var camera: Camera3D
var roof: Node3D

func _ready() -> void:
	for i in MODELS.size():
		var asset := load("res://assets/models/characters/" + MODELS[i] + ".glb") as PackedScene
		var model := asset.instantiate() as Node3D
		add_child(model)
		model.position = Vector3((i - 3.5) * 1.5, 0, 4)
		var label := Label3D.new()
		label.text = MODELS[i].replace("civilian_", "").replace("_a", "")
		label.font_size = 28
		label.pixel_size = 0.007
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
		label.position = model.position + Vector3(0, 2.35, 0)
	var home := (load("res://assets/models/buildings/building_house_a.glb") as PackedScene).instantiate() as Node3D
	add_child(home)
	home.position = Vector3(-6, 0, -4)
	roof = home.find_child("Roof", true, false) as Node3D
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(50, 40)
	plane.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("29333b")
	plane.material_override = material
	plane.position.y = -0.015
	add_child(plane)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("202830")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b4c5d0")
	world.environment.ambient_light_energy = 0.5
	add_child(world)
	camera = Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 27
	camera.position = Vector3(19, 23, 27)
	camera.look_at(Vector3(-1, 0, 0))
	camera.current = true
	var ui := CanvasLayer.new()
	add_child(ui)
	var help := Label.new()
	help.text = "PATIENT ZERO / MODEL BATCH 01\nWheel: zoom | Arrow keys: pan | R: roof"
	help.position = Vector2(24, 20)
	ui.add_child(help)

func _process(delta: float) -> void:
	var direction := Vector3(float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)), 0, float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP)))
	camera.position += direction * delta * 10

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: camera.size = maxf(6, camera.size - 2)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera.size = minf(55, camera.size + 2)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and roof:
		roof.visible = not roof.visible
