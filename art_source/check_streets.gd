extends SceneTree
var failures: Array[String]=[]
func require(ok: bool,message: String) -> void:
	if not ok and failures.size()<30: failures.append(message)
func _initialize() -> void: call_deferred("check")
func check() -> void:
	var map=root.get_node("MapGen")
	map.generate()
	var counts: Dictionary={}
	for prop in map.street_data["props"]:
		counts[prop["kind"]]=counts.get(prop["kind"],0)+1
		require(map.is_blocked(prop["center"],.35,0),"Missing prop collision")
		var pushed: Vector2=map.push_out(prop["center"],.35,0)
		require(pushed.distance_to(prop["center"])>.1,"Cannot exit prop center")
		for tr in map.transitions:
			if tr["from_floor"]==0:
				require(not prop["rect"].grow(.35).intersects(tr["rect"]),"Blocked entrance")
	require(counts.get("sedan",0)+counts.get("hatchback",0)==6,"Six parked cars")
	require(map.street_data["stops"].is_empty(),"No active boarding areas")
	# Test connected walking space with the same radius as moving characters.
	var start:=Vector2i(-130,-130)
	var visited: Dictionary={start:true}
	var queue: Array[Vector2i]=[start]
	var cursor:=0
	while cursor<queue.size():
		var cell: Vector2i=queue[cursor]
		cursor+=1
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i=cell+direction
			if absi(next.x)>138 or absi(next.y)>138 or visited.has(next): continue
			if map.is_blocked(Vector2(next)*.5,.35,0): continue
			visited[next]=true
			queue.append(next)
	for point in map.spawn_points:
		require(visited.has(Vector2i((point*2).round())),"Disconnected outdoor spawn")
	for tr in map.transitions:
		if tr["to_floor"]==0:
			var cell:=Vector2i((tr["dest"]*2).round())
			require(visited.has(cell),"Outdoor landing unreachable")
	var n: int=map.buildings.size()
	map.generate()
	require(map.buildings.size()==n,"Layout generation idempotent")
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	var renderer=game.get_node("MapRenderer")
	var streets=renderer.get_node("StreetEnvironment")
	require(streets.visible,"Streets visible outdoors")
	game.p_floor=1
	renderer._process(1.0)
	require(not streets.visible,"Streets hidden inside mall")
	game.p_floor=0
	renderer._process(1.0)
	require(streets.visible,"Streets restored after exit")
	var report={"passed":failures.is_empty(),"failures":failures,"props":counts,"outdoor_reachable_cells":visited.size(),"spawn_points":map.spawn_points.size(),"surface_patches":map.street_data["surfaces"].size(),"agents":game.pos.size()}
	FileAccess.open("res://art_source/streets_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
