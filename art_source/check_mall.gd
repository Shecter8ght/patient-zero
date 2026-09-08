extends SceneTree
var failures: Array[String] = []
func require(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void:
	call_deferred("check")
func check() -> void:
	var map = root.get_node("MapGen")
	map.generate()
	require(map.mall_rect.size == Vector2(48,48), "Mall footprint")
	for entry in map.building_data:
		if not entry["is_mall"]:
			require(not entry["rect"].intersects(map.mall_rect.grow(Tuning.MALL_CLEARANCE)), "City overlaps mall")
	for pt in map.spawn_points:
		require(not map.mall_rect.has_point(pt), "Outdoor spawn inside mall")
	for tr in map.transitions:
		if tr["from_floor"] <= Tuning.MALL_FLOORS and tr["to_floor"] <= Tuning.MALL_FLOORS:
			require(not map.is_blocked(tr["dest"], .35, tr["to_floor"]), "Blocked destination")
	var entry_point := Vector2(0, map.mall_rect.position.y - .5)
	var pushed: Vector2 = map.push_out(entry_point, .35, 0)
	require(not map.check_transition(pushed, 0).is_empty(), "Entrance unreachable after collision")
	var reach_counts: Array = []
	for fl in range(1,Tuning.MALL_FLOORS+1):
		# Flood fill actual collision map at 0.5 m spacing, using agent radius.
		var visited := {}
		var queue: Array[Vector2i] = [Vector2i(0,-38)]
		visited[queue[0]] = true
		var cursor := 0
		while cursor < queue.size():
			var cell: Vector2i = queue[cursor]
			cursor += 1
			for dir in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var next: Vector2i = cell + dir
				if visited.has(next): continue
				var point := Vector2(next)*.5
				if map.is_blocked(point,.35,fl): continue
				visited[next]=true
				queue.append(next)
		reach_counts.append(queue.size())
		for pt in map.mall_spawns[fl-1]:
			require(visited.has(Vector2i((pt*2).round())), "Disconnected spawn floor %d" % fl)
		for shop in map.mall_shops[fl-1]:
			require(visited.has(Vector2i((shop["center"]*2).round())), "Inaccessible shop floor %d" % fl)
		for tr in map.transitions:
			if tr["from_floor"] == fl:
				require(visited.has(Vector2i((tr["rect"].get_center()*2).round())), "Unreachable escalator/exit")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	var renderer = game.get_node("MapRenderer")
	for tr in map.transitions:
		if tr["from_floor"] <= Tuning.MALL_FLOORS and tr["to_floor"] <= Tuning.MALL_FLOORS:
			game.p_floor=tr["from_floor"]
			game.p_pos=tr["rect"].get_center()
			game.p_floor_cd=0
			game.p_vel=Vector2.ZERO
			game._update_player(0.0)
			require(game.p_floor == tr["to_floor"], "Actual player transition")
			require(game.p_pos.is_equal_approx(tr["dest"]), "Actual player landing")
	for fl in range(1,Tuning.MALL_FLOORS+1):
		game.p_floor=fl
		renderer._process(1.0)
		require(not renderer._mall_exterior.visible,"Exterior hides indoors")
		require(not game.get_node("Ground").visible,"No overlapping ground below first floor")
		for other in Tuning.MALL_FLOORS:
			require(renderer._floor_nodes[other].visible == (other+1 == fl),"Only active floor visible")
		var floor_node = renderer._floor_nodes[fl-1]
		require(is_equal_approx(floor_node.global_position.y,map.floor_y3d(fl)),"Floor height matches actors")
		for outdoor in renderer._outdoor_nodes:
			require(not outdoor.visible,"Outdoor geometry hidden indoors")
	game.p_floor=0
	renderer._process(1.0)
	require(renderer._mall_exterior.visible,"Exterior restored")
	require(game.pos.size()==Tuning.AGENT_COUNT,"Agent count unchanged")
	var report={"passed":failures.is_empty(),"failures":failures,"reachable_cells_per_floor":reach_counts,"agents":game.pos.size(),"mall_size":48,"floors":Tuning.MALL_FLOORS}
	FileAccess.open("res://art_source/mall_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
