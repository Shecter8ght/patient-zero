extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute("res://tests/output")
	var hud = game.get_node("HUD")
	for sample in [[Tuning.ARCH_CHILD, "child"], [Tuning.ARCH_NORMAL, "normal"], [Tuning.ARCH_BRUTE, "brute"]]:
		game.p_grab = 0
		game.archetype[0] = sample[0]
		hud._grab_zone_target = -1
		for frame in 4:
			await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/output/slider_%s.png" % sample[1])
	print("SLIDER_ZONE_CAPTURE_COMPLETE")
	quit()
