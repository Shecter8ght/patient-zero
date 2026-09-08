extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var renderer = game.get_node("MapRenderer")
	var houses := 0
	for child in renderer.get_children():
		if str(child.name).begins_with("House"):
			houses += 1
	assert(houses > 0)
	assert(not game.has_method("_tick_evac"))
	assert(not game.has_method("_tick_route_buses"))
	var streets = renderer.get_node("StreetEnvironment")
	game.p_floor = 1
	renderer._process(1.0)
	assert(not streets.visible)
	game.p_floor = 0
	renderer._process(1.0)
	assert(streets.visible)
	print("Environment integration passed: ", houses, " houses; interior hiding; no evacuation simulation")
	quit()
