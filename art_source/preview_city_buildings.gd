extends SceneTree
func _initialize() -> void:
	call_deferred("preview")
func preview() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var ids := ["apartment", "utility", "office"]
	for i in ids.size():
		var model = load("res://assets/models/buildings/building_%s_a.glb" % ids[i]).instantiate()
		stage.add_child(model)
		model.position.x = (i - 1) * 19.0
		var label := Label3D.new()
		label.text = ids[i].to_upper()
		label.position = Vector3(model.position.x, 0.2, 9)
		label.font_size = 64
		label.pixel_size = 0.018
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stage.add_child(label)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(100,100)
	ground.position.y = -0.22
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("29343b")
	ground.material_override = mat
	stage.add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-30,0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202b35")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("bacbd5")
	environment.environment.ambient_light_energy = 0.5
	stage.add_child(environment)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(27,36,60)
	camera.look_at(Vector3(0,6,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 66
	camera.current = true
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://art_source/previews/city_buildings_godot.png")
	print("CITY_PREVIEW_SAVED")
	quit()
