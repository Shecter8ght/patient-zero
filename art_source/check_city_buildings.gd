extends SceneTree
func _initialize() -> void:
	call_deferred("check")
func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var renderer = game.get_node("MapRenderer")
	var count := 0
	for entry in root.get_node("MapGen").building_data:
		var fid: int = entry["floor_id"]
		var model = renderer.get_node_or_null("CityBuilding%d" % fid)
		if model == null: continue
		count += 1
		assert(model.scale == Vector3.ONE)
		var walls = model.find_child("Walls", true, false)
		var roof = model.find_child("Roof", true, false)
		assert(walls.mesh.get_surface_count() == 1)
		assert(roof.mesh.get_surface_count() == 1)
		assert(walls.get_surface_override_material(0) != roof.get_surface_override_material(0))
		game.p_floor = fid
		game.p_pos = entry["rect"].get_center()
		renderer._process(2.0)
		assert(roof.get_surface_override_material(0).albedo_color.a < 0.001)
		game.p_floor = 0
		game.p_pos = Vector2(1000,1000)
		renderer._process(2.0)
		assert(roof.get_surface_override_material(0).albedo_color.a > 0.99)
	assert(count == renderer.CITY_BUILDINGS.ENTRIES.size())
	print("CITY_BUILDINGS_PASSED: ", count, " exact-size instances, independent materials, roof hiding and restoration")
	quit()
