extends SceneTree
func _initialize() -> void: call_deferred("preview")
func capture(path: String) -> void:
	for i in 18: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://art_source/previews/"+path)
func preview() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.get_node("HUD").hide()
	var cam:=Camera3D.new()
	game.add_child(cam)
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	cam.current=true
	cam.position=Vector3(100,115,-115)
	cam.look_at(Vector3(0,0,0))
	cam.size=173
	await capture("streets_city.png")
	game.p_pos=Vector2(0,-33)
	cam.position=Vector3(26,31,-63)
	cam.look_at(Vector3(-9,0,-31))
	cam.size=61
	await capture("streets_mall_plaza.png")
	cam.position=Vector3(-10,20,-52)
	cam.look_at(Vector3(-27,0,-34))
	cam.size=32
	await capture("streets_parking.png")
	game.p_pos=Vector2(0,-60)
	cam.position=Vector3(15,17,-83)
	cam.look_at(Vector3(1,0,-61))
	cam.size=29
	await capture("streets_bus_stop.png")
	game.get_node("HUD").show()
	game.get_node("CameraRig/Camera3D").current=true
	game.p_pos=Vector2(-15,-36)
	await capture("streets_gameplay.png")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game.set_physics_process(true)
	for i in 60: await process_frame
	var samples: Array[float]=[]
	var previous:=Time.get_ticks_usec()
	for i in 240:
		await process_frame
		var now:=Time.get_ticks_usec()
		samples.append(float(now-previous)/1000)
		previous=now
	samples.sort()
	var sum:=0.0
	for sample in samples: sum+=sample
	var report={"frames":240,"agents":game.pos.size(),"mean_frame_ms":sum/240,"p95_frame_ms":samples[228],"vsync":false,"floor":game.p_floor}
	FileAccess.open("res://art_source/streets_render_smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STREETS_PREVIEW_COMPLETE ",JSON.stringify(report))
	quit()
