extends SceneTree
func _initialize() -> void: call_deferred("capture")
func capture() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var samples: Array[float] = []
	var before := Time.get_ticks_usec()
	for frame in 240:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if frame >= 60: samples.append(float(now-before)/1000.0)
		before = now
		if frame == 120: root.get_texture().get_image().save_png("res://art_source/previews/animated_game.png")
	samples.sort()
	var avg := 0.0
	for ms in samples: avg += ms
	avg /= samples.size()
	var out := FileAccess.open("res://art_source/animation_render_smoke.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"agents":scene.pos.size(),"batches":scene.get_node("Agents").batches.size(),"sample_frames":samples.size(),"mean_frame_ms":avg,"p95_frame_ms":samples[int(samples.size()*.95)],"note":"Short local smoke run, includes simulation and rendering; not a sustained benchmark or minimum-spec guarantee."},"\t"))
	print("ANIMATED_GAME_RENDER_COMPLETE")
	quit()
