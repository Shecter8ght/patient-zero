extends SceneTree
func _initialize() -> void: call_deferred("capture")
func capture() -> void:
	var stage := (load("res://scenes/assets/animation_showcase.tscn") as PackedScene).instantiate()
	root.add_child(stage);stage.set_process(false)
	root.size = Vector2i(1280,720)
	await process_frame
	for clip in ["zombie_idle", "zombie_walk", "zombie_run", "bite"]:
		stage.set_clip(clip);stage.advance(0.25)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art_source/previews/animation_"+clip+".png")
	for clip in ["zombie_walk", "bite"]:
		var path: String = "res://art_source/previews/"+clip+"_frames"
		DirAccess.make_dir_recursive_absolute(path)
		stage.set_clip(clip)
		for frame in (36 if clip == "zombie_walk" else 24):
			stage.advance(1.0/24.0)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(path+"/frame_%03d.png" % frame)
	print("ZOMBIE_GPU_CAPTURE_COMPLETE ", RenderingServer.get_video_adapter_name())
	quit()
