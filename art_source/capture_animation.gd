extends SceneTree
func _initialize() -> void: call_deferred("capture")
func capture() -> void:
	var stage := (load("res://scenes/assets/animation_showcase.tscn") as PackedScene).instantiate()
	root.add_child(stage);stage.set_process(false)
	root.size = Vector2i(1280,720)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://art_source/previews/animation_frames")
	for clip in ["walk","run","grab","fall","phone","photo"]:
		stage.set_clip(clip)
		stage.advance(0.25 if clip != "fall" else 1.0)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art_source/previews/animation_"+clip+".png")
	stage.set_clip("walk")
	for frame in 48:
		stage.advance(1.0/24.0)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art_source/previews/animation_frames/frame_%03d.png" % frame)
	print("ANIMATION_GPU_CAPTURE_COMPLETE ", RenderingServer.get_video_adapter_name())
	quit()
